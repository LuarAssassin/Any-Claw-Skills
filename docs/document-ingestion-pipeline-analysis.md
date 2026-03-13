# Document Ingestion Pipeline 分析

## 目录
1. [核心概念](#核心概念)
2. [CoPaw ReMe 集成](#copaw-reme-集成)
3. [kimi-cli 基础文件读取](#kimi-cli-基础文件读取)
4. [openclaw 完整文档摄取流程](#openclaw-完整文档摄取流程)
5. [opencode 代码中心方法](#opencode-代码中心方法)
6. [架构对比与推荐](#架构对比与推荐)

---

## 核心概念

### 文档摄取流程概览

```
┌─────────────────────────────────────────────────────────────┐
│                    Document Ingestion Pipeline              │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │   Ingest     │  │    Chunk     │  │    Embed         │  │
│  │              │  │              │  │                  │  │
│  │ - Parse PDF  │  │ - Fixed size │  │ - OpenAI         │  │
│  │ - Extract MD │  │ - Semantic   │  │ - Local Model    │  │
│  │ - OCR Image  │  │ - Structural │  │ - Multimodal     │  │
│  └──────┬───────┘  └──────┬───────┘  └────────┬─────────┘  │
│         │                 │                   │            │
│         └─────────────────┼───────────────────┘            │
│                           ▼                                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                    Index                              │   │
│  │  - Vector Store (HNSW/IVF)  - Full-Text Search        │   │
│  │  - Hybrid Search            - Metadata Filter         │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 分块策略对比

| 策略 | 描述 | 优点 | 缺点 |
|------|------|------|------|
| **固定字符** | 每块 N 个字符 | 简单、均匀 | 可能切断语义 |
| **固定 Token** | 每块 N 个 token | LLM 友好 | 需要 tokenizer |
| **语义分块** | 按句子/段落边界 | 保持语义完整 | 块大小不均匀 |
| **结构分块** | 按章节/标题 | 保留文档结构 | 需要格式识别 |
| **重叠滑动** | 滑动窗口 + 重叠 | 保留上下文 | 存储冗余 |

---

## CoPaw ReMe 集成

### 整体架构

CoPaw 使用外部 **ReMe (ReMeLight)** 库处理文档摄取，通过环境变量配置。

```
┌─────────────────────────────────────────────────────────────┐
│                    CoPaw Document Pipeline                  │
│                                                             │
│  ┌─────────────────┐      ┌──────────────────────┐        │
│  │   MemoryManager │─────▶│   ReMe Library       │        │
│  │                 │      │   (External)          │        │
│  │ - search()      │      │                      │        │
│  │ - add_memory()  │      │ - Vector Store        │        │
│  │ - compact()     │      │ - FTS Search          │        │
│  └─────────────────┘      │ - Embedding           │        │
│                           └──────────────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

### 配置驱动架构

```python
# CoPaw 文档摄取配置（环境变量）
EMBEDDING_API_KEY          # API key for embedding service
EMBEDDING_BASE_URL         # Default: dashscope (阿里)
EMBEDDING_MODEL_NAME       # 模型名称
EMBEDDING_DIMENSIONS       # Default: 1024
EMBEDDING_CACHE_ENABLED    # Default: true
EMBEDDING_MAX_CACHE_SIZE   # Default: 2000
EMBEDDING_MAX_INPUT_LENGTH # Default: 8192
EMBEDDING_MAX_BATCH_SIZE   # Default: 10
FTS_ENABLED                # 全文搜索 (default: true)
MEMORY_STORE_BACKEND       # auto/local/chroma
```

### Memory Manager 实现

```python
# src/copaw/agents/memory/memory_manager.py
class MemoryManager:
    """Memory management wrapper around ReMe library."""

    def __init__(self):
        self.vector_enabled = self._check_vector_config()
        self.memory_backend = self._select_backend()
        self.embedding_cache = {}

    def _check_vector_config(self) -> bool:
        """Check if vector search is configured."""
        return bool(
            os.getenv("EMBEDDING_API_KEY") and
            os.getenv("EMBEDDING_MODEL_NAME")
        )

    def _select_backend(self) -> str:
        """Select storage backend based on platform."""
        if platform.system() == "Windows":
            return "local"  # Windows 使用本地文件存储
        return "chroma"   # 其他使用 ChromaDB

    async def add_memory(
        self,
        content: str,
        metadata: Dict[str, Any] = None,
    ) -> bool:
        """Add content to memory with optional embedding."""
        # 调用 ReMe 库
        return await self._reme.add(
            content=content,
            metadata=metadata or {},
            vectorize=self.vector_enabled,
        )

    async def search(
        self,
        query: str,
        top_k: int = 5,
        use_vector: bool = True,
    ) -> List[MemoryResult]:
        """Search memory with hybrid approach."""
        if use_vector and self.vector_enabled:
            # 向量 + 全文混合搜索
            return await self._reme.hybrid_search(
                query=query,
                top_k=top_k,
                vector_weight=0.7,
                text_weight=0.3,
            )
        else:
            # 仅全文搜索
            return await self._reme.fts_search(
                query=query,
                top_k=top_k,
            )

    async def compact_memory(
        self,
        messages: List[Message],
    ) -> str:
        """Compact messages into summary."""
        # 使用 LLM 生成摘要
        summary = await self._llm.summarize(messages)

        # 存储摘要到 ReMe
        await self._reme.add(
            content=summary,
            metadata={"type": "compaction", "count": len(messages)},
            vectorize=True,
        )

        return summary
```

### 分块与嵌入策略

CoPaw 依赖 ReMe 内部实现，从配置推断：

```python
# 推测的 ReMe 分块策略
DEFAULT_CHUNK_SIZE = 400        # tokens
DEFAULT_CHUNK_OVERLAP = 80      # tokens (20%)
MAX_INPUT_LENGTH = 8192         # 最大输入长度

# Token 估算 (字符 / 4)
def estimate_tokens(text: str) -> int:
    return len(text) // 4

# 分块逻辑（推测）
def chunk_text(text: str, chunk_tokens: int = 400, overlap: int = 80) -> List[str]:
    chunk_chars = chunk_tokens * 4
    overlap_chars = overlap * 4

    chunks = []
    start = 0
    while start < len(text):
        end = start + chunk_chars
        chunk = text[start:end]
        chunks.append(chunk)
        start = end - overlap_chars  # 重叠

    return chunks
```

---

## kimi-cli 基础文件读取

### 架构定位

kimi-cli **没有完整的文档摄取流程**，主要聚焦于 CLI 交互和 Wire 协议。

```
┌─────────────────────────────────────────────────────────────┐
│                    kimi-cli File Handling                   │
│                                                             │
│  ┌─────────────────┐      ┌──────────────────────┐        │
│  │   File Read     │─────▶│   Context Builder    │        │
│  │   (Basic)       │      │   (No chunking)       │        │
│  │                 │      │                      │        │
│  │ - read_file     │      │ - Direct insert      │        │
│  │ - list_files    │      │ - No embedding        │        │
│  │ - search_files  │      │ - No indexing         │        │
│  └─────────────────┘      └──────────────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

### 文件读取工具

```python
# src/kimi_cli/tools/file.py
class FileReadTool:
    """Basic file reading without chunking."""

    async def execute(
        self,
        path: str,
        offset: int = 0,
        limit: int = 100,
    ) -> str:
        """Read file content directly."""
        async with aiofiles.open(path, "r") as f:
            if offset > 0:
                await f.seek(offset)
            content = await f.read(limit * 100)  # Approximate chars

        return content

    async def search_in_file(
        self,
        path: str,
        pattern: str,
    ) -> List[Match]:
        """Simple grep-like search."""
        matches = []
        async with aiofiles.open(path, "r") as f:
            async for line_num, line in enumerate(f, 1):
                if pattern in line:
                    matches.append(Match(
                        line=line_num,
                        content=line.strip(),
                    ))
        return matches
```

### 上下文构建

```python
# src/kimi_cli/context/builder.py
class ContextBuilder:
    """Build context from files without ingestion pipeline."""

    def __init__(self, max_tokens: int = 8000):
        self.max_tokens = max_tokens
        self.contents = []

    def add_file(self, path: str, content: str) -> None:
        """Add file content directly to context."""
        self.contents.append(f"### File: {path}\n{content}")

    def build(self) -> str:
        """Build final context string."""
        # 简单截断，无智能分块
        combined = "\n\n".join(self.contents)
        if len(combined) > self.max_tokens * 4:
            combined = combined[:self.max_tokens * 4]
        return combined
```

---

## openclaw 完整文档摄取流程

### 整体架构

openclaw 拥有 **最完整的文档摄取流程**，支持多 embedding 提供商、混合搜索、增量更新。

```
┌─────────────────────────────────────────────────────────────┐
│                    openclaw Ingestion Pipeline              │
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │   Parse     │  │    Chunk    │  │     Embed           │ │
│  │             │  │             │  │                     │ │
│  │ - Markdown  │  │ - Line-based│  │ - OpenAI            │ │
│  │ - Images    │  │ - 400 tokens│  │ - Gemini            │ │
│  │ - Sessions  │  │ - 80 overlap│  │ - Voyage            │ │
│  └──────┬──────┘  └──────┬──────┘  │ - Mistral           │ │
│         │                │         │ - Ollama            │ │
│         └────────────────┼─────────┴─────────────────────┘ │
│                          ▼                                   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                    Index (SQLite)                     │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌──────────────┐ │   │
│  │  │ chunks      │  │ chunks_vec  │  │ chunks_fts   │ │   │
│  │  │ (metadata)  │  │ (vectors)   │  │ (FTS5)       │ │   │
│  │  └─────────────┘  └─────────────┘  └──────────────┘ │   │
│  │                                                      │   │
│  │  Hybrid Search: Vector + FTS + MMR + Temporal      │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 文件解析与发现

```typescript
// src/memory/internal.ts
export interface MemoryFile {
  path: string;
  source: "memory" | "session" | "extra";
  hash: string;
  mtime: number;
  size: number;
}

export async function listMemoryFiles(
  workspaceDir: string,
  extraPaths?: string[],
  multimodal?: MemoryMultimodalSettings,
): Promise<string[]> {
  const files: string[] = [];

  // 1. 扫描 memory/ 目录
  const memoryDir = path.join(workspaceDir, "memory");
  if (await fs.pathExists(memoryDir)) {
    const mdFiles = await glob("**/*.md", { cwd: memoryDir });
    files.push(...mdFiles.map((f) => path.join(memoryDir, f)));
  }

  // 2. 扫描 MEMORY.md
  const memoryFile = path.join(workspaceDir, "MEMORY.md");
  if (await fs.pathExists(memoryFile)) {
    files.push(memoryFile);
  }

  // 3. 扫描额外路径
  if (extraPaths) {
    for (const extraPath of extraPaths) {
      const resolved = path.resolve(workspaceDir, extraPath);
      if (await fs.pathExists(resolved)) {
        files.push(resolved);
      }
    }
  }

  // 4. 扫描多模态文件
  if (multimodal?.enabled) {
    const imageExtensions = ["png", "jpg", "jpeg", "gif", "webp"];
    for (const ext of imageExtensions) {
      const images = await glob(`**/*.${ext}`, { cwd: workspaceDir });
      files.push(...images.map((f) => path.join(workspaceDir, f)));
    }
  }

  return files;
}
```

### 分块策略

```typescript
// src/memory/internal.ts
export interface MemoryChunk {
  startLine: number;
  endLine: number;
  text: string;
  hash: string;
  embeddingInput?: EmbeddingInput;
}

export interface ChunkingConfig {
  tokens: number;    // 每块 token 数 (default: 400)
  overlap: number;   // 重叠 token 数 (default: 80)
}

// Token 到字符的转换系数 (~4 chars/token)
const CHARS_PER_TOKEN = 4;

export function chunkMarkdown(
  content: string,
  chunking: ChunkingConfig,
): MemoryChunk[] {
  const maxChars = Math.max(32, chunking.tokens * CHARS_PER_TOKEN);
  const overlapChars = Math.max(0, chunking.overlap * CHARS_PER_TOKEN);

  const lines = content.split("\n");
  const chunks: MemoryChunk[] = [];

  let currentChunk: string[] = [];
  let currentChars = 0;
  let startLine = 0;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const lineChars = line.length + 1; // +1 for newline

    // 检查是否需要分块
    if (currentChars + lineChars > maxChars && currentChunk.length > 0) {
      // 保存当前块
      const chunkText = currentChunk.join("\n");
      chunks.push({
        startLine: startLine + 1, // 1-indexed
        endLine: i,
        text: chunkText,
        hash: createHash("sha256").update(chunkText).digest("hex"),
      });

      // 处理重叠：保留最后 N 行
      if (overlapChars > 0) {
        let overlapLines: string[] = [];
        let overlapCharCount = 0;
        for (let j = currentChunk.length - 1; j >= 0; j--) {
          const overlapLine = currentChunk[j];
          if (overlapCharCount + overlapLine.length > overlapChars) {
            break;
          }
          overlapLines.unshift(overlapLine);
          overlapCharCount += overlapLine.length + 1;
        }
        currentChunk = overlapLines;
        currentChars = overlapCharCount;
        startLine = i - overlapLines.length;
      } else {
        currentChunk = [];
        currentChars = 0;
        startLine = i;
      }
    }

    currentChunk.push(line);
    currentChars += lineChars;
  }

  // 处理最后一块
  if (currentChunk.length > 0) {
    const chunkText = currentChunk.join("\n");
    chunks.push({
      startLine: startLine + 1,
      endLine: lines.length,
      text: chunkText,
      hash: createHash("sha256").update(chunkText).digest("hex"),
    });
  }

  return chunks;
}
```

### Embedding 提供商支持

```typescript
// src/memory/embeddings.ts
export type EmbeddingProviderId =
  | "openai"
  | "local"
  | "gemini"
  | "voyage"
  | "mistral"
  | "ollama";

export interface EmbeddingProvider {
  id: EmbeddingProviderId;
  name: string;
  models: string[];
  maxBatchSize: number;
  supportsBatchAPI: boolean;
  supportsMultimodal?: boolean;
}

export const EMBEDDING_PROVIDERS: Record<EmbeddingProviderId, EmbeddingProvider> = {
  openai: {
    id: "openai",
    name: "OpenAI",
    models: ["text-embedding-3-small", "text-embedding-3-large", "text-embedding-ada-002"],
    maxBatchSize: 2048,
    supportsBatchAPI: true,
  },
  gemini: {
    id: "gemini",
    name: "Google Gemini",
    models: ["gemini-embedding-001", "gemini-embedding-2-preview"],
    maxBatchSize: 100,
    supportsBatchAPI: true,
    supportsMultimodal: true,  // 支持图片嵌入
  },
  voyage: {
    id: "voyage",
    name: "Voyage AI",
    models: ["voyage-4-large"],
    maxBatchSize: 128,
    supportsBatchAPI: true,
  },
  mistral: {
    id: "mistral",
    name: "Mistral AI",
    models: ["mistral-embed"],
    maxBatchSize: 128,
    supportsBatchAPI: false,
  },
  ollama: {
    id: "ollama",
    name: "Ollama (Local)",
    models: ["nomic-embed-text", "mxbai-embed-large"],
    maxBatchSize: 32,
    supportsBatchAPI: false,
  },
  local: {
    id: "local",
    name: "Local (node-llama-cpp)",
    models: ["gguf models"],
    maxBatchSize: 16,
    supportsBatchAPI: false,
  },
};

// Embedding 函数
export async function embedChunks(
  chunks: MemoryChunk[],
  provider: EmbeddingProviderId,
  model: string,
  apiKey: string,
): Promise<EmbeddedChunk[]> {
  const providerConfig = EMBEDDING_PROVIDERS[provider];

  // 批处理
  const batches = chunk(chunks, providerConfig.maxBatchSize);
  const embeddings: number[][] = [];

  for (const batch of batches) {
    const batchEmbeddings = await embedBatch(batch, provider, model, apiKey);
    embeddings.push(...batchEmbeddings);
  }

  return chunks.map((chunk, i) => ({
    ...chunk,
    embedding: embeddings[i],
  }));
}

async function embedBatch(
  chunks: MemoryChunk[],
  provider: EmbeddingProviderId,
  model: string,
  apiKey: string,
): Promise<number[][]> {
  switch (provider) {
    case "openai":
      return embedOpenAI(chunks, model, apiKey);
    case "gemini":
      return embedGemini(chunks, model, apiKey);
    case "voyage":
      return embedVoyage(chunks, model, apiKey);
    case "ollama":
      return embedOllama(chunks, model);
    case "local":
      return embedLocal(chunks, model);
    default:
      throw new Error(`Unknown provider: ${provider}`);
  }
}
```

### 索引 Schema 设计

```typescript
// src/memory/memory-schema.ts

// 文件表
export const CREATE_FILES_TABLE = `
CREATE TABLE IF NOT EXISTS files (
  path TEXT PRIMARY KEY,
  source TEXT NOT NULL DEFAULT 'memory',
  hash TEXT NOT NULL,
  mtime INTEGER NOT NULL,
  size INTEGER NOT NULL
)`;

// 分块表
export const CREATE_CHUNKS_TABLE = `
CREATE TABLE IF NOT EXISTS chunks (
  id TEXT PRIMARY KEY,
  path TEXT NOT NULL,
  source TEXT NOT NULL,
  start_line INTEGER NOT NULL,
  end_line INTEGER NOT NULL,
  hash TEXT NOT NULL,
  model TEXT NOT NULL,
  text TEXT NOT NULL,
  updated_at INTEGER NOT NULL
)`;

// 向量表 (sqlite-vec 扩展)
export const CREATE_VECTOR_TABLE = `
CREATE VIRTUAL TABLE IF NOT EXISTS chunks_vec USING vec0(
  chunk_id TEXT PRIMARY KEY,
  embedding FLOAT[{dimensions}] DISTANCE_METRIC=COSINE
)`;

// 全文搜索表 (FTS5)
export const CREATE_FTS_TABLE = `
CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
  chunk_id,
  text,
  content='chunks',
  content_rowid='id'
)`;

// Embedding 缓存表
export const CREATE_EMBEDDING_CACHE_TABLE = `
CREATE TABLE IF NOT EXISTS embedding_cache (
  provider TEXT NOT NULL,
  model TEXT NOT NULL,
  provider_key TEXT NOT NULL,
  hash TEXT NOT NULL,
  embedding TEXT NOT NULL,
  dims INTEGER,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (provider, model, provider_key, hash)
)`;

// 索引
export const CREATE_INDEXES = `
CREATE INDEX IF NOT EXISTS idx_chunks_path ON chunks(path);
CREATE INDEX IF NOT EXISTS idx_chunks_hash ON chunks(hash);
CREATE INDEX IF NOT EXISTS idx_chunks_updated ON chunks(updated_at);
CREATE INDEX IF NOT EXISTS idx_embedding_cache_hash ON embedding_cache(hash);
`;
```

### 混合搜索实现

```typescript
// src/memory/hybrid.ts
export interface HybridSearchResult {
  chunkId: string;
  score: number;
  vectorScore?: number;
  textScore?: number;
  metadata: {
    path: string;
    startLine: number;
    endLine: number;
    text: string;
  };
}

export async function hybridSearch(params: {
  query: string;
  queryEmbedding: number[];
  topK: number;
  vectorWeight: number;  // e.g., 0.7
  textWeight: number;    // e.g., 0.3
  mmr?: {
    enabled: boolean;
    lambda: number;      // 0-1, diversity vs relevance tradeoff
  };
  temporalDecay?: {
    enabled: boolean;
    halfLife: number;    // days
  };
}): Promise<HybridSearchResult[]> {
  // 1. 向量搜索
  const vectorResults = await vectorSearch({
    embedding: params.queryEmbedding,
    topK: params.topK * 2,  // 获取更多用于重排序
  });

  // 2. 全文搜索
  const textResults = await ftsSearch({
    query: params.query,
    topK: params.topK * 2,
  });

  // 3. 合并结果
  let merged = mergeHybridResults({
    vector: vectorResults,
    keyword: textResults,
    vectorWeight: params.vectorWeight,
    textWeight: params.textWeight,
  });

  // 4. MMR 重排序（多样性）
  if (params.mmr?.enabled) {
    merged = applyMMR(merged, params.queryEmbedding, params.mmr.lambda);
  }

  // 5. 时间衰减（时效性）
  if (params.temporalDecay?.enabled) {
    merged = applyTemporalDecay(merged, params.temporalDecay.halfLife);
  }

  return merged.slice(0, params.topK);
}

// MMR (Maximal Marginal Relevance)
function applyMMR(
  results: HybridSearchResult[],
  queryEmbedding: number[],
  lambda: number,
): HybridSearchResult[] {
  const selected: HybridSearchResult[] = [];
  const remaining = [...results];

  while (remaining.length > 0 && selected.length < results.length) {
    let bestScore = -Infinity;
    let bestIdx = 0;

    for (let i = 0; i < remaining.length; i++) {
      const result = remaining[i];

      // 相关性
      const relevance = result.vectorScore || result.score;

      // 多样性（与已选结果的最大相似度）
      let maxSim = 0;
      for (const sel of selected) {
        const sim = cosineSimilarity(
          queryEmbedding,  // 使用 embedding 计算相似度
          sel.metadata.embedding,
        );
        maxSim = Math.max(maxSim, sim);
      }

      // MMR 分数
      const score = lambda * relevance - (1 - lambda) * maxSim;

      if (score > bestScore) {
        bestScore = score;
        bestIdx = i;
      }
    }

    selected.push(remaining[bestIdx]);
    remaining.splice(bestIdx, 1);
  }

  return selected;
}

// 时间衰减
function applyTemporalDecay(
  results: HybridSearchResult[],
  halfLifeDays: number,
): HybridSearchResult[] {
  const now = Date.now();
  const halfLifeMs = halfLifeDays * 24 * 60 * 60 * 1000;

  return results.map((r) => {
    const age = now - r.metadata.updatedAt;
    const decayFactor = Math.pow(0.5, age / halfLifeMs);
    return {
      ...r,
      score: r.score * decayFactor,
    };
  });
}
```

### 增量同步策略

```typescript
// src/memory/manager-sync-ops.ts
export interface SyncConfig {
  onSessionStart: boolean;
  onSearch: boolean;
  watch: boolean;
  watchDebounceMs: number;
  intervalMinutes: number;
  sessions: {
    deltaBytes: number;
    deltaMessages: number;
  };
}

export class MemorySyncManager {
  private config: SyncConfig;
  private fileWatcher?: FSWatcher;
  private syncTimer?: NodeJS.Timeout;
  private lastSync: number = 0;

  async start(): Promise<void> {
    // 1. Session 开始时同步
    if (this.config.onSessionStart) {
      await this.sync();
    }

    // 2. 文件监听
    if (this.config.watch) {
      this.startFileWatcher();
    }

    // 3. 定时同步
    if (this.config.intervalMinutes > 0) {
      this.startIntervalSync();
    }
  }

  private startFileWatcher(): void {
    const debouncedSync = debounce(
      () => this.sync({ reason: "file-change" }),
      this.config.watchDebounceMs,
    );

    this.fileWatcher = watch(
      "./memory",
      { recursive: true },
      (eventType, filename) => {
        if (filename?.endsWith(".md")) {
          debouncedSync();
        }
      },
    );
  }

  private startIntervalSync(): void {
    this.syncTimer = setInterval(
      () => this.sync({ reason: "interval" }),
      this.config.intervalMinutes * 60 * 1000,
    );
  }

  async sync(options?: { reason?: string; force?: boolean }): Promise<void> {
    if (this.isSyncing && !options?.force) {
      return;  // 避免并发同步
    }

    this.isSyncing = true;
    try {
      // 1. 扫描文件变化
      const fileChanges = await this.detectFileChanges();

      // 2. 处理删除的文件
      for (const deleted of fileChanges.deleted) {
        await this.removeFileFromIndex(deleted);
      }

      // 3. 处理新增/修改的文件
      for (const file of [...fileChanges.added, ...fileChanges.modified]) {
        await this.indexFile(file);
      }

      this.lastSync = Date.now();
    } finally {
      this.isSyncing = false;
    }
  }

  private async detectFileChanges(): Promise<{
    added: MemoryFile[];
    modified: MemoryFile[];
    deleted: string[];
  }> {
    // 获取当前文件列表
    const currentFiles = await listMemoryFiles(this.workspaceDir);

    // 获取已索引的文件
    const indexedFiles = await this.db.query<MemoryFile>(
      "SELECT * FROM files",
    );

    const added: MemoryFile[] = [];
    const modified: MemoryFile[] = [];
    const indexedPaths = new Set(indexedFiles.map((f) => f.path));

    for (const file of currentFiles) {
      const indexed = indexedFiles.find((f) => f.path === file.path);
      if (!indexed) {
        added.push(file);
      } else if (indexed.mtime < file.mtime || indexed.hash !== file.hash) {
        modified.push(file);
      }
    }

    const deleted = indexedFiles
      .filter((f) => !currentFiles.some((cf) => cf.path === f.path))
      .map((f) => f.path);

    return { added, modified, deleted };
  }
}
```

---

## opencode 代码中心方法

### 整体架构

opencode **没有向量嵌入流程**，专注于代码文件直接读取和文本搜索。

```
┌─────────────────────────────────────────────────────────────┐
│                    opencode File Handling                   │
│                                                             │
│  ┌─────────────────┐      ┌──────────────────────┐        │
│  │   File Read     │─────▶│   Context Builder    │        │
│  │   (Code-centric)│      │   (Line-based)        │        │
│  │                 │      │                      │        │
│  │ - Line limit    │      │ - No embedding        │        │
│  │ - Grep search   │      │ - No chunking         │        │
│  │ - LSP support   │      │ - Direct insert      │        │
│  └─────────────────┘      └──────────────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

### 文件读取限制

```typescript
// packages/opencode/src/tool/read.ts
const DEFAULT_READ_LIMIT = 2000;   // 最大行数
const MAX_LINE_LENGTH = 2000;      // 单行截断
const MAX_BYTES = 50 * 1024;       // 50KB 上限

export async function readFile(
  filePath: string,
  options?: {
    offset?: number;
    limit?: number;
  },
): Promise<ReadResult> {
  const content = await fs.readFile(filePath, "utf-8");

  // 二进制文件检测
  if (isBinary(content)) {
    return {
      error: `File appears to be binary: ${filePath}`,
    };
  }

  const lines = content.split("\n");

  // 应用限制
  const offset = options?.offset || 0;
  const limit = Math.min(options?.limit || DEFAULT_READ_LIMIT, DEFAULT_READ_LIMIT);

  const sliced = lines.slice(offset, offset + limit);

  // 截断超长行
  const truncated = sliced.map((line) =>
    line.length > MAX_LINE_LENGTH
      ? line.slice(0, MAX_LINE_LENGTH) + "... [truncated]"
      : line,
  );

  return {
    content: truncated.join("\n"),
    totalLines: lines.length,
    returnedLines: truncated.length,
    hasMore: offset + limit < lines.length,
  };
}
```

### Grep 搜索

```typescript
// packages/opencode/src/tool/grep.ts
export async function grep(params: {
  pattern: string;
  paths?: string[];
  include?: string[];
  exclude?: string[];
  caseSensitive?: boolean;
}): Promise<GrepResult[]> {
  const { pattern, paths, include, exclude, caseSensitive } = params;

  // 使用 ripgrep
  const args = [
    "--line-number",
    "--with-filename",
    "--color=never",
    caseSensitive ? "" : "-i",
    pattern,
    ...(paths || ["."]),
  ];

  if (include) {
    for (const glob of include) {
      args.push("--include", glob);
    }
  }

  if (exclude) {
    for (const glob of exclude) {
      args.push("--exclude", glob);
    }
  }

  const { stdout } = await execAsync(`rg ${args.join(" ")}`);

  // 解析结果
  const results: GrepResult[] = [];
  for (const line of stdout.split("\n")) {
    const match = line.match(/^([^:]+):(\d+):(.*)$/);
    if (match) {
      results.push({
        file: match[1],
        line: parseInt(match[2], 10),
        content: match[3],
      });
    }
  }

  return results;
}
```

---

## 架构对比与推荐

### 四项目对比

| 特性 | CoPaw | kimi-cli | openclaw | opencode |
|------|-------|----------|----------|----------|
| **架构** | ReMe 集成 | 基础文件读取 | 完整流程 | 代码中心 |
| **解析格式** | Markdown | 文本 | Markdown + 图片 | 代码文件 |
| **分块** | Token-based | 无 | Line-based (400 tokens) | Line-based (2000 lines) |
| **Embedding** | DashScope/Chroma | 无 | 6+ 提供商 | 无 |
| **向量存储** | Chroma/local | 无 | SQLite-vec | 无 |
| **全文搜索** | ✅ | 基础 grep | ✅ FTS5 | ✅ ripgrep |
| **混合搜索** | ✅ | ❌ | ✅ + MMR | ❌ |
| **增量更新** | ✅ | ❌ | ✅ 文件监听 | ✅ 文件监听 |
| **缓存** | ✅ | ❌ | ✅ SQLite | ❌ |
| **多模态** | 有限 | ❌ | ✅ Gemini | 有限 |

### 推荐混合架构

```
┌─────────────────────────────────────────────────────────────┐
│                    Document Ingestion Pipeline              │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │   Parse      │  │    Chunk     │  │    Embed         │  │
│  │              │  │              │  │                  │  │
│  │ - Markdown   │  │ - Line-aware │  │ - OpenAI         │  │
│  │ - PDF        │  │ - 400 tokens │  │ - Gemini         │  │
│  │ - Word       │  │ - 80 overlap │  │ - Voyage         │  │
│  │ - Image(OCR) │  │ - Metadata   │  │ - Local          │  │
│  └──────┬───────┘  └──────┬───────┘  └────────┬─────────┘  │
│         │                 │                   │            │
│         └─────────────────┼───────────────────┘            │
│                           ▼                                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                    Index (SQLite)                     │   │
│  │                                                      │   │
│  │  chunks (metadata)  │  chunks_vec (vectors)         │   │
│  │  chunks_fts (FTS5)  │  embedding_cache              │   │
│  │                                                      │   │
│  │  Search: Hybrid (Vector 0.7 + FTS 0.3)              │   │
│  │          + MMR Rerank + Temporal Decay              │   │
│  └─────────────────────────────────────────────────────┘   │
│                           │                                 │
│                           ▼                                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Sync Strategy (openclaw)                 │   │
│  │  - File watcher (debounce)                           │   │
│  │  - Session start sync                                │   │
│  │  - Periodic interval sync                            │   │
│  │  - Delta-based updates                               │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 关键设计建议

1. **分块策略**
   - 使用行感知分块（保留代码结构）
   - 400 tokens/块，80 tokens 重叠
   - 保留元数据：文件名、行号、hash

2. **Embedding**
   - 多提供商支持（OpenAI/Gemini/Voyage/Local）
   - 批处理 API 提高效率
   - SQLite 缓存避免重复计算

3. **索引**
   - 混合搜索：向量 + 全文
   - MMR 重排序保证多样性
   - 时间衰减体现时效性

4. **同步**
   - 文件监听实时更新
   - 增量同步（只处理变化文件）
   - 防抖避免频繁重建

---

## 附录：关键代码文件

| 项目 | 关键文件 | 说明 |
|------|----------|------|
| **CoPaw** | `agents/memory/memory_manager.py` | Memory manager |
| **CoPaw** | `agents/tools/memory_search.py` | Memory search tool |
| **openclaw** | `memory/internal.ts` | File discovery & chunking |
| **openclaw** | `memory/embeddings.ts` | Embedding providers |
| **openclaw** | `memory/memory-schema.ts` | SQLite schema |
| **openclaw** | `memory/hybrid.ts` | Hybrid search |
| **openclaw** | `memory/manager-sync-ops.ts` | Sync operations |
| **opencode** | `tool/read.ts` | File reading |
| **opencode** | `tool/grep.ts` | Grep search |

---

*报告生成时间: 2025-03-13*
*分析项目: CoPaw, kimi-cli, openclaw, opencode*
