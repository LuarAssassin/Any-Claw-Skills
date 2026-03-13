# Memory 写入策略与 Session-State 边界分析

## 目录
1. [核心概念](#核心概念)
2. [CoPaw](#copaw)
3. [kimi-cli](#kimi-cli)
4. [openclaw](#openclaw)
5. [opencode](#opencode)
6. [对比总结与建议](#对比总结与建议)

---

## 核心概念

### Memory 写入策略维度

| 维度 | 选项 | 说明 |
|------|------|------|
| **写入时机** | 实时写入 / 延迟写入 / 批量写入 / 条件触发 | 何时将数据持久化 |
| **写入内容** | 消息 / 摘要 / 向量 / 元数据 / 状态 | 什么数据被持久化 |
| **存储介质** | SQLite / JSONL / 文件系统 / 向量数据库 | 数据存储在哪里 |
| **同步机制** | 同步阻塞 / 异步非阻塞 / 事件驱动 | 如何协调写入 |

### Session-State 边界核心问题

1. **边界划分**: Session 运行时状态 vs 跨会话持久化记忆
2. **一致性保证**: 如何保证内存状态与持久化存储一致
3. **恢复机制**: Session 重启后如何重建状态
4. **并发安全**: 多线程/进程访问时的数据完整性

---

## CoPaw

### Memory 写入策略

```python
# src/copaw/agents/hooks/memory_compaction.py:76-90
config = load_config()
memory_compact_threshold = config.agents.running.memory_compact_threshold
left_compact_threshold = memory_compact_threshold - str_token_count

if left_compact_threshold <= 0:
    logger.warning("The memory_compact_threshold is set too low...")
    return None

# 触发异步摘要任务
self.memory_manager.add_async_summary_task(messages=messages_to_compact)
compact_content = await self.memory_manager.compact_memory(...)
await agent.memory.update_compressed_summary(compact_content)
```

| 维度 | 实现 |
|------|------|
| **写入时机** | 条件触发（Token 阈值达到 `memory_compact_threshold` 时触发 compaction） |
| **写入内容** | 消息摘要（summarization）、向量嵌入、元数据 |
| **存储介质** | SQLite（ReMeLight）、Chroma（向量存储）/ Local（文件存储 Windows） |
| **写入频率** | 低频率，仅在阈值触发时写入 |

### Session-State 边界架构

```
┌─────────────────────────────────────────────────────────┐
│                    Session 运行时                        │
│  ┌─────────────────┐      ┌──────────────────────┐     │
│  │  InMemoryMemory │─────▶│  MemoryCompactionHook │     │
│  │  (完整消息历史)  │      │  (Token 阈值检查)      │     │
│  └─────────────────┘      └──────────────────────┘     │
│           │                            │                │
│           │ 超过阈值时                  │ 触发 compaction │
│           ▼                            ▼                │
│  ┌─────────────────┐      ┌──────────────────────┐     │
│  │  reserved_msgs  │◀─────│   MemoryManager      │     │
│  │  (保留区消息)    │      │   (ReMeLight 接口)    │     │
│  └─────────────────┘      └──────────────────────┘     │
│                                    │                    │
└────────────────────────────────────┼────────────────────┘
                                     │ 持久化写入
                                     ▼
┌─────────────────────────────────────────────────────────┐
│                    持久化存储层                          │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐ │
│  │   SQLite    │    │   Chroma    │    │   Local     │ │
│  │  (摘要文本)  │    │  (向量嵌入)  │    │ (Windows存储)│ │
│  └─────────────┘    └─────────────┘    └─────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### 关键代码：Memory Manager 写入

```python
# src/copaw/memory/memory_manager.py
class MemoryManager:
    def __init__(self):
        self.storage = ReMeLightStorage()  # 底层存储抽象

    async def compact_memory(self, messages: List[Message]) -> str:
        """压缩消息并持久化"""
        summary = await self.summarizer.summarize(messages)
        # 同时更新向量索引
        await self.storage.store_embedding(
            content=summary,
            metadata={"type": "compaction", "msg_count": len(messages)}
        )
        return summary
```

### 恢复机制

```python
# Session 启动时
async def load_session(self):
    # 从 ReMeLight 恢复压缩摘要
    compressed_summary = await self.memory_manager.get_compressed_summary()
    # 重建 InMemoryMemory，但完整历史已丢失，只剩摘要
    self.memory.set_compressed_summary(compressed_summary)
```

### 优劣分析

| 优势 | 劣势 |
|------|------|
| Token 阈值触发减少不必要的写入 | Session-State 边界模糊 |
| 向量搜索集成良好 | 完整历史在 compaction 后丢失 |
| 异步写入不阻塞推理 | `InMemoryMemory` 与 `ReMeLight` 同步复杂 |

---

## kimi-cli

### Memory 写入策略

```python
# src/kimi_cli/wire/file.py:117-131
async def append_message(self, msg: WireMessage, *, timestamp: float | None = None) -> None:
    record = WireMessageRecord.from_wire_message(
        msg,
        timestamp=time.time() if timestamp is None else timestamp,
    )
    await self.append_record(record)

async def append_record(self, record: WireMessageRecord) -> None:
    self.path.parent.mkdir(parents=True, exist_ok=True)
    needs_header = not self.path.exists() or self.path.stat().st_size == 0
    async with aiofiles.open(self.path, mode="a", encoding="utf-8") as f:
        if needs_header:
            metadata = WireFileMetadata(protocol_version=self.protocol_version)
            await f.write(_dump_line(metadata))
        await f.write(_dump_line(record))  # 实时追加写入
```

| 维度 | 实现 |
|------|------|
| **写入时机** | 实时追加写入（append-only） |
| **写入内容** | 消息历史（context.jsonl）、Wire 事件（wire.jsonl）、状态（state.json） |
| **存储介质** | JSONL 文件（消息）、JSON 文件（状态） |
| **写入频率** | 每条消息后实时写入 |

### Session-State 边界架构

```
~/.kimi/sessions/{workdir_md5}/
└── {session_id}/
    ├── context.jsonl      # 对话消息历史（append-only）
    ├── wire.jsonl         # 详细事件日志（调试/可视化）
    └── state.json         # Session 状态（配置、动态agents等）
```

```python
# src/kimi_cli/session.py:126-144
session_dir = work_dir_meta.sessions_dir / session_id
session_dir.mkdir(parents=True, exist_ok=True)

context_file = session_dir / "context.jsonl"
context_file.touch()

session = Session(
    id=session_id,
    work_dir=work_dir,
    context_file=context_file,           # 消息历史句柄
    wire_file=WireFile(path=session_dir / "wire.jsonl"),  # 事件日志
    state=SessionState(),                # 运行时状态
    ...
)
```

### 三种数据分离

| 文件 | 内容 | 格式 | 用途 |
|------|------|------|------|
| `context.jsonl` | 对话消息 | JSON Lines | LLM 上下文构建 |
| `wire.jsonl` | 运行时事件 | JSON Lines + 协议头 | 调试、可视化、D-Mail |
| `state.json` | Session 配置 | JSON | 持久化状态恢复 |

### D-Mail 与 Session-State 关系

```python
# D-Mail 通过 Wire 日志实现时间旅行
class DenwaRenji:
    def send_dmail(self, dmail: DMail):
        # D-Mail 本身作为 Wire 事件写入
        self.wire_file.append_message(dmail.to_wire_message())
        self._pending_dmail = dmail  # Session 状态标记

    def fetch_pending_dmail(self) -> DMail | None:
        return self._pending_dmail  # 从 Session 状态读取
```

### 恢复机制

```python
# 从 context.jsonl 恢复
async def resume_session(session_id: str) -> Session:
    context_file = get_context_path(session_id)
    messages = []
    async with aiofiles.open(context_file, 'r') as f:
        async for line in f:
            if line.strip():
                record = json.loads(line)
                messages.append(Message.from_record(record))

    # 从 state.json 恢复配置
    state = SessionState.load(get_state_path(session_id))

    return Session(messages=messages, state=state)
```

### 优劣分析

| 优势 | 劣势 |
|------|------|
| 简单直接，易于外部工具解析 | 文件 IO 频繁 |
| 三种数据分离清晰 | 无内置向量搜索 |
| Wire 日志提供完整事件溯源 | 大 session 文件性能下降 |
| JSONL 支持流式读取 | 无压缩，存储空间大 |

---

## openclaw

### Memory 写入策略

```typescript
// src/memory/manager.ts:241-255
async warmSession(sessionKey?: string): Promise<void> {
  if (!this.settings.sync.onSessionStart) {
    return;
  }
  // Session 开始时触发同步
  void this.sync({ reason: "session-start" }).catch((err) => {
    log.warn(`memory sync failed (session-start): ${String(err)}`);
  });
  if (key) {
    this.sessionWarm.add(key);
  }
}

// src/memory/manager.ts:452-467
async sync(params?: { reason?: string; force?: boolean }): Promise<void> {
  if (this.closed || this.syncing) {
    return this.syncing ?? Promise.resolve();
  }
  this.syncing = this.runSyncWithReadonlyRecovery(params).finally(() => {
    this.syncing = null;
  });
  return this.syncing;
}
```

| 维度 | 实现 |
|------|------|
| **写入时机** | 实时 + 延迟批量（debounced）、Session 开始/结束、文件 watcher 触发 |
| **写入内容** | 向量嵌入、FTS 索引、文件 chunks、session 文件增量 |
| **存储介质** | SQLite + sqlite-vec（向量扩展）、文件系统 |
| **写入频率** | 多触发点：文件变更、定时器、session 生命周期 |

### Session-State 边界架构

```
┌────────────────────────────────────────────────────────────┐
│                     Session 运行时                          │
│  ┌─────────────────┐      ┌────────────────────────────┐  │
│  │   SessionState  │─────▶│   MemoryIndexManager       │  │
│  │   (临时索引缓存)  │      │   (SQLite + sqlite-vec)     │  │
│  └─────────────────┘      └────────────────────────────┘  │
│           │                           │                   │
│           │ 查询命中缓存               │ 批量同步            │
│           ▼                           ▼                   │
│  ┌─────────────────┐      ┌────────────────────────────┐  │
│  │   sessionDeltas │◀─────│   File Watcher (chokidar)  │  │
│  │   (增量跟踪)     │      │   文件变更触发              │  │
│  └─────────────────┘      └────────────────────────────┘  │
└────────────────────────────────────────────────────────────┘
                    │
                    │ 持久化写入
                    ▼
┌────────────────────────────────────────────────────────────┐
│                      持久化存储层                           │
│  ┌─────────────────┐      ┌────────────────────────────┐  │
│  │  SQLite Index   │      │   Session JSONL Files      │  │
│  │  (chunks + vec) │      │   (独立会话日志)            │  │
│  └─────────────────┘      └────────────────────────────┘  │
└────────────────────────────────────────────────────────────┘
```

### 多触发点同步机制

```typescript
// src/memory/manager.ts - 同步触发点汇总
class MemoryManager {
  private syncTimer?: NodeJS.Timeout;

  constructor() {
    // 1. 文件 Watcher 触发
    this.watcher = chokidar.watch(dirs).on('change', () => {
      this.sync({ reason: "file-change" });
    });

    // 2. 定时器触发
    this.ensureIntervalSync();
  }

  // 3. Session 生命周期触发
  async warmSession(sessionKey: string) {
    await this.sync({ reason: "session-start" });
  }

  // 4. 手动/强制触发
  async forceSync() {
    await this.sync({ reason: "manual", force: true });
  }
}
```

### Session 文件独立存储

```typescript
// src/core/session-files.ts
interface SessionFile {
  path: string;
  deltas: SessionFileDelta[];  // 文件增量
  lastSync: number;
}

// Session 文件与 Memory Index 分离
class SessionFileManager {
  private pendingFiles: Map<string, SessionFile>;

  async flush(): Promise<void> {
    // 写入 JSONL
    await this.writeSessionLog();
    // 更新 Memory Index
    await memoryManager.sync({ reason: "session-flush" });
  }
}
```

### 恢复机制

```typescript
// 从 SQLite 恢复索引
async function restoreIndex(agentId: string): Promise<void> {
  const dbPath = path.join(OPENCLOUD_DIR, "memory", agentId, "index.sqlite");
  const db = new Database(dbPath);

  // 恢复向量索引
  db.exec(`
    CREATE VIRTUAL TABLE IF NOT EXISTS vec_index USING vec0(
      embedding float[768],
      +file_path,
      +chunk_index
    )
  `);

  // Session 文件独立恢复
  const sessionFiles = await loadSessionFiles(agentId);
}
```

### 优劣分析

| 优势 | 劣势 |
|------|------|
| 混合搜索（向量 + FTS） | 架构复杂，同步逻辑分散 |
| Debounced 同步减少 IO | 多触发点增加调试难度 |
| 支持多种 embedding provider | SQLite 并发访问需小心 |
| Session 文件与索引分离 | 需要维护两个数据源一致性 |

---

## opencode

### Memory 写入策略

```typescript
// src/session/index.ts:685-705
export const updateMessage = fn(MessageV2.Info, async (msg) => {
  const { id, sessionID, ...data } = msg;
  Database.use((db) => {
    db.insert(MessageTable)
      .values({ id, session_id: sessionID, data })
      .onConflictDoUpdate({ target: MessageTable.id, set: { data } })
      .run();
    // 事件发布
    Database.effect(() =>
      Bus.publish(MessageV2.Event.Updated, { info: msg }),
    );
  });
  return msg;
});

// src/session/index.ts:754-775
export const updatePart = fn(UpdatePartInput, async (part) => {
  const { id, messageID, sessionID, ...data } = part;
  Database.use((db) => {
    db.insert(PartTable)
      .values({ id, message_id: messageID, session_id: sessionID, data })
      .onConflictDoUpdate({ target: PartTable.id, set: { data } })
      .run();
    Database.effect(() =>
      Bus.publish(MessageV2.Event.PartUpdated, { part: structuredClone(part) }),
    );
  });
});
```

| 维度 | 实现 |
|------|------|
| **写入时机** | 实时写入（消息/Part 级别） |
| **写入内容** | Message、Parts、会话元数据、摘要、diff |
| **存储介质** | SQLite（Drizzle ORM）、JSON 文件（storage/storage.ts） |
| **写入频率** | 高频率，每条消息/Part 实时写入 |

### Session-State 边界架构

```
┌────────────────────────────────────────────────────────────┐
│                    Session 运行时                          │
│  ┌─────────────────┐      ┌────────────────────────────┐  │
│  │   Session 对象   │◀────▶│   Event Bus  (发布-订阅)    │  │
│  │   (内存状态)     │      │                            │  │
│  └─────────────────┘      └────────────────────────────┘  │
│           │                           │                   │
│           │ 读写                     │ 事件通知          │
│           ▼                           ▼                   │
│  ┌─────────────────┐      ┌────────────────────────────┐  │
│  │   Database 层    │◀────▶│   Effect 系统              │  │
│  │  (Drizzle ORM)   │      │   (副作用管理)              │  │
│  └─────────────────┘      └────────────────────────────┘  │
└────────────────────────────────────────────────────────────┘
                    │
                    ▼
┌────────────────────────────────────────────────────────────┐
│                      持久化存储层                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │SessionTable │  │MessageTable │  │  PartTable  │        │
│  │  (会话元数据) │  │  (消息数据)  │  │  (片段数据)  │        │
│  └─────────────┘  └─────────────┘  └─────────────┘        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │storage JSON │  │  Summary    │  │   Diff      │        │
│  │ (辅助存储)   │  │  (摘要)      │  │  (变更)      │        │
│  └─────────────┘  └─────────────┘  └─────────────┘        │
└────────────────────────────────────────────────────────────┘
```

### 数据库 Schema 设计

```typescript
// src/session/session.sql.ts
export const SessionTable = sqliteTable("session", {
  id: text().$type<SessionID>().primaryKey(),
  project_id: text().$type<ProjectID>().notNull(),
  parent_id: text().$type<SessionID>(),  // Fork 支持
  slug: text().notNull(),
  title: text().notNull(),
  version: text().notNull(),
  share_url: text(),
  // 摘要统计
  summary_additions: integer(),
  summary_deletions: integer(),
  summary_files: integer(),
  summary_diffs: text({ mode: "json" }),
  // 回退点
  revert: text({ mode: "json" }).$type<{ messageID: MessageID }>(),
  // 权限
  permission: text({ mode: "json" }).$type<PermissionNext.Ruleset>(),
  // 时间戳
  time_created: integer(),
  time_updated: integer(),
  time_compacting: integer(),  // 上次压缩时间
  time_archived: integer(),    // 归档时间
});

export const MessageTable = sqliteTable("message", {
  id: text().$type<MessageID>().primaryKey(),
  session_id: text().$type<SessionID>().notNull(),
  time_created: integer(),
  data: text({ mode: "json" }).notNull().$type<InfoData>(),  // JSON 序列化
});

export const PartTable = sqliteTable("part", {
  id: text().$type<PartID>().primaryKey(),
  message_id: text().$type<MessageID>().notNull(),
  session_id: text().$type<SessionID>().notNull(),
  time_created: integer(),
  data: text({ mode: "json" }).notNull().$type<PartData>(),
});
```

### Event Bus 解耦机制

```typescript
// Database 层事件发布
class Database {
  static effects: (() => void)[] = [];

  static use<T>(fn: (db: DrizzleDB) => T): T {
    const result = fn(this.db);
    // 事务完成后执行副作用
    this.flushEffects();
    return result;
  }

  static effect(fn: () => void): void {
    this.effects.push(fn);
  }

  static flushEffects(): void {
    for (const fn of this.effects) {
      fn();  // 发布事件
    }
    this.effects = [];
  }
}

// Bus 订阅
Bus.subscribe(MessageV2.Event.Updated, ({ info }) => {
  // 更新 UI、通知其他模块
  ui.updateMessage(info);
});
```

### Compaction 与 Session 边界

```typescript
// src/session/compaction.ts
export async function isOverflow(input: {
  tokens: MessageV2.Assistant["tokens"];
  model: Provider.Model;
}) {
  const config = await Config.get();
  if (config.compaction?.auto === false) return false;

  const context = input.model.limit.context;
  const count = input.tokens.total ||
    input.tokens.input + input.tokens.output;

  // 保留区计算
  const reserved = config.compaction?.reserved ??
    Math.min(COMPACTION_BUFFER, maxOutputTokens(input.model));

  const usable = input.model.limit.input
    ? input.model.limit.input - reserved
    : context - maxOutputTokens(input.model);

  return count >= usable;
}

// Compaction 后更新 Session 元数据
export async function compactSession(sessionId: SessionID): Promise<void> {
  const summary = await generateSummary(sessionId);
  await Session.update({
    id: sessionId,
    summary_additions: summary.additions,
    summary_deletions: summary.deletions,
    time_compacting: Date.now(),
  });
}
```

### Fork 与 Session 复制

```typescript
// Session Fork 实现
export async function forkSession(
  parentId: SessionID,
  options?: ForkOptions
): Promise<Session> {
  const parent = await Session.get(parentId);

  // 复制 Session 元数据
  const newSession = await Session.create({
    parent_id: parentId,  // 记录父 Session
    project_id: parent.project_id,
    title: `${parent.title} (fork)`,
    ...
  });

  // 复制消息历史（可选）
  if (options?.includeHistory) {
    const messages = await Message.list({ session_id: parentId });
    for (const msg of messages) {
      await Message.create({
        session_id: newSession.id,
        data: msg.data,
      });
    }
  }

  return newSession;
}
```

### 恢复机制

```typescript
// 从 SQLite 恢复完整 Session
export async function resumeSession(sessionId: SessionID): Promise<Session> {
  // 1. 恢复 Session 元数据
  const session = await Session.get(sessionId);

  // 2. 恢复消息列表
  const messages = await Message.list({
    session_id: sessionId,
    orderBy: "time_created",
  });

  // 3. 恢复 Parts（流式消息的片段）
  for (const msg of messages) {
    msg.parts = await Part.list({ message_id: msg.id });
  }

  // 4. 重建内存状态
  return new Session({ ...session, messages });
}
```

### 优劣分析

| 优势 | 劣势 |
|------|------|
| 结构化数据模型，类型安全 | SQLite 可能成为瓶颈（需索引优化） |
| Event Bus 解耦，模块独立 | Schema 变更需要 migration |
| Fork 支持完整或部分复制 | JSON 列查询能力有限 |
| Session/ Message/ Part 分离清晰 | 复杂查询需要多表 join |

---

## 对比总结与建议

### Memory 写入策略对比

| 项目 | 写入时机 | 存储介质 | 内容粒度 | 同步机制 |
|------|----------|----------|----------|----------|
| **CoPaw** | 条件触发（Token 阈值） | SQLite + Chroma | 摘要级 | Hook-based |
| **kimi-cli** | 实时追加 | JSONL | 消息级 | 直接文件写入 |
| **openclaw** | 实时 + 延迟批量 | SQLite + sqlite-vec | 文件 chunk | Watcher + Timer |
| **opencode** | 实时 | SQLite（Drizzle） | Message/Part | Event Bus |

### Session-State 边界清晰度

```
清晰度排序：opencode > kimi-cli > openclaw > CoPaw

opencode:    SessionTable ↔ MessageTable ↔ PartTable (明确三层)
kimi-cli:    context.jsonl / wire.jsonl / state.json (文件分离)
openclaw:    SessionState ↔ MemoryIndexManager (较清晰)
CoPaw:       InMemoryMemory ↔ ReMeLight (边界模糊)
```

### 推荐架构

基于四个项目的最佳实践，推荐以下分层架构：

```
┌─────────────────────────────────────────────────────────────┐
│                      Session 运行时层                        │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐│
│  │  Working Memory │  │  Context Window │  │  Tool State  ││
│  │  (当前对话上下文) │  │  (Token 管理)    │  │  (临时锁等)   ││
│  └─────────────────┘  └─────────────────┘  └──────────────┘│
└─────────────────────────────────────────────────────────────┘
                              │ 触发条件/定时同步
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      同步管理层                              │
│  ┌─────────────────────────────────────────────────────────┐│
│  │  Sync Manager (debounced + 条件触发 + session 生命周期)   ││
│  │  - 批量写入    - 冲突检测    - 失败重试                    ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      持久化存储层                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │ Session Meta│  │ Message Log │  │   Vector Index      │ │
│  │  (SQLite)   │  │  (JSONL)    │  │  (sqlite-vec/       │ │
│  │ - 配置      │  │ - 完整历史   │  │   chroma)          │ │
│  │ - 摘要      │  │ - 按 session │  │ - 语义搜索          │ │
│  │ - 统计      │  │   分文件     │  │ - 混合检索          │ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### 关键设计建议

1. **写入策略**: 采用 "实时元数据 + 批量内容" 混合模式
   - Session 元数据实时写入 SQLite（小数据量、高频查询）
   - 消息历史批量追加 JSONL（大数据量、顺序读取）
   - 向量索引延迟同步（计算密集、可接受延迟）

2. **边界划分**: 三层边界模型
   - **Session 层**: 配置、摘要、权限、统计
   - **Message 层**: 消息历史、Parts、时间戳
   - **Index 层**: 向量嵌入、FTS 索引、文件 chunks

3. **同步机制**: Event Bus + Debounced Sync
   - 模块间通过 Event Bus 解耦
   - Sync Manager 聚合写入，减少 IO
   - 支持强制同步（session 结束、用户手动触发）

4. **恢复机制**: 分层恢复
   - Session 元数据从 SQLite 快速加载
   - 消息历史按需流式加载（分页）
   - 向量索引异步重建（后台线程）

5. **并发安全**: 读写分离 + 乐观锁
   - 读操作：直接查询 SQLite（WAL 模式支持并发读）
   - 写操作：通过 Sync Manager 队列化
   - Session 切换：乐观锁检测冲突

---

## 附录：代码参考

### CoPaw Memory Compaction Hook
```python
# src/copaw/agents/hooks/memory_compaction.py
class MemoryCompactionHook:
    async def __call__(self, agent: ReActAgent, kwargs: dict):
        token_count = agent.memory.get_token_count()
        threshold = agent.max_input_length * MEMORY_COMPACT_RATIO

        if token_count > threshold:
            messages = agent.memory.get_messages()
            reserved_count = max(3, int(len(messages) * MEMORY_RESERVE_RATIO))
            to_compact = messages[:-reserved_count]

            summary = await agent.memory_manager.compact_memory(to_compact)
            await agent.memory.update_compressed_summary(summary)
```

### kimi-cli Wire File Format
```python
# Wire File Protocol
{
  "protocol_version": "1.0",
  "records": [
    {"type": "message", "role": "user", "content": "..."},
    {"type": "dmail", "checkpoint_id": 5, "instruction": "..."},
    {"type": "checkpoint", "id": 5, "hash": "..."}
  ]
}
```

### openclaw Memory Sync Config
```typescript
// settings.json
{
  "memory": {
    "sync": {
      "onSessionStart": true,
      "onSessionEnd": true,
      "onFileChange": true,
      "intervalMs": 30000,
      "debounceMs": 1000
    }
  }
}
```

### opencode Database Effect
```typescript
// 事务 + 事件发布模式
Database.use((db) => {
  db.insert(MessageTable).values({...}).run();
  Database.effect(() => Bus.publish(Event.MessageCreated, {...}));
});
```

---

*报告生成时间: 2025-03-13*
*分析项目: CoPaw, kimi-cli, openclaw, opencode*
