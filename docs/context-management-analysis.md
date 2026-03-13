# 多轮对话上下文管理机制深度调研报告

## 概述

本报告对四个开源 AI Agent 项目（CoPaw、kimi-cli、openclaw、opencode）的多轮对话上下文管理机制进行了深度技术分析，对比各自的实现策略、优劣，并提出最优解决方案。

---

## 一、各项目实现对比

### 1. CoPaw（Python）

#### 存储架构
- **内存存储**: 使用 `agentscope.memory.InMemoryMemory` + `ReMeInMemoryMemory` 扩展
- **持久化**: `~/.copaw/memory/` 目录
- **工作目录**: 由 `COPAW_WORKING_DIR` 环境变量配置

#### 上下文结构（三区模型）
```
┌─────────────────────────────────────────┐
│ System Prompt (固定)                     │  ← 始终保留
├─────────────────────────────────────────┤
│ 压缩摘要 (可选)                           │  ← 压缩后生成
├─────────────────────────────────────────┤
│ 可压缩区                                 │  ← 超限时被压缩
├─────────────────────────────────────────┤
│ 保留区 (最近 N 条)                        │  ← 始终保留
└─────────────────────────────────────────┘
```

#### Token 计算
- **分词器**: HuggingFace Tokenizer (Qwen2.5-7B-Instruct)
- **回退策略**: 字符数 // 4
- **位置**: `src/copaw/agents/utils/token_counting.py`

```python
def safe_count_str_tokens(text: str) -> int:
    try:
        token_ids = token_counter.tokenizer.encode(text)
        return len(token_ids)
    except Exception:
        return len(text.encode("utf-8")) // 4  # 回退
```

#### 压缩策略
- **触发阈值**: `max_input_length * memory_compact_ratio` (默认 128K * 0.75 = 96K)
- **保留比例**: `memory_reserve_ratio` (默认 10%，即最近 10% 消息保留)
- **最小保留**: `MEMORY_COMPACT_KEEP_RECENT` (默认 3 条)

#### 核心实现
```python
# 异步生成摘要
compact_content = await memory_manager.compact_memory(
    messages=messages_to_compact,
    previous_summary=memory.get_compressed_summary(),
)

# 更新摘要并标记已压缩消息
await agent.memory.update_compressed_summary(compact_content)
await memory.update_messages_mark(
    new_mark=_MemoryMark.COMPRESSED,
    msg_ids=[msg.id for msg in messages_to_compact],
)
```

#### 优点
1. **三区结构清晰**: 系统提示 + 压缩摘要 + 可压缩区 + 保留区
2. **工具调用完整性保护**: `check_valid_messages()` 确保 tool_use/tool_result 成对
3. **增量摘要**: 支持将新对话与已有摘要合并
4. **异步摘要**: 后台生成详细摘要不阻塞主流程

#### 缺点
1. **依赖外部库**: ReMe 库增加了依赖复杂度
2. **配置分散**: Token 阈值在多处配置
3. **压缩模型单一**: 使用固定模型进行压缩

---

### 2. kimi-cli（Python）

#### 存储架构
- **文件格式**: JSON Lines (`context.jsonl`)
- **存储位置**: `~/.local/share/kimi/sessions/{session_id}/`
- **特殊文件**: `wire.jsonl` (协议消息), `state.json` (会话状态)

#### 数据结构
```python
class Context:
    def __init__(self, file_backend: Path):
        self._history: list[Message] = []        # 内存消息
        self._token_count: int = 0                # 当前token
        self._next_checkpoint_id: int = 0         # checkpoint ID
        self._system_prompt: str | None = None
```

#### Token 计算
- **估算**: 字符数 // 4
- **实际**: 从 LLM API 响应获取

```python
def estimate_text_tokens(messages: Sequence[Message]) -> int:
    total_chars = 0
    for msg in messages:
        for part in msg.content:
            if isinstance(part, TextPart):
                total_chars += len(part.text)
    return total_chars // 4
```

#### 压缩策略（SimpleCompaction）
- **触发条件**: 双条件触发
  - 比例触发: `token_count >= max_context_size * 0.85`
  - 保留空间: `token_count + reserved_context_size >= max_context_size`
- **保留消息**: 最近 2 条用户/助手消息
- **压缩提示**: 结构化提示模板 (`src/kimi_cli/prompts/compact.md`)

```python
class SimpleCompaction:
    def __init__(self, max_preserved_messages: int = 2):
        self.max_preserved_messages = max_preserved_messages

    async def compact(self, messages, llm):
        # 保留最近2条，压缩更早历史
        to_compact = history[:preserve_start_index]
        to_preserve = history[preserve_start_index:]
        # 调用LLM生成摘要
        # 构建 [摘要] + [保留消息]
```

#### Checkpoint 与 D-Mail 机制
- **Checkpoint**: 每个 step 开始时创建，支持回退
- **D-Mail**: 允许 AI 主动回溯到历史 checkpoint

```python
class DMail(BaseModel):
    message: str           # 发送给过去自己的消息
    checkpoint_id: int     # 目标checkpoint

# 工具调用此方法发送D-Mail
def send_dmail(self, dmail: DMail):
    self._pending_dmail = dmail
```

#### 优点
1. **Checkpoint 系统**: 支持任意点回退，D-Mail 机制独特
2. **双条件触发**: 比例 + 保留空间双重保险
3. **结构化压缩**: 明确的压缩优先级和输出格式
4. **估算 + 实际**: 启发式估算配合 API 实际计数

#### 缺点
1. **保留消息少**: 仅保留 2 条，上下文可能丢失
2. **文件 IO 频繁**: JSONL 逐行读写
3. **压缩粒度粗**: 只区分"压缩"和"保留"两类

---

### 3. openclaw（TypeScript）

#### 存储架构
- **文件格式**: JSONL (`<sessionId>.jsonl`)
- **存储位置**: `~/.openclaw/sessions/`

#### Token 估算
```typescript
const CHARS_PER_TOKEN_ESTIMATE = 4;                    // 通用文本
const TOOL_RESULT_CHARS_PER_TOKEN_ESTIMATE = 2;       // 工具结果
const IMAGE_CHAR_ESTIMATE = 8_000;                    // 图片
```

#### 六层防护体系
```
Layer 1: Session Persistence (JSONL)
Layer 2: History Limiting (Turn-based)
Layer 3: Context Pruning (TTL-aware soft/hard trim)
Layer 4: Tool Result Guarding (Per-request budget)
Layer 5: Compaction (Summarization)
Layer 6: Post-compaction Re-injection
```

#### 上下文剪枝（Context Pruning）

**配置**:
```typescript
const DEFAULT_CONTEXT_PRUNING_SETTINGS = {
  mode: "cache-ttl",
  ttlMs: 5 * 60 * 1000,           // 5分钟 TTL
  keepLastAssistants: 3,          // 保护最近3条助手消息
  softTrimRatio: 0.3,             // 30% 软剪裁阈值
  hardClearRatio: 0.5,            // 50% 硬清除阈值
  minPrunableToolChars: 50_000,
  softTrim: {
    maxChars: 4_000,
    headChars: 1_500,
    tailChars: 1_500,
  },
  hardClear: {
    enabled: true,
    placeholder: "[Old tool result content cleared]",
  },
};
```

**两阶段剪枝**:
1. **Soft Trim**: 保留头部和尾部，中间替换为 `[...]`
2. **Hard Clear**: 整个工具结果替换为占位符

#### 轮数限制
```typescript
function limitHistoryTurns(messages: AgentMessage[], limit: number): AgentMessage[] {
  // 从后向前遍历，保留最近 limit 轮用户消息
  for (let i = messages.length - 1; i >= 0; i--) {
    if (messages[i].role === "user") {
      userCount++;
      if (userCount > limit) {
        return messages.slice(lastUserIndex);  // 滑动窗口
      }
    }
  }
}
```

#### 工具结果守卫
```typescript
const CONTEXT_INPUT_HEADROOM_RATIO = 0.75;      // 75% 安全余量
const SINGLE_TOOL_RESULT_CONTEXT_SHARE = 0.5;   // 单个工具结果最多50%

function enforceToolResultContextBudgetInPlace(params: {
  messages: AgentMessage[];
  contextBudgetChars: number;
  maxSingleToolResultChars: number;
}): void
```

#### 压缩后上下文重新注入
```typescript
const DEFAULT_POST_COMPACTION_SECTIONS = ["Session Startup", "Red Lines"];

// 压缩后重新注入 AGENTS.md 的关键章节
function extractSections(content: string, sectionNames: string[]): string[]
```

#### 优点
1. **六层防护**: 最全面的上下文管理机制
2. **两阶段剪枝**: Soft Trim + Hard Clear 精细控制
3. **缓存感知**: TTL-based 优化 Anthropic prompt caching
4. **可配置压缩模型**: 支持指定轻量级模型进行压缩
5. **章节注入**: 压缩后重新注入关键上下文

#### 缺点
1. **复杂度高**: 六层机制学习成本大
2. **TypeScript 特定**: 移植到其他语言需要大量工作
3. **估算保守**: 2 chars/token 对工具结果过于保守

---

### 4. opencode（TypeScript）

#### 存储架构
- **数据库**: SQLite
- **表结构**:
  - `SessionTable`: 会话基本信息
  - `MessageTable`: 消息
  - `PartTable`: 消息片段

#### Token 计算
```typescript
const CHARS_PER_TOKEN = 4;

export function estimate(input: string) {
  return Math.max(0, Math.round((input || "").length / CHARS_PER_TOKEN));
}
```

#### 模型限制
```typescript
limit: {
  context: number   // 总上下文长度限制
  input?: number    // 输入长度限制
  output: number    // 输出长度限制
}
```

#### 自动压缩触发
```typescript
const COMPACTION_BUFFER = 20_000;  // 20K token缓冲区

export async function isOverflow(input) {
  const count = input.tokens.total ||
    input.tokens.input + input.tokens.output +
    input.tokens.cache.read + input.tokens.cache.write;

  const reserved = config.compaction?.reserved ??
    Math.min(COMPACTION_BUFFER, maxOutputTokens(input.model));

  const usable = input.model.limit.input
    ? input.model.limit.input - reserved
    : context - maxOutputTokens(input.model);

  return count >= usable;
}
```

#### 压缩策略

**摘要提示模板**:
```typescript
const defaultPrompt = `Provide a detailed prompt for continuing our conversation above.
Focus on information that would be helpful for continuing the conversation.

Template:
---
## Goal
[What goal(s) is the user trying to accomplish?]

## Instructions
- [What important instructions did the user give you]

## Discoveries
[What notable things were learned]

## Accomplished
[What work has been completed]

## Relevant files / directories
[Construct a structured list of relevant files]
---`;
```

#### 工具输出剪裁（Pruning）
```typescript
const PRUNE_MINIMUM = 20_000;    // 最小剪裁阈值
const PRUNE_PROTECT = 40_000;    // 保护最近40K token
const PRUNE_PROTECTED_TOOLS = ["skill"];  // 保护skill工具

// 从后往前遍历，清除超过保护阈值的工具输出
export async function prune(input: { sessionID: SessionID }) {
  for (let msgIndex = msgs.length - 1; msgIndex >= 0; msgIndex--) {
    if (turns < 2) continue;  // 保护最近2轮
    if (msg.info.role === "assistant" && msg.info.summary) break;

    // 标记已压缩，输出替换为 "[Old tool result content cleared]"
    part.state.time.compacted = Date.now();
  }
}
```

#### 消息流过滤
```typescript
export async function filterCompacted(stream: AsyncIterable<MessageV2.WithParts>) {
  for await (const msg of stream) {
    result.push(msg);
    // 遇到压缩标记的用户消息后停止
    if (msg.info.role === "user" &&
        completed.has(msg.info.id) &&
        msg.parts.some((part) => part.type === "compaction"))
      break;
    // 记录已完成摘要的父消息
    if (msg.info.role === "assistant" && msg.info.summary)
      completed.add(msg.info.parentID);
  }
}
```

#### 优点
1. **数据库存储**: SQLite 支持复杂查询和事务
2. **结构化摘要**: 模板化摘要格式清晰
3. **工具保护**: 特定工具（如 skill）不被剪裁
4. **媒体感知**: 自动剥离大附件，保留文本引用

#### 缺点
1. **数据库依赖**: SQLite 增加了部署复杂度
2. **估算简单**: 仅字符 // 4，无实际 Token 计数
3. **保留策略单一**: 仅保护最近 2 轮 + skill 工具

---

## 二、综合对比表

| 维度 | CoPaw | kimi-cli | openclaw | opencode |
|------|-------|----------|----------|----------|
| **存储** | InMemory + 文件 | JSONL | JSONL | SQLite |
| **Token计算** | HF Tokenizer + 回退 | 估算+实际 | 估算(分层) | 简单估算 |
| **触发方式** | 阈值比例 | 双条件(比例+保留) | 多层触发 | 溢出检测 |
| **保留策略** | 最近 N 条 + 摘要 | 最近 2 条 | 最近 N 轮 + 助手 | 最近 2 轮 + skill |
| **压缩粒度** | 消息级别 | 消息级别 | 工具结果级别 | 工具结果级别 |
| **特殊机制** | 工具完整性检查 | Checkpoint + D-Mail | 六层防护 + 章节注入 | 数据库存储 |
| **配置复杂度** | 中等 | 简单 | 高 | 中等 |
| **语言** | Python | Python | TypeScript | TypeScript |

---

## 三、优劣分析

### CoPaw
- **优势**: 三区模型清晰，工具完整性保护完善
- **劣势**: 依赖 ReMe 库，配置分散
- **适用**: 需要严格工具调用完整性的场景

### kimi-cli
- **优势**: Checkpoint 系统独特，双条件触发可靠
- **劣势**: 保留消息过少，文件 IO 频繁
- **适用**: 需要频繁回退和分支的场景

### openclaw
- **优势**: 六层防护最全面，两阶段剪枝精细
- **劣势**: 复杂度高，学习成本大
- **适用**: 生产环境，需要精细控制的场景

### opencode
- **优势**: 数据库存储支持复杂查询，结构化摘要
- **劣势**: 数据库依赖，估算简单
- **适用**: 需要持久化和复杂会话管理的场景

---

## 四、推荐解决方案

基于以上分析，推荐采用**混合策略**，融合各项目优点：

### 核心架构（推荐）

```
┌─────────────────────────────────────────────────────────────┐
│                    Context Management Architecture          │
├─────────────────────────────────────────────────────────────┤
│ Layer 1: Storage (JSONL + Memory Cache)                     │
│          - 持久化到 JSONL，运行时缓存于内存                   │
│          - 支持 Checkpoint 标记                              │
├─────────────────────────────────────────────────────────────┤
│ Layer 2: Token Calculation (Hybrid)                         │
│          - 使用 tiktoken/jtokkit 精确计算                   │
│          - 失败时回退到 chars//4                            │
├─────────────────────────────────────────────────────────────┤
│ Layer 3: Trigger Detection (Dual Condition)                 │
│          - 比例触发: usage >= threshold (e.g., 80%)         │
│          - 空间触发: usage + reserved >= max                │
├─────────────────────────────────────────────────────────────┤
│ Layer 4: Protection Zone                                    │
│          - System Prompt (固定)                             │
│          - 最近 N 轮对话 (可配置，默认 4 轮)                 │
│          - 未完成的工具调用链                               │
├─────────────────────────────────────────────────────────────┤
│ Layer 5: Pruning (Two-Stage)                                │
│          - Soft Trim: 大工具结果保留头尾                    │
│          - Hard Clear: 旧工具结果替换占位符                 │
├─────────────────────────────────────────────────────────────┤
│ Layer 6: Compaction (Smart Summarization)                   │
│          - 使用轻量级模型生成结构化摘要                     │
│          - 支持增量更新                                     │
│          - 压缩后注入关键上下文                             │
└─────────────────────────────────────────────────────────────┘
```

### 关键实现代码（Python 示例）

```python
"""
推荐的多轮对话上下文管理实现
融合 CoPaw + kimi-cli + openclaw + opencode 优点
"""

import json
from dataclasses import dataclass, field
from typing import List, Optional, Dict, Any
from pathlib import Path
import tiktoken


@dataclass
class Message:
    id: str
    role: str  # "system", "user", "assistant", "tool"
    content: Any
    metadata: Dict = field(default_factory=dict)
    tokens: int = 0


class TokenCounter:
    """Token 计数器 - 精确计算 + 回退"""

    def __init__(self, model: str = "gpt-4"):
        self.model = model
        try:
            self.encoder = tiktoken.encoding_for_model(model)
        except:
            self.encoder = None

    def count(self, text: str) -> int:
        if self.encoder:
            return len(self.encoder.encode(text))
        return len(text) // 4  # 回退

    def count_messages(self, messages: List[Message]) -> int:
        total = 0
        for msg in messages:
            if msg.tokens > 0:
                total += msg.tokens
            else:
                text = json.dumps(msg.content) if isinstance(msg.content, dict) else str(msg.content)
                msg.tokens = self.count(text)
                total += msg.tokens
        return total


class ContextManager:
    """
    上下文管理器

    融合策略:
    - CoPaw: 三区模型 + 工具完整性保护
    - kimi-cli: 双条件触发 + Checkpoint
    - openclaw: 两阶段剪枝 + 六层防护
    - opencode: 结构化摘要 + 特殊工具保护
    """

    # 默认配置
    DEFAULT_CONFIG = {
        "max_context_tokens": 128_000,
        "trigger_threshold": 0.80,      # 80% 触发
        "reserved_tokens": 20_000,      # 保留空间
        "keep_recent_turns": 4,         # 保留最近轮数
        "keep_recent_assistants": 3,    # 保留最近助手消息
        "soft_trim_max_chars": 4_000,
        "soft_trim_head_chars": 1_500,
        "soft_trim_tail_chars": 1_500,
        "hard_clear_placeholder": "[Old content cleared]",
        "protected_tools": ["skill", "read_file"],
        "compaction_model": "gpt-3.5-turbo",  # 轻量级模型
    }

    def __init__(self, session_id: str, config: Optional[Dict] = None):
        self.session_id = session_id
        self.config = {**self.DEFAULT_CONFIG, **(config or {})}
        self.token_counter = TokenCounter()

        # 三区结构
        self.system_prompt: Optional[str] = None
        self.compressed_summary: str = ""
        self.compressed_messages: List[Message] = []  # 已压缩历史
        self.active_messages: List[Message] = []       # 活跃对话

        # Checkpoint
        self.checkpoints: List[int] = []

        # 文件存储
        self.session_file = Path(f"~/.kimi-agent/sessions/{session_id}.jsonl").expanduser()
        self.session_file.parent.mkdir(parents=True, exist_ok=True)

    # ==================== Layer 1: Storage ====================

    def load(self) -> None:
        """从 JSONL 加载会话"""
        if not self.session_file.exists():
            return

        with open(self.session_file, 'r', encoding='utf-8') as f:
            for line in f:
                if not line.strip():
                    continue
                data = json.loads(line)
                if data.get("role") == "_system":
                    self.system_prompt = data["content"]
                elif data.get("role") == "_summary":
                    self.compressed_summary = data["content"]
                elif data.get("role") == "_checkpoint":
                    self.checkpoints.append(data["id"])
                else:
                    self.active_messages.append(Message(**data))

    def save(self) -> None:
        """保存到 JSONL"""
        with open(self.session_file, 'w', encoding='utf-8') as f:
            if self.system_prompt:
                f.write(json.dumps({"role": "_system", "content": self.system_prompt}) + '\n')
            if self.compressed_summary:
                f.write(json.dumps({"role": "_summary", "content": self.compressed_summary}) + '\n')
            for msg in self.active_messages:
                f.write(json.dumps({
                    "id": msg.id,
                    "role": msg.role,
                    "content": msg.content,
                    "metadata": msg.metadata,
                    "tokens": msg.tokens,
                }) + '\n')

    def create_checkpoint(self) -> int:
        """创建 Checkpoint"""
        checkpoint_id = len(self.checkpoints)
        self.checkpoints.append(checkpoint_id)
        self.save()
        return checkpoint_id

    def revert_to(self, checkpoint_id: int) -> None:
        """回退到指定 Checkpoint"""
        if checkpoint_id >= len(self.checkpoints):
            raise ValueError(f"Checkpoint {checkpoint_id} does not exist")
        # 截断到 checkpoint 位置
        # ...

    # ==================== Layer 2: Token Calculation ====================

    def get_token_count(self) -> int:
        """计算总 Token 数"""
        total = 0
        if self.system_prompt:
            total += self.token_counter.count(self.system_prompt)
        if self.compressed_summary:
            total += self.token_counter.count(self.compressed_summary)
        total += self.token_counter.count_messages(self.active_messages)
        return total

    # ==================== Layer 3: Trigger Detection ====================

    def should_compact(self) -> bool:
        """双条件触发检测"""
        token_count = self.get_token_count()
        max_tokens = self.config["max_context_tokens"]
        threshold = self.config["trigger_threshold"]
        reserved = self.config["reserved_tokens"]

        # 条件1: 比例触发
        if token_count >= max_tokens * threshold:
            return True

        # 条件2: 保留空间触发
        if token_count + reserved >= max_tokens:
            return True

        return False

    # ==================== Layer 4: Protection Zone ====================

    def _get_protected_messages(self) -> List[Message]:
        """获取受保护的消息（不可压缩）"""
        protected = []

        # 1. 保留最近 N 轮
        user_count = 0
        for msg in reversed(self.active_messages):
            protected.append(msg)
            if msg.role == "user":
                user_count += 1
                if user_count >= self.config["keep_recent_turns"]:
                    break

        protected.reverse()

        # 2. 检查工具调用完整性
        protected = self._ensure_tool_integrity(protected)

        return protected

    def _ensure_tool_integrity(self, messages: List[Message]) -> List[Message]:
        """确保 tool_use/tool_result 成对出现"""
        use_ids = set()
        result_ids = set()

        for msg in messages:
            if msg.role == "assistant" and "tool_calls" in msg.metadata:
                for call in msg.metadata["tool_calls"]:
                    use_ids.add(call["id"])
            elif msg.role == "tool":
                result_ids.add(msg.metadata.get("tool_call_id"))

        # 如有不完整的工具链，扩展保护范围
        # ...

        return messages

    # ==================== Layer 5: Pruning (Two-Stage) ====================

    def prune_context(self) -> None:
        """两阶段剪枝"""
        # 阶段1: Soft Trim - 大工具结果保留头尾
        for msg in self.active_messages:
            if msg.role == "tool" and self._should_soft_trim(msg):
                msg.content = self._soft_trim_content(msg.content)

        # 阶段2: Hard Clear - 旧工具结果替换占位符
        # 保护最近 N 轮的 tool 消息
        protected_tool_ids = self._get_protected_tool_ids()

        for msg in self.active_messages:
            if msg.role == "tool" and msg.id not in protected_tool_ids:
                if self._should_hard_clear(msg):
                    msg.content = self.config["hard_clear_placeholder"]
                    msg.metadata["cleared"] = True

    def _should_soft_trim(self, msg: Message) -> bool:
        """判断是否需要软剪裁"""
        content_len = len(str(msg.content))
        return content_len > self.config["soft_trim_max_chars"]

    def _soft_trim_content(self, content: Any) -> str:
        """软剪裁: 保留头尾"""
        text = str(content)
        head = text[:self.config["soft_trim_head_chars"]]
        tail = text[-self.config["soft_trim_tail_chars"]:]
        return f"{head}\n... ({len(text) - self.config['soft_trim_head_chars'] - self.config['soft_trim_tail_chars']} chars omitted) ...\n{tail}"

    def _get_protected_tool_ids(self) -> set:
        """获取受保护的工具消息 ID"""
        protected = set()
        recent_tools = 0

        for msg in reversed(self.active_messages):
            if msg.role == "tool":
                # 保护特定工具
                tool_name = msg.metadata.get("tool_name", "")
                if tool_name in self.config["protected_tools"]:
                    protected.add(msg.id)
                    continue

                # 保护最近 N 个
                recent_tools += 1
                if recent_tools <= self.config["keep_recent_assistants"]:
                    protected.add(msg.id)

        return protected

    def _should_hard_clear(self, msg: Message) -> bool:
        """判断是否需要硬清除"""
        # 已清除的跳过
        if msg.metadata.get("cleared"):
            return False

        # 保护特定工具
        tool_name = msg.metadata.get("tool_name", "")
        if tool_name in self.config["protected_tools"]:
            return False

        return True

    # ==================== Layer 6: Compaction ====================

    async def compact(self, custom_instruction: str = "") -> str:
        """智能压缩 - 生成结构化摘要"""
        protected = self._get_protected_messages()
        to_compact = [m for m in self.active_messages if m not in protected]

        if not to_compact:
            return ""

        # 构建压缩提示
        prompt = self._build_compaction_prompt(to_compact, custom_instruction)

        # 调用轻量级模型生成摘要
        summary = await self._call_compaction_model(prompt)

        # 更新三区结构
        self.compressed_summary = self._merge_summaries(
            self.compressed_summary, summary
        )
        self.compressed_messages.extend(to_compact)
        self.active_messages = protected

        # 重新注入关键上下文
        await self._reinject_critical_context()

        self.save()
        return summary

    def _build_compaction_prompt(self, messages: List[Message], instruction: str) -> str:
        """构建结构化压缩提示"""
        history = self._format_messages(messages)

        prompt = f"""Provide a detailed summary of the conversation below.
Focus on information that would be helpful for continuing the conversation.

{instruction}

Use this template:
---
## Goal
[What goal(s) is the user trying to accomplish?]

## Instructions
- [What important instructions did the user give you]

## Discoveries
[What notable things were learned during this conversation]

## Accomplished
[What work has been completed, what work is still in progress]

## Relevant files / directories
[Construct a structured list of relevant files]

## Next Steps
[What should be done next]
---

Conversation history:
{history}
"""
        return prompt

    def _merge_summaries(self, old: str, new: str) -> str:
        """合并新旧摘要"""
        if not old:
            return new
        return f"{old}\n\n## New Summary\n{new}"

    async def _reinject_critical_context(self) -> None:
        """压缩后重新注入关键上下文"""
        # 读取 AGENTS.md 的关键章节
        # 提取 "Session Startup", "Red Lines" 等
        # 追加到 compressed_summary
        pass

    async def _call_compaction_model(self, prompt: str) -> str:
        """调用轻量级模型生成摘要"""
        # 实现调用逻辑
        pass

    # ==================== Public API ====================

    def add_message(self, role: str, content: Any, **metadata) -> Message:
        """添加消息"""
        import uuid
        msg = Message(
            id=str(uuid.uuid4()),
            role=role,
            content=content,
            metadata=metadata,
        )
        self.active_messages.append(msg)

        # 自动检测是否需要压缩
        if self.should_compact():
            # 触发压缩（异步）
            pass

        return msg

    def get_context_for_llm(self) -> List[Dict]:
        """获取用于 LLM 的上下文"""
        context = []

        # System Prompt
        if self.system_prompt:
            context.append({"role": "system", "content": self.system_prompt})

        # 压缩摘要
        if self.compressed_summary:
            context.append({
                "role": "system",
                "content": f"Previous conversation summary:\n{self.compressed_summary}"
            })

        # 活跃消息
        for msg in self.active_messages:
            context.append({
                "role": msg.role,
                "content": msg.content,
            })

        return context


# ==================== 使用示例 ====================

async def main():
    # 创建上下文管理器
    ctx = ContextManager(session_id="session-001")
    ctx.load()

    # 设置系统提示
    ctx.system_prompt = "You are a helpful coding assistant."

    # 添加消息
    ctx.add_message("user", "帮我写一个登录功能")
    ctx.add_message("assistant", "好的，我来帮你实现...")

    # 手动触发压缩
    if ctx.should_compact():
        summary = await ctx.compact()
        print(f"Compressed summary: {summary}")

    # 获取上下文用于 LLM
    context = ctx.get_context_for_llm()

    # 创建 checkpoint
    checkpoint_id = ctx.create_checkpoint()

    # 回退
    # ctx.revert_to(checkpoint_id)


if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
```

### 配置建议

```json
{
  "context_management": {
    "max_context_tokens": 128000,
    "trigger_threshold": 0.80,
    "reserved_tokens": 20000,
    "keep_recent_turns": 4,
    "keep_recent_assistants": 3,
    "soft_trim": {
      "max_chars": 4000,
      "head_chars": 1500,
      "tail_chars": 1500
    },
    "hard_clear": {
      "enabled": true,
      "placeholder": "[Old content cleared]"
    },
    "protected_tools": ["skill", "read_file", "write_file"],
    "compaction": {
      "model": "gpt-3.5-turbo",
      "post_compaction_sections": ["Session Startup", "Red Lines"]
    }
  }
}
```

---

## 五、总结

1. **存储层**: JSONL + 内存缓存，支持 Checkpoint（借鉴 kimi-cli）
2. **Token 计算**: tiktoken 精确计算 + chars//4 回退（借鉴 CoPaw）
3. **触发机制**: 双条件触发（比例 + 保留空间）（借鉴 kimi-cli）
4. **保护策略**: 三区模型 + 工具完整性检查（借鉴 CoPaw + opencode）
5. **剪枝策略**: 两阶段剪枝 Soft Trim + Hard Clear（借鉴 openclaw）
6. **压缩策略**: 轻量级模型生成结构化摘要，支持增量更新（借鉴 CoPaw + opencode）
7. **后处理**: 压缩后重新注入关键上下文（借鉴 openclaw）

此方案融合了四个项目的最佳实践，兼顾简洁性、可靠性和可配置性，适用于生产环境的 AI Agent 系统。
