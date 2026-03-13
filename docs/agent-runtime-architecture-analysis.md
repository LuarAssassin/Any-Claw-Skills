# AI Agent Runtime 主循环架构深度调研报告

## 概述

本报告对四个开源 AI Agent 项目（CoPaw、kimi-cli、openclaw、opencode）的 Agent Runtime 主循环架构进行深度技术分析，对比各自的执行流程、并发模型、状态管理和扩展机制。

---

## 一、各项目 Runtime 架构概览

### 架构对比表

| 维度 | CoPaw | kimi-cli | openclaw | opencode |
|------|-------|----------|----------|----------|
| **运行时基础** | AgentScope (ReActAgent) | 自研 KimiSoul | Pi Embedded Runner | Vercel AI SDK + Effect TS |
| **语言** | Python | Python | TypeScript | TypeScript (Bun) |
| **主循环模式** | ReAct (Reasoning-Acting) | Step Loop | Pi Event Stream | Vercel AI SDK Stream |
| **并发模型** | AsyncIO + Multi-worker | AsyncIO | Node.js Async | Effect TS ManagedRuntime |
| **子 Agent** | MCP Client | Labor Market | Subagent Registry | Agent 配置系统 |
| **状态持久化** | JSON 文件 | JSONL | JSONL | SQLite |
| **通信机制** | Channel Queue | Wire (Pub/Sub) | Pi Events | Stream Events |

---

## 二、各项目 Runtime 详解

### 1. CoPaw - ReAct 循环架构

#### 核心架构

基于 **AgentScope** 框架的 **ReActAgent**，采用经典的 Reasoning-Acting 循环：

```
┌─────────────────────────────────────────────────────────────────┐
│                     CoPaw ReAct Loop                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌──────────┐      ┌──────────┐      ┌──────────┐             │
│   │ User Msg │ ───> │ Reasoning│ ───> │  Acting  │             │
│   └──────────┘      │  (LLM)   │      │ (Tools)  │             │
│                     └────┬─────┘      └────┬─────┘             │
│                          │                 │                    │
│                          └────────┬────────┘                    │
│                                   │                             │
│                                   ▼                             │
│                          ┌──────────────┐                       │
│                          │ Tool Result  │                       │
│                          │ Inject Back  │                       │
│                          └──────────────┘                       │
│                                   │                             │
│                                   └────────> (Loop until done)  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### 主循环实现

```python
# src/copaw/agents/react_agent.py
class CoPawAgent(ToolGuardMixin, ReActAgent):
    def __init__(self, max_iters: int = 50, ...):
        # max_iters: 最大推理-行动迭代次数
        super().__init__(...)

    async def reply(self, message: Msg) -> Msg:
        """Main entry for message processing."""
        for _ in range(self.max_iters):
            # 1. Reasoning - LLM decides next action
            reasoning_msg = await self._reasoning()

            # 2. Acting - Execute tool calls
            if has_tool_calls(reasoning_msg):
                await self._acting(reasoning_msg)
            else:
                # No tool calls, return final response
                return reasoning_msg
```

#### 多通道并发模型

**Channel Manager 架构**:

```python
# src/copaw/app/channels/manager.py
class ChannelManager:
    def __init__(self, channels: List[BaseChannel]):
        self._queues: Dict[str, asyncio.Queue] = {}
        self._consumer_tasks: List[asyncio.Task] = []
        self._in_progress: Set[Tuple[str, str]] = set()

    async def _consume_channel_loop(self, channel_id: str, worker_index: int):
        """Worker loop: 4 workers per channel."""
        while True:
            payload = await q.get()
            key = ch.get_debounce_key(payload)

            # Acquire per-key lock for sequential processing
            async with key_lock:
                self._in_progress.add((channel_id, key))
                batch = _drain_same_key(q, ch, key, payload)
                await _process_batch(ch, batch)
```

**并发配置**:
- 每通道工作线程: `_CONSUMER_WORKERS_PER_CHANNEL = 4`
- 队列最大长度: `_CHANNEL_QUEUE_MAXSIZE = 1000`
- 消息防抖: 时间窗口内合并同一会话消息

#### 消息处理流程

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│  Channel │───>│ Channel  │───>│  Agent   │───>│  User    │
│  Input   │    │ Manager  │    │ Runner   │    │ Output   │
└──────────┘    └──────────┘    └──────────┘    └──────────┘
     │                │                │                │
     ▼                ▼                ▼                ▼
┌─────────┐    ┌─────────────┐   ┌─────────────┐   ┌─────────┐
│• Console│    │• Debounce   │   │• Tool Guard │   │• Stream │
│• Discord│    │• Queue per  │   │  Check      │   │  Events │
│• DingTalk    │  channel    │   │• ReAct Loop │   │• Channel│
│• Feishu │    │• Merge same │   │• Session   │   │  Send   │
└─────────┘    │  session    │   │  State      │   └─────────┘
               └─────────────┘   └─────────────┘
```

#### 心跳机制

```python
# src/copaw/app/crons/heartbeat.py
async def run_heartbeat_once(*, runner, channel_manager):
    """Periodic task execution based on HEARTBEAT.md."""
    hb = get_heartbeat_config()

    # Check active hours
    if not _in_active_hours(hb.active_hours):
        return

    # Read HEARTBEAT.md
    query_text = path.read_text().strip()

    # Execute agent
    async for event in runner.stream_query(req):
        await channel_manager.send_event(...)
```

**配置**:
```python
interval_seconds = parse_heartbeat_every("30m")  # 30分钟
# 支持格式: "30m", "1h", "2h30m"
```

---

### 2. kimi-cli - Step Loop 架构

#### 核心架构

**KimiSoul** 采用 **Step Loop** 模式，每个 Step 是一次完整的 LLM 调用：

```
┌─────────────────────────────────────────────────────────────────┐
│                     KimiSoul Step Loop                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  run() / run_ralph_loop()                               │   │
│  │     └── _turn()                                         │   │
│  │          └── _agent_loop()                              │   │
│  │               └── while True:                           │   │
│  │                     └── _step()  <- 单次 LLM 调用        │   │
│  │                          ├── collect_injections()       │   │
│  │                          ├── kosong.step() (LLM)        │   │
│  │                          ├── execute_tools()            │   │
│  │                          └── grow_context()             │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### 主循环实现

```python
# src/kimi_cli/soul/kimisoul.py
class KimiSoul:
    async def _agent_loop(self) -> TurnOutcome:
        """The main agent loop for one run."""
        step_no = 0
        while True:
            step_no += 1
            if step_no > self._loop_control.max_steps_per_turn:
                raise MaxStepsReached(...)

            wire_send(StepBegin(n=step_no))

            # 1. Auto-compact if needed
            if should_auto_compact(...):
                await self.compact_context()

            # 2. Create checkpoint
            await self._checkpoint()

            # 3. Execute one step
            try:
                step_outcome = await self._step()
            except BackToTheFuture as e:
                # D-Mail triggered time travel
                await self._handle_back_to_the_future(e)
                continue

            # 4. Check if done
            if step_outcome.done:
                return step_outcome

    async def _step(self) -> StepOutcome:
        """Single LLM invocation step."""
        # 1. Collect dynamic injections
        injections = await self._collect_injections()

        # 2. Normalize history
        history = normalize_history(self._context.history)

        # 3. Call LLM
        result = await kosong.step(
            system_prompt=self._system_prompt,
            history=history,
            toolset=self._agent.toolset,
        )

        # 4. Execute tools in parallel
        if result.tool_calls:
            tool_results = await asyncio.gather(*[
                self._agent.toolset.handle(tc) for tc in result.tool_calls
            ])

        # 5. Grow context
        await self._grow_context(result, tool_results)

        return StepOutcome(done=not result.tool_calls)
```

#### Checkpoint 与 D-Mail

**Checkpoint 机制**:

```python
# src/kimi_cli/soul/context.py
class Context:
    async def checkpoint(self, add_user_message: bool):
        checkpoint_id = self._next_checkpoint_id
        self._next_checkpoint_id += 1

        # Persist checkpoint marker
        async with aiofiles.open(self._file_backend, "a") as f:
            await f.write(json.dumps({
                "role": "_checkpoint",
                "id": checkpoint_id
            }) + "\n")

    async def revert_to(self, checkpoint_id: int):
        """Revert context to a previous checkpoint."""
        # Truncate history to checkpoint
        # Restore from file
```

**D-Mail（时间旅行）**:

```python
# src/kimi_cli/soul/denwarenji.py
class DenwaRenji:
    def send_dmail(self, dmail: DMail):
        """Send message to past checkpoint."""
        if dmail.checkpoint_id >= self._n_checkpoints:
            raise DenwaRenjiError("Checkpoint does not exist")
        self._pending_dmail = dmail

# In _step()
if dmail := self._denwa_renji.fetch_pending_dmail():
    raise BackToTheFuture(
        checkpoint_id=dmail.checkpoint_id,
        messages=[Message(...)],  # Inject D-Mail as system message
    )
```

**D-Mail 流程图**:

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ SendDMail   │────>│ DenwaRenji  │────>│ BackToTheFuture
│ Tool Call   │     │ store       │     │ Exception   │
└─────────────┘     └─────────────┘     └──────┬──────┘
                                               │
                    ┌──────────────────────────┘
                    ▼
┌─────────────────────────────────────────────────────────────┐
│ _agent_loop catches BackToTheFuture                         │
│                                                             │
│ await self._context.revert_to(e.checkpoint_id)              │
│ await self._context.append_message(e.messages)              │
│ continue  # Restart loop from checkpoint                    │
└─────────────────────────────────────────────────────────────┘
```

#### Labor Market（子 Agent）

```python
# src/kimi_cli/soul/agent.py
class LaborMarket:
    def __init__(self):
        self.fixed_subagents: dict[str, Agent] = {}
        self.dynamic_subagents: dict[str, Agent] = {}

    def add_fixed_subagent(self, name: str, agent: Agent, description: str):
        """Pre-defined subagent from config."""
        self.fixed_subagents[name] = agent

    def add_dynamic_subagent(self, name: str, agent: Agent):
        """Runtime-created subagent, shares LaborMarket."""
        self.dynamic_subagents[name] = agent
```

**子 Agent 创建**:

```python
# Runtime copy strategies
def copy_for_fixed_subagent(self) -> Runtime:
    """Independent LaborMarket for isolation."""
    return Runtime(
        ...,
        labor_market=LaborMarket(),  # New instance
    )

def copy_for_dynamic_subagent(self) -> Runtime:
    """Shared LaborMarket for task delegation."""
    return Runtime(
        ...,
        labor_market=self.labor_market,  # Shared
    )
```

#### 上下文压缩

```python
# src/kimi_cli/soul/compaction.py
class SimpleCompaction:
    async def compact(self, messages: Sequence[Message], llm: LLM):
        # 1. Prepare: split into compact + preserve
        compact_msg, to_preserve = self.prepare(messages)

        # 2. Call LLM to summarize
        result = await kosong.step(
            system_prompt="Compact conversation context",
            history=[compact_msg],
        )

        # 3. Build compacted messages
        compacted = [
            Message(role="user", content=[
                system("Previous context compacted:"),
                *result.message.content,
            ]),
            *to_preserve,  # Recent N messages preserved
        ]

        return CompactionResult(messages=compacted)
```

---

### 3. openclaw - Pi Embedded Runner 架构

#### 核心架构

基于 **Pi Agent Core** 的 **Event Stream** 模式：

```
─────────────────────────────────────────────────────────────────┐
│                  Pi Embedded Runner                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  runEmbeddedPiAgent()                                           │
│    └── subscribeEmbeddedPiSession()                             │
│          └── for await (event of session.events)                │
│                ├── assistant.messageDelta                       │
│                ├── assistant.toolCall                           │
│                ├── assistant.toolResult                         │
│                └── assistant.finish                             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### 主循环实现

```typescript
// src/agents/pi-embedded-runner/run.ts
export async function runEmbeddedPiAgent(params): Promise<EmbeddedPiRunResult> {
    // 1. Lane Queue for serialization
    const sessionLane = resolveSessionLane(params.sessionKey);
    const globalLane = resolveGlobalLane(params.lane);

    // 2. Create Agent Session
    const { session } = await createAgentSession({...});

    // 3. Event stream processing
    for await (const event of session.events) {
        switch (event.type) {
            case "assistant.messageDelta":
                await handleMessageDelta(event);
                break;
            case "assistant.toolCall":
                await handleToolCall(event);
                break;
            case "assistant.toolResult":
                await handleToolResult(event);
                break;
            case "assistant.finish":
                return { status: "complete" };
        }
    }
}
```

#### 自动回复系统

```typescript
// src/auto-reply/reply/agent-runner.ts
export async function runReplyAgent(params): Promise<void> {
    const mode = params.queueMode || "steer";  // steer | followup | collect

    switch (mode) {
        case "steer":
            // Inject message into current run
            await steerCurrentRun(params);
            break;
        case "followup":
            // Wait for current run, then start new
            await waitAndStartNew(params);
            break;
        case "collect":
            // Batch messages
            await collectAndBatch(params);
            break;
    }
}
```

#### 多智能体架构

```typescript
// src/agents/subagent-registry.ts
export class SubagentRegistry {
    private subagents: Map<string, SubagentInfo> = new Map();

    register(id: string, config: SubagentConfig): void {
        this.subagents.set(id, {
            id,
            workspace: config.workspace,
            model: config.model,
            skills: config.skills,
        });
    }

    async spawn(parentSession: string, subagentId: string): Promise<string> {
        // Create isolated session for subagent
        const subagentSession = await createSession({
            parent: parentSession,
            agent: subagentId,
        });
        return subagentSession.id;
    }
}
```

#### Hook 系统

```typescript
// src/plugins/hooks.ts
export type HookType =
    | "before_model_resolve"
    | "before_prompt_build"
    | "before_agent_start"
    | "agent_end"
    | "before_compaction"
    | "after_compaction"
    | "message_received"
    | "message_sending"
    | "message_sent"
    | "before_tool_call"
    | "after_tool_call"
    | "session_start"
    | "session_end";

// Hook execution
export async function runHooks(type: HookType, context: HookContext): Promise<void> {
    const hooks = getHooksForType(type);
    for (const hook of hooks) {
        await hook(context);
    }
}
```

#### 心跳机制

```typescript
// src/infra/heartbeat-runner.ts
export async function runHeartbeatIfNeeded(params): Promise<boolean> {
    const heartbeatEvery = resolveHeartbeatEvery(agentConfig);
    const timeSinceLast = Date.now() - lastHeartbeatAt;

    if (timeSinceLast < heartbeatEvery) {
        return false;  // Not yet
    }

    // Read HEARTBEAT.md
    const queryText = await readFile("HEARTBEAT.md");

    // Trigger heartbeat run
    await runReplyAgent({
        commandBody: queryText,
        isHeartbeat: true,
    });
}
```

---

### 4. opencode - Vercel AI SDK 架构

#### 核心架构

基于 **Vercel AI SDK** 的 **Stream Processing** 模式：

```
┌─────────────────────────────────────────────────────────────────┐
│                  OpenCode Agent Loop                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  SessionProcessor.create()                                      │
│    └── LLM.stream()  (Vercel AI SDK streamText)                │
│          └── for await (value of stream.fullStream)             │
│                ├── "start"                                      │
│                ├── "reasoning-start/delta/end"                  │
│                ├── "tool-call"                                  │
│                ├── "tool-result"                                │
│                ├── "finish-step"                                │
│                └── "finish"                                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### 主循环实现

```typescript
// packages/opencode/src/session/processor.ts
export namespace SessionProcessor {
    export function create(input: { sessionID, model, abort }) {
        return {
            async process(streamInput: LLM.StreamInput) {
                while (true) {
                    const stream = await LLM.stream(streamInput);

                    for await (const value of stream.fullStream) {
                        switch (value.type) {
                            case "start":
                                await handleStart(value);
                                break;
                            case "reasoning-start":
                                await handleReasoningStart(value);
                                break;
                            case "tool-call":
                                await handleToolCall(value);
                                break;
                            case "tool-result":
                                await handleToolResult(value);
                                break;
                            case "finish":
                                return;  // Done
                        }
                    }
                }
            }
        };
    }
}
```

#### Agent 切换

```typescript
// packages/opencode/src/agent/agent.ts
export const Agent = {
    build: {
        name: "build",
        mode: "primary",
        permission: PermissionNext.merge(defaults, user),
    },
    plan: {
        name: "plan",
        mode: "primary",
        permission: PermissionNext.merge(defaults, {
            edit: { "*": "deny" },  // No edits in plan mode
        }),
    },
    explore: {
        name: "explore",
        mode: "subagent",
        tools: ["glob", "grep", "read_file"],
    },
    compaction: {
        name: "compaction",
        mode: "primary",
        // Dedicated agent for context compaction
    },
};
```

#### Part 消息模型

```typescript
// packages/opencode/src/session/message-v2.ts
type Part =
    | TextPart       // 文本内容
    | ToolPart       // 工具调用
    | ReasoningPart  // 推理内容
    | PatchPart      // 代码变更
    | StepStartPart  // 步骤开始
    | StepFinishPart // 步骤结束
    | CompactionPart; // 会话压缩

// Message with parts
export interface MessageV2 {
    id: string;
    role: "user" | "assistant" | "system";
    parts: Part[];
}
```

#### 快照与回滚

```typescript
// packages/opencode/src/session/index.ts
export const setRevert = fn(
    z.object({
        sessionID: SessionID.zod,
        revert: RevertState,
        summary: SessionSummary,
    }),
    async (input) => {
        return Database.use((db) => {
            return db
                .update(SessionTable)
                .set({
                    revert: input.revert,
                    summary_additions: input.summary?.additions,
                    summary_deletions: input.summary?.deletions,
                    summary_files: input.summary?.files,
                })
                .where(eq(SessionTable.id, input.sessionID))
                .returning()
                .get();
        });
    }
);

// Revert to snapshot
export const revertTo = fn(
    z.object({ sessionID: SessionID.zod }),
    async (input) => {
        const session = await get({ sessionID: input.sessionID });
        if (!session.revert) throw new Error("No revert point");

        // Restore files from revert.snapshot
        await restoreSnapshot(session.revert.snapshot);
    }
);
```

---

## 三、核心机制对比

### 1. 循环模式对比

| 项目 | 循环模式 | 特点 |
|------|---------|------|
| **CoPaw** | ReAct | reasoning-acting 分离，max_iters 限制 |
| **kimi-cli** | Step Loop | 单 LLM 调用 = 1 step，动态注入 |
| **openclaw** | Event Stream | Pi Agent Core 事件流 |
| **opencode** | Stream Processing | Vercel AI SDK 流式处理 |

### 2. 子 Agent 对比

| 项目 | 子 Agent 机制 | 通信方式 |
|------|--------------|---------|
| **CoPaw** | MCP Client | stdio/HTTP |
| **kimi-cli** | Labor Market | Wire (Pub/Sub) |
| **openclaw** | Subagent Registry | Pi Events |
| **opencode** | Agent Config | 函数调用 |

### 3. 状态持久化对比

| 项目 | 存储格式 | 特点 |
|------|---------|------|
| **CoPaw** | JSON | 文件存储，会话状态 |
| **kimi-cli** | JSONL | 追加写入，Checkpoint 标记 |
| **openclaw** | JSONL | Pi 原生格式 |
| **opencode** | SQLite | 结构化查询，强类型 |

### 4. 特殊机制对比

| 项目 | 特色机制 | 说明 |
|------|---------|------|
| **CoPaw** | ToolGuard + 心跳 | 六层安全防护 + 定时巡逻 |
| **kimi-cli** | D-Mail + Checkpoint | 时间旅行回溯 |
| **openclaw** | Auto-Reply + Hooks | 自动回复 + 扩展钩子 |
| **opencode** | Snapshot + Revert | 代码快照回滚 |

---

## 四、推荐 Runtime 架构

基于以上分析，推荐以下融合架构：

```
┌─────────────────────────────────────────────────────────────────┐
│                   Recommended Agent Runtime                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Loop Layer (Step Loop)                                 │   │
│  │  - Inspired by: kimi-cli                                │   │
│  │  - Max steps per turn: configurable                     │   │
│  │  - Auto-compact trigger                                 │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │                           ▼                               │ │
│  │  ┌─────────────────────────────────────────────────────┐ │ │
│  │  │  Step Execution                                     │ │ │
│  │  │  1. Collect dynamic injections                      │ │ │
│  │  │  2. Check context limit -> compact if needed        │ │ │
│  │  │  3. Create checkpoint                               │ │ │
│  │  │  4. LLM call (Vercel AI SDK style)                  │ │ │
│  │  │  5. Execute tools in parallel                       │ │ │
│  │  │  6. Grow context                                    │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  │                           │                               │ │
│  │                           ▼                               │ │
│  │  ┌─────────────────────────────────────────────────────┐ │ │
│  │  │  Event Stream (openclaw style)                      │ │ │
│  │  │  - messageDelta                                     │ │ │
│  │  │  - toolCall / toolResult                            │ │ │
│  │  │  - reasoning                                        │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────────────────┘ │
│                              │                                  │
│  ┌───────────────────────────┼─────────────────────────────── │
│  │                           ▼                               │ │
│  │  ┌─────────────────────────────────────────────────────┐ │ │
│  │  │  Subagent / Labor Market (kimi-cli style)           │ │ │
│  │  │  - Fixed subagents: independent LaborMarket         │ │ │
│  │  │  - Dynamic subagents: shared LaborMarket            │ │ │
│  │  │  - Task delegation via Task tool                    │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────────────────┘ │
│                              │                                  │
│  ┌───────────────────────────┼───────────────────────────────┐ │
│  │                           ▼                               │ │
│  │  ┌─────────────────────────────────────────────────────┐ │ │
│  │  │  Persistence (opencode style)                       │ │ │
│  │  │  - SQLite: structured, queryable                    │ │ │
│  │  │  - Session + Message + Part tables                  │ │ │
│  │  │  - Snapshot for revert                              │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────────────────┘ │
│                              │                                  │
│  ┌───────────────────────────┼───────────────────────────────┐ │
│  │                           ▼                               │ │
│  │  ┌─────────────────────────────────────────────────────┐ │ │
│  │  │  Hook System (openclaw style)                       │ │ │
│  │  │  - before_tool_call / after_tool_call               │ │ │
│  │  │  - before_prompt_build / after_compaction           │ │ │
│  │  │  - Plugin extension points                          │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────────────────┘ │
│                              │                                  │
│  ┌───────────────────────────┼───────────────────────────────┐ │
│  │                           ▼                               │ │
│  │  ┌─────────────────────────────────────────────────────┐ │ │
│  │  │  Special Features                                   │ │ │
│  │  │  - Checkpoint + D-Mail (kimi-cli)                   │ │ │
│  │  │  - ToolGuard (CoPaw)                                │ │ │
│  │  │  - Heartbeat (CoPaw/openclaw)                       │ │ │
│  │  │  - Auto-reply (openclaw)                            │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 关键实现代码

```typescript
// Recommended Agent Runtime Implementation

interface LoopConfig {
    maxStepsPerTurn: number;
    maxRetriesPerStep: number;
    compactionTriggerRatio: number;
    reservedContextSize: number;
}

class AgentRuntime {
    private context: Context;
    private laborMarket: LaborMarket;
    private checkpointManager: CheckpointManager;
    private compaction: Compaction;
    private toolGuard: ToolGuard;
    private hooks: HookSystem;

    async run(userInput: string): Promise<void> {
        // Initialize
        await this.initialize();

        // Main loop
        for (let step = 0; step < this.config.maxStepsPerTurn; step++) {
            // 1. Dynamic injection
            const injections = await this.collectInjections();

            // 2. Check and compact
            if (await this.shouldCompact()) {
                await this.compactContext();
            }

            // 3. Create checkpoint
            const checkpointId = await this.checkpointManager.create();

            // 4. Execute step
            try {
                const outcome = await this.executeStep(injections);

                if (outcome.done) {
                    return;
                }
            } catch (e) {
                if (e instanceof DMailTriggered) {
                    // Time travel
                    await this.checkpointManager.revertTo(e.checkpointId);
                    await this.context.injectDMail(e.message);
                    continue;
                }
                throw e;
            }
        }
    }

    private async executeStep(injections: Injection[]): Promise<StepOutcome> {
        // Run hooks
        await this.hooks.run("before_step", { context: this.context });

        // LLM call
        const stream = await this.llm.stream({
            systemPrompt: this.buildSystemPrompt(injections),
            history: this.context.history,
            tools: this.toolset,
        });

        // Process stream events
        for await (const event of stream) {
            switch (event.type) {
                case "tool-call":
                    // ToolGuard check
                    if (!await this.toolGuard.check(event.toolCall)) {
                        throw new ToolGuardError();
                    }
                    // Execute tool
                    const result = await this.executeTool(event.toolCall);
                    await this.context.addToolResult(result);
                    break;

                case "finish":
                    return { done: true };
            }
        }

        return { done: false };
    }

    private async executeTool(call: ToolCall): Promise<ToolResult> {
        // Run hooks
        await this.hooks.run("before_tool_call", { toolCall: call });

        // Execute
        const result = await this.toolset.execute(call);

        // Run hooks
        await this.hooks.run("after_tool_call", { toolCall: call, result });

        return result;
    }
}
```

---

## 五、总结

### 各项目优势

| 项目 | Runtime 优势 | 独特机制 |
|------|-------------|---------|
| **CoPaw** | ReAct 经典架构 + AgentScope | ToolGuard 六层防护 + 心跳 |
| **kimi-cli** | Step Loop 清晰 + D-Mail | 时间旅行回溯 + Labor Market |
| **openclaw** | Pi Embedded + Hook 系统 | 自动回复 + 完整扩展钩子 |
| **opencode** | Vercel AI SDK + Effect TS | 类型安全 + 代码快照回滚 |

### 推荐技术选型

| 组件 | 推荐实现 | 来源 |
|------|---------|------|
| **主循环** | Step Loop + Event Stream 混合 | kimi-cli + openclaw |
| **子 Agent** | Labor Market + MCP | kimi-cli + CoPaw |
| **持久化** | SQLite + JSONL 混合 | opencode + kimi-cli |
| **通信** | Wire (Pub/Sub) | kimi-cli |
| **Hooks** | Before/After 事件 | openclaw |
| **特殊功能** | Checkpoint + D-Mail + ToolGuard | kimi-cli + CoPaw |

此方案融合了四个项目的最佳实践，兼顾执行效率、扩展性和安全性，适用于生产级 AI Agent 系统。
