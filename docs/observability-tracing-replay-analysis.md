# Observability / Tracing / Replay 架构分析

## 目录
1. [核心概念](#核心概念)
2. [CoPaw 日志与指标](#copaw-日志与指标)
3. [kimi-cli Wire 事件流](#kimi-cli-wire-事件流)
4. [openclaw 追踪与日志](#openclaw-追踪与日志)
5. [opencode 会话与快照](#opencode-会话与快照)
6. [架构对比与推荐](#架构对比与推荐)

---

## 核心概念

### 可观测性三支柱

```
┌─────────────────────────────────────────────────────────────┐
│                    Observability                            │
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │    Logs     │  │   Metrics   │  │      Traces         │ │
│  │             │  │             │  │                     │ │
│  │ - 结构化    │  │ - Token使用 │  │ - Trace ID          │ │
│  │ - 级别控制  │  │ - 性能指标  │  │ - Span 层级         │ │
│  │ - 轮转归档  │  │ - 成功率    │  │ - 上下文传播        │ │
│  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘ │
│         │                │                    │            │
│         └────────────────┼────────────────────┘            │
│                          ▼                                 │
│  ┌─────────────────────────────────────────────────────┐  │
│  │                    Replay 重放                       │  │
│  │  - 会话重放      - 检查点恢复    - 时间旅行调试      │  │
│  │  - Wire 日志     - Git 快照      - 事件溯源         │  │
│  └─────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 链路追踪模型

```
┌─────────────────────────────────────────────────────────────┐
│                      Trace (完整请求链路)                    │
│  TraceID: trace_abc123                                      │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Span A: User Request (root)                         │   │
│  │ SpanID: span_001  ParentID: null                    │   │
│  │ Duration: 5000ms                                    │   │
│  │ Tags: {user_id: "u123", channel: "feishu"}          │   │
│  │                                                     │   │
│  │  ┌─────────────────────────────────────────────┐   │   │
│  │  │ Span B: LLM Call                             │   │   │
│  │  │ SpanID: span_002  ParentID: span_001         │   │   │
│  │  │ Duration: 2000ms                             │   │   │
│  │  │ Tags: {model: "gpt-4", tokens: 1500}         │   │   │
│  │  │                                             │   │   │
│  │  │  ┌─────────────────────────────────────┐   │   │   │
│  │  │  │ Span C: Tool Call (search)          │   │   │   │
│  │  │  │ SpanID: span_003  ParentID: span_002│   │   │   │
│  │  │  │ Duration: 500ms                     │   │   │   │
│  │  │  │ Tags: {tool: "search", query: "..."}│   │   │   │
│  │  │  └─────────────────────────────────────┘   │   │   │
│  │  │                                             │   │   │
│  │  │  ┌─────────────────────────────────────┐   │   │   │
│  │  │  │ Span D: Tool Call (file_read)       │   │   │   │
│  │  │  │ SpanID: span_004  ParentID: span_002│   │   │   │
│  │  │  │ Duration: 200ms                     │   │   │   │
│  │  │  │ Tags: {tool: "file_read", path:"..."}│   │   │   │
│  │  │  └─────────────────────────────────────┘   │   │   │
│  │  └─────────────────────────────────────────────┘   │   │
│  │                                                     │   │
│  │  ┌─────────────────────────────────────────────┐   │   │
│  │  │ Span E: Response Send                        │   │   │
│  │  │ SpanID: span_005  ParentID: span_001         │   │   │
│  │  │ Duration: 100ms                              │   │   │
│  │  └─────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 重放机制类型

| 类型 | 原理 | 适用场景 |
|------|------|----------|
| **事件溯源** | 记录所有输入事件，按序重放 | 确定性调试、回归测试 |
| **状态快照** | 定期保存完整状态 | 快速恢复、断点续传 |
| **Wire 日志** | 记录所有 I/O 交互 | 前后端通信分析 |
| **Git 快照** | 代码版本快照 | 代码变更追踪 |

---

## CoPaw 日志与指标

### 日志系统

```python
# src/copaw/utils/logging.py
import logging
from colorama import Fore, Style, init

class ColorFormatter(logging.Formatter):
    """Colored log formatter with ANSI codes."""

    COLORS = {
        "CRITICAL": Fore.RED + Style.BRIGHT,
        "ERROR": Fore.RED,
        "WARNING": Fore.YELLOW,
        "INFO": Fore.GREEN,
        "DEBUG": Fore.CYAN,
    }

    def format(self, record: logging.LogRecord) -> str:
        # 添加颜色
        color = self.COLORS.get(record.levelname, "")
        reset = Style.RESET_ALL

        # 格式化: [TIME] [LEVEL] NAME: MESSAGE
        formatted = f"[{self.formatTime(record)}] "
        formatted += f"[{color}{record.levelname}{reset}] "
        formatted += f"{record.name}: {record.getMessage()}"

        return formatted


def setup_logging(
    level: str = "INFO",
    log_file: Optional[Path] = None,
    namespace: str = "copaw",
) -> logging.Logger:
    """Setup logging with colored console output and optional file handler."""
    logger = logging.getLogger(namespace)
    logger.setLevel(getattr(logging, level.upper()))

    # 控制台处理器
    console_handler = logging.StreamHandler()
    console_handler.setFormatter(ColorFormatter())
    logger.addHandler(console_handler)

    # 文件处理器（带轮转）
    if log_file:
        if platform.system() == "Darwin":  # macOS
            file_handler = RotatingFileHandler(
                log_file,
                maxBytes=10 * 1024 * 1024,  # 10MB
                backupCount=5,
            )
        else:
            file_handler = logging.FileHandler(log_file)

        file_handler.setFormatter(
            logging.Formatter(
                "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
            )
        )
        logger.addHandler(file_handler)

    return logger
```

### Token 使用指标

```python
# src/copaw/token_usage/manager.py
from pydantic import BaseModel
from typing import Dict, List, Optional
from datetime import date, datetime

class TokenUsageRecord(BaseModel):
    """Single token usage record."""
    timestamp: datetime
    provider: str
    model: str
    input_tokens: int
    output_tokens: int
    total_tokens: int
    cost_usd: Optional[float] = None

class TokenUsageStats(BaseModel):
    """Aggregated token usage statistics."""
    date: date
    provider: str
    model: str
    total_requests: int
    total_input_tokens: int
    total_output_tokens: int
    total_tokens: int
    total_cost_usd: Optional[float] = None

class TokenUsageManager:
    """Singleton manager for token usage tracking."""

    _instance: Optional["TokenUsageManager"] = None
    _lock = asyncio.Lock()

    def __init__(self, storage_path: Path):
        self.storage_path = storage_path
        self._cache: List[TokenUsageRecord] = []
        self._flush_interval = 60  # 每60秒刷盘
        self._flush_task: Optional[asyncio.Task] = None

    @classmethod
    async def get_instance(cls) -> "TokenUsageManager":
        if cls._instance is None:
            async with cls._lock:
                if cls._instance is None:
                    storage_path = get_data_dir() / "token_usage.json"
                    cls._instance = cls(storage_path)
                    await cls._instance._load()
        return cls._instance

    async def record(
        self,
        provider: str,
        model: str,
        input_tokens: int,
        output_tokens: int,
        cost_usd: Optional[float] = None,
    ) -> None:
        """Record a token usage entry."""
        record = TokenUsageRecord(
            timestamp=datetime.now(timezone.utc),
            provider=provider,
            model=model,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            total_tokens=input_tokens + output_tokens,
            cost_usd=cost_usd,
        )
        self._cache.append(record)

        # 触发异步刷盘
        if len(self._cache) >= 100:
            await self._flush()

    async def get_stats(
        self,
        start_date: Optional[date] = None,
        end_date: Optional[date] = None,
        provider: Optional[str] = None,
        model: Optional[str] = None,
    ) -> List[TokenUsageStats]:
        """Query aggregated statistics with filters."""
        records = await self._load_all()

        # 应用过滤
        filtered = [
            r for r in records
            if (not start_date or r.timestamp.date() >= start_date)
            and (not end_date or r.timestamp.date() <= end_date)
            and (not provider or r.provider == provider)
            and (not model or r.model == model)
        ]

        # 按日期/提供商/模型聚合
        stats: Dict[tuple, TokenUsageStats] = {}
        for r in filtered:
            key = (r.timestamp.date(), r.provider, r.model)
            if key not in stats:
                stats[key] = TokenUsageStats(
                    date=key[0],
                    provider=key[1],
                    model=key[2],
                    total_requests=0,
                    total_input_tokens=0,
                    total_output_tokens=0,
                    total_tokens=0,
                )
            s = stats[key]
            s.total_requests += 1
            s.total_input_tokens += r.input_tokens
            s.total_output_tokens += r.output_tokens
            s.total_tokens += r.total_tokens
            if r.cost_usd:
                s.total_cost_usd = (s.total_cost_usd or 0) + r.cost_usd

        return list(stats.values())

    async def _flush(self) -> None:
        """Async flush cache to disk."""
        if not self._cache:
            return

        data = [r.model_dump() for r in self._cache]

        # 原子写入
        temp_file = self.storage_path.with_suffix(".tmp")
        async with aiofiles.open(temp_file, "w") as f:
            await f.write(json.dumps(data, indent=2, default=str))
        temp_file.rename(self.storage_path)

        self._cache.clear()

    async def _load(self) -> None:
        """Load existing data."""
        if not self.storage_path.exists():
            return

        async with aiofiles.open(self.storage_path) as f:
            content = await f.read()
            data = json.loads(content)
            self._cache = [TokenUsageRecord(**r) for r in data]
```

### 健康检查心跳

```python
# src/copaw/app/crons/heartbeat.py
class HeartbeatTask:
    """Periodic health check and status report task."""

    def __init__(
        self,
        interval: str = "1h",  # 支持: 30m, 1h, 2h30m, 90s
        target: str = "last",  # "last" 或 "main"
        active_hours: Optional[tuple[int, int]] = None,  # (9, 18) 工作时间
    ):
        self.interval = self._parse_interval(interval)
        self.target = target
        self.active_hours = active_hours

    async def run(self) -> None:
        """Execute heartbeat check."""
        # 检查活跃时间段
        if self.active_hours:
            now = datetime.now().hour
            if not (self.active_hours[0] <= now < self.active_hours[1]):
                return  # 非工作时间跳过

        try:
            # 收集健康指标
            health = await self._collect_health_metrics()

            # 构建状态报告
            report = self._build_report(health)

            # 发送到目标渠道
            await self._send_report(report)

        except Exception as e:
            logger.error(f"Heartbeat failed: {e}")

    async def _collect_health_metrics(self) -> Dict[str, Any]:
        """Collect system health metrics."""
        return {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "memory_usage": psutil.virtual_memory().percent,
            "cpu_usage": psutil.cpu_percent(),
            "disk_usage": psutil.disk_usage("/").percent,
            "active_sessions": len(get_active_sessions()),
            "pending_tasks": get_pending_task_count(),
            "token_usage_today": await self._get_today_token_usage(),
        }

    def _build_report(self, health: Dict[str, Any]) -> str:
        """Build human-readable health report."""
        return f"""
🫀 Heartbeat Report
───────────────────
⏰ Time: {health['timestamp']}
💾 Memory: {health['memory_usage']}%
🔲 CPU: {health['cpu_usage']}%
💿 Disk: {health['disk_usage']}%
👥 Active Sessions: {health['active_sessions']}
📋 Pending Tasks: {health['pending_tasks']}
🔢 Token Usage Today: {health['token_usage_today']}
        """.strip()

    def _parse_interval(self, interval: str) -> int:
        """Parse interval string to seconds."""
        total = 0
        # 匹配数字+单位
        for match in re.finditer(r'(\d+)([hms])', interval.lower()):
            value, unit = int(match.group(1)), match.group(2)
            if unit == 'h':
                total += value * 3600
            elif unit == 'm':
                total += value * 60
            else:
                total += value
        return total
```

### 会话追踪

```python
# src/copaw/agents/session.py
class SafeJSONSession(SessionBase):
    """Cross-platform safe session storage."""

    def __init__(
        self,
        session_id: str,
        working_dir: Path,
        memory: Optional[MemoryBase] = None,
    ):
        self.session_id = session_id
        self.working_dir = working_dir
        self.session_file = self._get_safe_path(working_dir, f"{session_id}.json")
        self.memory = memory or TemporaryMemory()

    def _get_safe_path(self, base: Path, filename: str) -> Path:
        """Get cross-platform safe file path."""
        # 处理 Windows 非法字符
        if platform.system() == "Windows":
            filename = re.sub(r'[<>:"/\\|?*]', '_', filename)
        return base / filename

    async def save_session_state(self, state: Dict[str, Any]) -> None:
        """Save session state atomically."""
        temp_file = self.session_file.with_suffix(".tmp")
        async with aiofiles.open(temp_file, "w") as f:
            await f.write(json.dumps(state, indent=2, default=str))
        temp_file.rename(self.session_file)

    async def load_session_state(self) -> Dict[str, Any]:
        """Load session state."""
        if not self.session_file.exists():
            return {}

        async with aiofiles.open(self.session_file) as f:
            content = await f.read()
            return json.loads(content)

    async def update_session_state(
        self,
        key_path: str,
        value: Any,
    ) -> None:
        """Update nested session state by key path."""
        state = await self.load_session_state()

        # 支持点号路径: "metadata.user.name"
        keys = key_path.split(".")
        current = state
        for key in keys[:-1]:
            if key not in current:
                current[key] = {}
            current = current[key]
        current[keys[-1]] = value

        await self.save_session_state(state)
```

---

## kimi-cli Wire 事件流

### Wire 协议架构

```typescript
// web/src/hooks/wireTypes.ts
// Wire 协议是前后端通信的事件流协议

// ========== 事件类型定义 ==========

// Turn 生命周期事件
type TurnBeginEvent = {
  type: "turn_begin";
  seq: number;
  request_id: string;
  timestamp: number;
  user_input: string;
  context_size: number;
};

type TurnEndEvent = {
  type: "turn_end";
  seq: number;
  request_id: string;
  timestamp: number;
  finish_reason: "stop" | "length" | "tool_calls" | "error";
  total_steps: number;
};

// Step 生命周期事件
type StepBeginEvent = {
  type: "step_begin";
  seq: number;
  step_no: number;
  timestamp: number;
};

type StepInterruptedEvent = {
  type: "step_interrupted";
  seq: number;
  step_no: number;
  reason: "timeout" | "cancelled" | "error";
  error?: string;
};

// 内容流事件
type ContentPartEvent =
  | { type: "text_delta"; seq: number; delta: string }
  | { type: "think_delta"; seq: number; delta: string }
  | { type: "image"; seq: number; mime_type: string; data: string }
  | { type: "audio"; seq: number; mime_type: string; data: string }
  | { type: "video"; seq: number; mime_type: string; data: string };

// 工具调用事件
type ToolCallEvent = {
  type: "tool_call";
  seq: number;
  tool_call_id: string;
  name: string;
  input_preview: string;
};

type ToolCallPartEvent = {
  type: "tool_call_part";
  seq: number;
  tool_call_id: string;
  delta: string;  // JSON 增量
};

type ToolResultEvent = {
  type: "tool_result";
  seq: number;
  tool_call_id: string;
  result_preview: string;
  is_error: boolean;
  duration_ms: number;
};

// 状态更新事件
type StatusUpdateEvent = {
  type: "status_update";
  seq: number;
  status:
    | { type: "thinking" }
    | { type: "calling_tool"; tool_name: string }
    | { type: "compacting" }
    | { type: "loading_mcp"; server: string }
    | {
        type: "token_usage";
        input: number;
        output: number;
        total: number;
        model: string;
      };
};

// 会话通知事件
type SessionNoticeEvent = {
  type: "session_notice";
  seq: number;
  level: "info" | "warning" | "error";
  message: string;
  detail?: string;
};

// Compaction 事件
type CompactionBeginEvent = {
  type: "compaction_begin";
  seq: number;
  original_size: number;
  strategy: string;
};

type CompactionEndEvent = {
  type: "compaction_end";
  seq: number;
  new_size: number;
  summary: string;
  saved_tokens: number;
};

// MCP 加载事件
type MCPLoadingBeginEvent = {
  type: "mcp_loading_begin";
  seq: number;
  server_name: string;
  tools_count: number;
};

type MCPLoadingEndEvent = {
  type: "mcp_loading_end";
  seq: number;
  server_name: string;
  status: "success" | "error";
  error?: string;
};

// 审批事件
type ApprovalRequestEvent = {
  type: "approval_request";
  seq: number;
  request_id: string;
  checkpoint_id: number;
  tool_name: string;
  tool_input: Record<string, unknown>;
  timeout_seconds: number;
};

type ApprovalRequestResolvedEvent = {
  type: "approval_request_resolved";
  seq: number;
  request_id: string;
  approved: boolean;
  feedback?: string;
};

// 提问事件
type QuestionRequestEvent = {
  type: "question_request";
  seq: number;
  request_id: string;
  question: string;
  options?: string[];
};

// 子代理事件（支持嵌套）
type SubagentEventWire = {
  type: "subagent_event";
  seq: number;
  subagent_id: string;
  parent_request_id: string;
  nested_event: WireEvent;  // 递归嵌套
};

// 联合类型
type WireEvent =
  | TurnBeginEvent
  | TurnEndEvent
  | StepBeginEvent
  | StepInterruptedEvent
  | ContentPartEvent
  | ToolCallEvent
  | ToolCallPartEvent
  | ToolResultEvent
  | StatusUpdateEvent
  | SessionNoticeEvent
  | CompactionBeginEvent
  | CompactionEndEvent
  | MCPLoadingBeginEvent
  | MCPLoadingEndEvent
  | ApprovalRequestEvent
  | ApprovalRequestResolvedEvent
  | QuestionRequestEvent
  | SubagentEventWire;
```

### 追踪状态管理

```typescript
// web/src/hooks/useWire.ts
interface TurnState {
  userInput: string;
  steps: StepState[];
  currentStep: number;
  contextUsage: number;
  isComplete: boolean;
  error?: string;
}

interface StepState {
  n: number;
  thinkingContent: string;
  textContent: string;
  toolCalls: ToolCallState[];
  isStreaming: boolean;
  status: "thinking" | "calling_tool" | "writing" | "complete";
}

interface ToolCallState {
  id: string;
  name: string;
  input: Record<string, unknown>;
  result?: string;
  isError: boolean;
  durationMs?: number;
}

// Wire 状态聚合器
class WireStateAggregator {
  private turns: Map<string, TurnState> = new Map();
  private currentTurn: string | null = null;

  processEvent(event: WireEvent): void {
    switch (event.type) {
      case "turn_begin":
        this.currentTurn = event.request_id;
        this.turns.set(event.request_id, {
          userInput: event.user_input,
          steps: [],
          currentStep: 0,
          contextUsage: event.context_size,
          isComplete: false,
        });
        break;

      case "step_begin":
        if (this.currentTurn) {
          const turn = this.turns.get(this.currentTurn)!;
          turn.steps.push({
            n: event.step_no,
            thinkingContent: "",
            textContent: "",
            toolCalls: [],
            isStreaming: true,
            status: "thinking",
          });
          turn.currentStep = event.step_no;
        }
        break;

      case "text_delta":
        if (this.currentTurn) {
          const turn = this.turns.get(this.currentTurn)!;
          const step = turn.steps[turn.currentStep - 1];
          if (step) {
            step.textContent += event.delta;
          }
        }
        break;

      case "tool_call":
        if (this.currentTurn) {
          const turn = this.turns.get(this.currentTurn)!;
          const step = turn.steps[turn.currentStep - 1];
          if (step) {
            step.toolCalls.push({
              id: event.tool_call_id,
              name: event.name,
              input: JSON.parse(event.input_preview || "{}"),
              isError: false,
            });
            step.status = "calling_tool";
          }
        }
        break;

      case "tool_result":
        if (this.currentTurn) {
          const turn = this.turns.get(this.currentTurn)!;
          const step = turn.steps[turn.currentStep - 1];
          if (step) {
            const toolCall = step.toolCalls.find(
              (t) => t.id === event.tool_call_id
            );
            if (toolCall) {
              toolCall.result = event.result_preview;
              toolCall.isError = event.is_error;
              toolCall.durationMs = event.duration_ms;
            }
          }
        }
        break;

      case "turn_end":
        if (this.currentTurn) {
          const turn = this.turns.get(this.currentTurn)!;
          turn.isComplete = true;
        }
        break;
    }
  }

  getTurnState(requestId: string): TurnState | undefined {
    return this.turns.get(requestId);
  }

  getAllTurns(): TurnState[] {
    return Array.from(this.turns.values());
  }
}
```

### Wire 日志与重放

```python
# tests_e2e/wire_helpers.py
class WireProcess:
    """E2E test helper for Wire protocol interaction."""

    def __init__(self, args: List[str]):
        self.process = subprocess.Popen(
            args,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            stdin=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        self.line_reader = LineReader(self.process.stdout)
        self.messages: List[Dict[str, Any]] = []

    async def start(self) -> None:
        """Start reading Wire events."""
        async for line in self.line_reader:
            if line.startswith("wire: "):
                event = json.loads(line[6:])
                self.messages.append(event)

    def wait_for_event(
        self,
        event_type: str,
        timeout: float = 30.0,
        predicate: Optional[Callable[[Dict], bool]] = None,
    ) -> Dict[str, Any]:
        """Wait for specific Wire event."""
        start = time.time()
        while time.time() - start < timeout:
            for msg in self.messages:
                if msg.get("type") == event_type:
                    if predicate is None or predicate(msg):
                        return msg
            time.sleep(0.1)
        raise TimeoutError(f"Event {event_type} not received within {timeout}s")

    def normalize_response(self, messages: List[Dict]) -> List[Dict]:
        """Normalize messages for comparison (idempotent)."""
        normalized = []
        for msg in messages:
            # 移除非确定性字段
            clean = {
                k: v
                for k, v in msg.items()
                if k not in ("seq", "timestamp", "request_id")
            }
            normalized.append(clean)
        return normalized

    def summarize_messages(self, messages: List[Dict]) -> str:
        """Create human-readable summary of message sequence."""
        summary = []
        for msg in messages:
            msg_type = msg.get("type", "unknown")
            if msg_type == "turn_begin":
                summary.append(f"▶ Turn: {msg.get('user_input', '')[:50]}...")
            elif msg_type == "tool_call":
                summary.append(f"  🔧 Tool: {msg.get('name')}({msg.get('input_preview')})")
            elif msg_type == "tool_result":
                status = "✓" if not msg.get("is_error") else "✗"
                summary.append(f"  {status} Result: {msg.get('result_preview', '')[:50]}...")
            elif msg_type == "turn_end":
                summary.append(f"◀ End: {msg.get('finish_reason')}")
        return "\n".join(summary)


# 脚本化测试配置（用于重放）
def write_scripted_config(
    path: Path,
    responses: List[Dict[str, Any]],
) -> None:
    """Write scripted responses for deterministic replay."""
    config = {
        "mode": "scripted",
        "responses": responses,
    }
    with open(path, "w") as f:
        json.dump(config, f, indent=2)


# 示例：预定义响应脚本
SCRIPTED_RESPONSES = [
    {
        "trigger": {"type": "llm_request", "contains": "hello"},
        "response": {
            "type": "text_delta",
            "delta": "Hello! How can I help you today?",
        },
    },
    {
        "trigger": {"type": "tool_call", "name": "read_file"},
        "response": {
            "type": "tool_result",
            "result_preview": "File content here...",
            "is_error": False,
        },
    },
]
```

### 事件溯源与重放

```python
# src/kimi_cli/wire/file.py
class WireFile:
    """File backend for Wire events (persistent logging)."""

    PROTOCOL_VERSION = "1.0"

    def __init__(self, path: Path):
        self.path = path
        self._lock = asyncio.Lock()

    async def append_message(
        self,
        msg: WireMessage,
        timestamp: float | None = None,
    ) -> None:
        """Append message to Wire file."""
        record = WireMessageRecord.from_wire_message(
            msg,
            timestamp=time.time() if timestamp is None else timestamp,
        )
        await self.append_record(record)

    async def append_record(self, record: WireMessageRecord) -> None:
        """Append record with atomic write."""
        async with self._lock:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            needs_header = not self.path.exists() or self.path.stat().st_size == 0

            async with aiofiles.open(self.path, mode="a", encoding="utf-8") as f:
                if needs_header:
                    metadata = WireFileMetadata(
                        protocol_version=self.PROTOCOL_VERSION,
                        created_at=time.time(),
                    )
                    await f.write(_dump_line(metadata))
                await f.write(_dump_line(record))

    async def read_all(self) -> List[WireMessageRecord]:
        """Read all records from Wire file."""
        if not self.path.exists():
            return []

        records = []
        async with aiofiles.open(self.path, "r", encoding="utf-8") as f:
            async for line in f:
                line = line.strip()
                if not line:
                    continue
                data = json.loads(line)
                # 跳过 metadata 行
                if data.get("type") == "metadata":
                    continue
                records.append(WireMessageRecord(**data))
        return records

    async def replay(
        self,
        callback: Callable[[WireMessageRecord], Awaitable[None]],
        start_seq: int = 0,
    ) -> None:
        """Replay events from file."""
        records = await self.read_all()
        for record in records:
            if record.seq >= start_seq:
                await callback(record)


# 使用示例：重放会话
async def replay_session(wire_file: Path, start_from: int = 0) -> None:
    """Replay a session from Wire file."""
    file = WireFile(wire_file)

    async def handle_event(record: WireMessageRecord) -> None:
        event = record.to_event()
        print(f"[{record.seq}] {event.type}: {event}")

        # 重建状态
        if event.type == "turn_begin":
            print(f"Starting turn: {event.user_input}")
        elif event.type == "tool_call":
            print(f"Tool called: {event.name}")
        elif event.type == "turn_end":
            print(f"Turn finished: {event.finish_reason}")

    await file.replay(handle_event, start_seq=start_from)
```

---

## openclaw 追踪与日志

### 日志系统架构

```typescript
// src/logging/logger.ts
import { Logger as TsLogger } from "tslog";

export interface Logger {
  debug: (...args: unknown[]) => void;
  info: (...args: unknown[]) => void;
  warn: (...args: unknown[]) => void;
  error: (...args: unknown[]) => void;
  fatal: (...args: unknown[]) => void;
}

// 子系统日志器
export function createSubsystemLogger(subsystem: string): Logger {
  const logger = new TsLogger({
    name: subsystem,
    prettyLogTemplate: "{{yyyy}}.{{mm}}.{{dd}} {{hh}}:{{MM}}:{{ss}} {{logLevelName}} [{{name}}] ",
    prettyLogStyles: {
      name: {
        color: getSubsystemColor(subsystem),
      },
    },
  });

  // 添加文件处理器
  const logFile = getLogFilePath(subsystem);
  logger.attachTransport((logObj) => {
    appendToLogFile(logFile, JSON.stringify(logObj));
  });

  return logger;
}

// 子系统颜色分配（基于哈希）
function getSubsystemColor(subsystem: string): string {
  const colors = ["blue", "green", "yellow", "magenta", "cyan"];
  const hash = subsystem.split("").reduce((acc, char) => {
    return acc + char.charCodeAt(0);
  }, 0);
  return colors[hash % colors.length];
}


// src/logging/subsystem.ts
export const Subsystems = {
  AGENT: "agent",
  CHANNEL: "channel",
  MEMORY: "memory",
  MCP: "mcp",
  TOOLS: "tools",
  LLM: "llm",
  BROWSER: "browser",
  SCHEDULER: "scheduler",
} as const;

export type Subsystem = (typeof Subsystems)[keyof typeof Subsystems];

// 日志轮转
class LogRotator {
  private maxSize: number = 500 * 1024 * 1024; // 500MB
  private maxAge: number = 24 * 60 * 60 * 1000; // 24h

  async rotate(logFile: Path): Promise<void> {
    const stats = await fs.stat(logFile).catch(() => null);
    if (!stats) return;

    // 按大小轮转
    if (stats.size > this.maxSize) {
      const rotatedName = `${logFile.name}.${Date.now()}`;
      await fs.rename(logFile, logFile.parent / rotatedName);
    }

    // 清理旧日志
    const logDir = logFile.parent;
    const files = await fs.readdir(logDir);
    const now = Date.now();

    for (const file of files) {
      const filePath = logDir / file;
      const fileStats = await fs.stat(filePath);
      if (now - fileStats.mtime.getTime() > this.maxAge) {
        await fs.unlink(filePath);
      }
    }
  }
}
```

### Agent 追踪基础

```typescript
// src/agents/trace-base.ts
export type AgentTraceBase = {
  // 标识
  runId?: string;           // 单次运行 ID
  sessionId?: string;       // 会话 ID
  sessionKey?: string;      // 会话密钥

  // 模型信息
  provider?: string;        // 提供商: openai, anthropic, etc.
  modelId?: string;         // 模型 ID
  modelApi?: string | null; // API 端点

  // 环境
  workspaceDir?: string;    // 工作目录
};

// 生成追踪 ID
export function generateRunId(): string {
  return `run_${Date.now()}_${randomBytes(4).toString("hex")}`;
}

// 追踪上下文传播
export function withTrace<T>(
  base: AgentTraceBase,
  fn: (trace: AgentTraceBase) => Promise<T>,
): Promise<T> {
  const trace = {
    ...base,
    runId: base.runId || generateRunId(),
  };

  // 设置异步上下文
  return asyncLocalStorage.run(trace, () => fn(trace));
}

// 获取当前追踪上下文
export function getCurrentTrace(): AgentTraceBase | undefined {
  return asyncLocalStorage.getStore();
}
```

### 缓存追踪

```typescript
// src/agents/cache-trace.ts
export type CacheTraceEvent = {
  seq: number;
  timestamp: number;
  stage:
    | "session:loaded"
    | "session:sanitized"
    | "session:limited"
    | "prompt:before"
    | "prompt:images"
    | "stream:context"
    | "session:after";
  payload: unknown;
  messageFingerprints?: string[];  // SHA256 指纹
  messagesDigest?: string;         // 整体摘要
};

export class CacheTracer {
  private events: CacheTraceEvent[] = [];
  private seq = 0;
  private outputPath?: Path;

  constructor(options?: { outputPath?: Path }) {
    this.outputPath = options?.outputPath;
  }

  trace(
    stage: CacheTraceEvent["stage"],
    payload: unknown,
    messages?: Message[],
  ): void {
    const event: CacheTraceEvent = {
      seq: this.seq++,
      timestamp: Date.now(),
      stage,
      payload: this.sanitizePayload(payload),
    };

    // 计算消息指纹
    if (messages) {
      event.messageFingerprints = messages.map((m) =>
        createHash("sha256").update(JSON.stringify(m)).digest("hex"),
      );
      event.messagesDigest = createHash("sha256")
        .update(event.messageFingerprints.join(""))
        .digest("hex");
    }

    this.events.push(event);
  }

  private sanitizePayload(payload: unknown): unknown {
    // 移除敏感信息
    if (typeof payload === "object" && payload !== null) {
      const cleaned = { ...payload };
      delete cleaned.apiKey;
      delete cleaned.password;
      delete cleaned.token;
      return cleaned;
    }
    return payload;
  }

  async flush(): Promise<void> {
    if (!this.outputPath) return;

    // JSONL 格式写入
    const lines = this.events.map((e) => JSON.stringify(e)).join("\n");
    await fs.writeFile(this.outputPath, lines + "\n", { flag: "a" });
    this.events = [];
  }

  // 分析追踪结果
  analyze(): {
    totalStages: number;
    stageCounts: Record<string, number>;
    duration: number;
  } {
    return {
      totalStages: this.events.length,
      stageCounts: this.events.reduce((acc, e) => {
        acc[e.stage] = (acc[e.stage] || 0) + 1;
        return acc;
      }, {} as Record<string, number>),
      duration:
        this.events.length > 1
          ? this.events[this.events.length - 1].timestamp -
            this.events[0].timestamp
          : 0,
    };
  }
}
```

### 浏览器追踪

```typescript
// src/browser/pw-tools-core.trace.ts
import { test as baseTest } from "@playwright/test";

export const test = baseTest.extend<{
  trace: {
    start: (name: string) => Promise<void>;
    stop: () => Promise<void>;
    screenshot: (name: string) => Promise<void>;
  };
}>({
  trace: async ({ page, context }, use, testInfo) => {
    const traceDir = testInfo.outputPath("traces");

    await use({
      start: async (name: string) => {
        await context.tracing.start({
          snapshots: true,
          screenshots: true,
          sources: true,
        });
      },
      stop: async () => {
        await context.tracing.stop({
          path: `${traceDir}/trace.zip`,
        });
      },
      screenshot: async (name: string) => {
        await page.screenshot({
          path: `${traceDir}/${name}.png`,
          fullPage: true,
        });
      },
    });
  },
});
```

### Cron 运行日志

```typescript
// src/cron/run-log.ts
export type CronRunLogEntry = {
  id: string;
  timestamp: number;
  taskName: string;
  status: "success" | "error" | "timeout";
  durationMs: number;
  output?: string;
  error?: string;
  deliveryStatus?: "pending" | "delivered" | "failed";
};

export class CronRunLog {
  private logFile: Path;
  private maxSize: number = 2 * 1024 * 1024; // 2MB
  private maxEntries: number = 2000;

  constructor(logFile: Path) {
    this.logFile = logFile;
  }

  async append(entry: CronRunLogEntry): Promise<void> {
    // 原子写入
    const line = JSON.stringify(entry) + "\n";
    await fs.writeFile(this.logFile, line, { flag: "a" });

    // 检查大小并修剪
    await this.trimIfNeeded();
  }

  async query(options?: {
    status?: CronRunLogEntry["status"];
    taskName?: string;
    since?: number;
    until?: number;
    limit?: number;
    offset?: number;
  }): Promise<CronRunLogEntry[]> {
    const entries: CronRunLogEntry[] = [];

    const fileStream = createReadStream(this.logFile);
    const rl = createInterface({
      input: fileStream,
      crlfDelay: Infinity,
    });

    for await (const line of rl) {
      if (!line.trim()) continue;
      const entry: CronRunLogEntry = JSON.parse(line);

      // 应用过滤
      if (options?.status && entry.status !== options.status) continue;
      if (options?.taskName && entry.taskName !== options.taskName) continue;
      if (options?.since && entry.timestamp < options.since) continue;
      if (options?.until && entry.timestamp > options.until) continue;

      entries.push(entry);
    }

    // 排序和分页
    entries.sort((a, b) => b.timestamp - a.timestamp);
    const offset = options?.offset || 0;
    const limit = options?.limit || entries.length;
    return entries.slice(offset, offset + limit);
  }

  private async trimIfNeeded(): Promise<void> {
    const stats = await fs.stat(this.logFile).catch(() => null);
    if (!stats || stats.size < this.maxSize) return;

    // 读取所有条目
    const entries = await this.query({ limit: this.maxEntries });

    // 保留最近 N 条
    const toKeep = entries.slice(0, this.maxEntries);
    const lines = toKeep.map((e) => JSON.stringify(e)).join("\n");

    // 原子替换
    const tempFile = this.logFile.withSuffix(".tmp");
    await fs.writeFile(tempFile, lines + "\n");
    await fs.rename(tempFile, this.logFile);
  }
}
```

---

## opencode 会话与快照

### 日志系统

```typescript
// packages/opencode/src/util/log.ts
export interface LogOptions {
  service?: string;
  logDir?: string;
}

export class Log {
  private service: string;
  private logFile?: string;
  private startTime: number;

  static create(options: LogOptions = {}): Log {
    return new Log(options);
  }

  constructor(options: LogOptions = {}) {
    this.service = options.service || "opencode";
    this.startTime = Date.now();

    if (options.logDir) {
      // 按日期命名日志文件
      const date = new Date().toISOString().split("T")[0];
      this.logFile = path.join(options.logDir, `${date}.log`);

      // 清理旧日志
      this.cleanupOldLogs(options.logDir);
    }
  }

  private cleanupOldLogs(logDir: string): void {
    const files = fs.readdirSync(logDir);
    const logFiles = files
      .filter((f) => f.endsWith(".log"))
      .map((f) => ({
        name: f,
        path: path.join(logDir, f),
        mtime: fs.statSync(path.join(logDir, f)).mtime,
      }))
      .sort((a, b) => b.mtime.getTime() - a.mtime.getTime());

    // 保留最近 10 个日志文件
    for (const file of logFiles.slice(10)) {
      fs.unlinkSync(file.path);
    }
  }

  private formatMessage(
    level: string,
    message: string,
    meta?: Record<string, unknown>,
  ): string {
    const now = new Date();
    const elapsed = Date.now() - this.startTime;

    const parts = [
      now.toISOString(),
      `+${elapsed}ms`,
      `[${this.service}]`,
      level,
      message,
    ];

    if (meta) {
      parts.push(JSON.stringify(meta));
    }

    return parts.join(" ");
  }

  debug(message: string, meta?: Record<string, unknown>): void {
    const formatted = this.formatMessage("DEBUG", message, meta);
    console.log(formatted);
    this.writeToFile(formatted);
  }

  info(message: string, meta?: Record<string, unknown>): void {
    const formatted = this.formatMessage("INFO", message, meta);
    console.log(formatted);
    this.writeToFile(formatted);
  }

  error(message: string, error?: Error): void {
    const meta: Record<string, unknown> = {};
    if (error) {
      meta.error = error.message;
      meta.stack = error.stack;

      // 支持 Error cause 链
      let cause = error.cause;
      let depth = 0;
      while (cause instanceof Error && depth < 5) {
        meta[`cause_${depth}`] = cause.message;
        cause = cause.cause;
        depth++;
      }
    }

    const formatted = this.formatMessage("ERROR", message, meta);
    console.error(formatted);
    this.writeToFile(formatted);
  }

  private writeToFile(line: string): void {
    if (this.logFile) {
      fs.appendFileSync(this.logFile, line + "\n");
    }
  }
}
```

### 会话事件总线

```typescript
// packages/opencode/src/session/index.ts
// 事件总线定义
export const SessionEvents = {
  Created: BusEvent.define("session.created", {
    session: SessionV2.Info,
  }),

  Updated: BusEvent.define("session.updated", {
    session: SessionV2.Info,
    changes: z.array(z.tuple([z.string(), z.unknown(), z.unknown()])),
  }),

  Deleted: BusEvent.define("session.deleted", {
    sessionID: SessionID.zod,
  }),

  DiffCreated: BusEvent.define("session.diff_created", {
    sessionID: SessionID.zod,
    diff: SessionV2.Diff,
  }),

  Compacted: BusEvent.define("session.compacted", {
    sessionID: SessionID.zod,
    summary: z.string(),
  }),
};

// 消息事件
export const MessageEvents = {
  Created: BusEvent.define("message.created", {
    message: MessageV2.Info,
  }),

  Updated: BusEvent.define("message.updated", {
    message: MessageV2.Info,
  }),

  Deleted: BusEvent.define("message.deleted", {
    messageID: MessageID.zod,
    sessionID: SessionID.zod,
  }),

  PartCreated: BusEvent.define("message.part_created", {
    part: PartV2.Info,
  }),

  PartUpdated: BusEvent.define("message.part_updated", {
    part: PartV2.Info,
  }),
};

// 订阅示例
Bus.subscribe(SessionEvents.Created, async ({ session }) => {
  console.log(`Session created: ${session.id}`);
  await notifyUI({ type: "session_created", session });
});

Bus.subscribe(MessageEvents.PartUpdated, async ({ part }) => {
  // 流式更新 UI
  await streamToUI({ type: "part_delta", part });
});
```

### 会话恢复机制

```typescript
// packages/opencode/src/session/revert.ts
export const RevertInput = z.object({
  sessionID: SessionID.zod,
  messageID: MessageID.zod,
  partID: PartID.zod.optional(),
});

export type RevertInput = z.infer<typeof RevertInput>;

export async function revert(input: RevertInput): Promise<SessionV2.Info> {
  const { sessionID, messageID, partID } = input;

  // 1. 获取会话当前状态
  const session = await Session.get(sessionID);

  // 2. 找到恢复点
  const targetMessage = await Message.get(messageID);
  if (!targetMessage) {
    throw new Error(`Message ${messageID} not found`);
  }

  // 3. 计算需要删除的消息
  const allMessages = await Message.list({ session_id: sessionID });
  const messagesToDelete = allMessages.filter(
    (m) => m.time.created > targetMessage.time.created,
  );

  // 4. 计算文件差异（用于恢复代码状态）
  const diff = await calculateDiff(sessionID, messageID);

  // 5. 应用恢复
  await Database.use((db) => {
    // 删除消息
    for (const msg of messagesToDelete) {
      db.delete(MessageTable).where(eq(MessageTable.id, msg.id)).run();
    }

    // 删除关联的 Parts
    if (partID) {
      db.delete(PartTable)
        .where(
          and(
            eq(PartTable.message_id, messageID),
            gt(PartTable.time_created, partID),
          ),
        )
        .run();
    }

    // 更新会话状态
    db.update(SessionTable)
      .set({
        revert: { messageID, partID },
        time_updated: Date.now(),
      })
      .where(eq(SessionTable.id, sessionID))
      .run();
  });

  // 6. 发布事件
  Bus.publish(SessionEvents.Updated, {
    session: await Session.get(sessionID),
    changes: [["revert", null, { messageID, partID }]],
  });

  return Session.get(sessionID);
}

// 计算代码差异
async function calculateDiff(
  sessionID: SessionID,
  messageID: MessageID,
): Promise<SessionV2.Diff> {
  const currentSnapshot = await Snapshot.track();
  const targetSnapshot = await Snapshot.at(messageID);

  return {
    additions: currentSnapshot.additions - targetSnapshot.additions,
    deletions: currentSnapshot.deletions - targetSnapshot.deletions,
    files: currentSnapshot.files.filter(
      (f) => !targetSnapshot.files.includes(f),
    ),
  };
}
```

### Git 快照系统

```typescript
// packages/opencode/src/snapshot/index.ts
export namespace Snapshot {
  export type Info = {
    id: string;
    sessionID: SessionID;
    messageID?: MessageID;
    timestamp: number;
    additions: number;
    deletions: number;
    files: string[];
    diff?: FileDiff[];
  };

  export type FileDiff = {
    path: string;
    status: "added" | "modified" | "deleted";
    additions: number;
    deletions: number;
    patch?: string;
  };

  // 创建快照
  export async function track(
    sessionID?: SessionID,
  ): Promise<Info> {
    const git = await getGit();

    // 获取当前状态
    const status = await git.status();
    const diff = await git.diffSummary();

    const snapshot: Info = {
      id: generateSnapshotId(),
      sessionID: sessionID || (await getCurrentSession()),
      timestamp: Date.now(),
      additions: diff.insertions,
      deletions: diff.deletions,
      files: status.files.map((f) => f.path),
    };

    // 保存到存储
    await storage.set(`snapshot:${snapshot.id}`, snapshot);

    return snapshot;
  }

  // 恢复到快照
  export async function restore(snapshotId: string): Promise<void> {
    const snapshot = await storage.get<Info>(`snapshot:${snapshotId}`);
    if (!snapshot) {
      throw new Error(`Snapshot ${snapshotId} not found`);
    }

    const git = await getGit();

    // 使用 git stash 保存当前更改
    await git.stash(["-u"]);

    // 恢复到快照对应的提交
    if (snapshot.messageID) {
      // 找到对应的 git commit
      const commit = await findCommitByMessage(snapshot.messageID);
      if (commit) {
        await git.checkout(commit);
      }
    }

    // 应用 stash
    await git.stash(["pop"]);
  }

  // 获取差异
  export async function diff(
    fromSnapshotId: string,
    toSnapshotId: string,
  ): Promise<FileDiff[]> {
    const git = await getGit();

    const fromCommit = await findCommitBySnapshot(fromSnapshotId);
    const toCommit = await findCommitBySnapshot(toSnapshotId);

    const diff = await git.diff([`${fromCommit}..${toCommit}`]);

    return parseDiff(diff);
  }

  // 定时清理（7天）
  export async function gc(): Promise<void> {
    const sevenDaysAgo = Date.now() - 7 * 24 * 60 * 60 * 1000;

    const allSnapshots = await storage.list("snapshot:");
    for (const key of allSnapshots) {
      const snapshot = await storage.get<Info>(key);
      if (snapshot && snapshot.timestamp < sevenDaysAgo) {
        await storage.delete(key);
      }
    }
  }
}
```

### Token 使用追踪

```typescript
// packages/opencode/src/session/index.ts
export async function getUsage(
  sessionID: SessionID,
): Promise<{
  input: number;
  output: number;
  cacheReads: number;
  cacheWrites: number;
  total: number;
  costUSD: Decimal;
}> {
  const messages = await Message.list({ session_id: sessionID });

  let input = 0;
  let output = 0;
  let cacheReads = 0;
  let cacheWrites = 0;

  for (const message of messages) {
    if (message.tokens) {
      input += message.tokens.input || 0;
      output += message.tokens.output || 0;

      // 提供商特定的缓存统计
      if (message.tokens.cacheReads) {
        cacheReads += message.tokens.cacheReads;
      }
      if (message.tokens.cacheWrites) {
        cacheWrites += message.tokens.cacheWrites;
      }
    }
  }

  // 计算成本
  const costUSD = calculateCost({
    provider: await getProvider(sessionID),
    model: await getModel(sessionID),
    input,
    output,
    cacheReads,
    cacheWrites,
  });

  return {
    input,
    output,
    cacheReads,
    cacheWrites,
    total: input + output,
    costUSD,
  };
}

// 成本计算
function calculateCost(params: {
  provider: string;
  model: string;
  input: number;
  output: number;
  cacheReads: number;
  cacheWrites: number;
}): Decimal {
  const pricing = getPricing(params.provider, params.model);

  const inputCost = new Decimal(params.input)
    .times(pricing.inputPer1K)
    .div(1000);
  const outputCost = new Decimal(params.output)
    .times(pricing.outputPer1K)
    .div(1000);

  // 缓存通常更便宜
  const cacheReadCost = new Decimal(params.cacheReads)
    .times(pricing.cacheReadPer1K || pricing.inputPer1K * 0.5)
    .div(1000);
  const cacheWriteCost = new Decimal(params.cacheWrites)
    .times(pricing.cacheWritePer1K || pricing.inputPer1K)
    .div(1000);

  return inputCost.plus(outputCost).plus(cacheReadCost).plus(cacheWriteCost);
}
```

---

## 架构对比与推荐

### 四项目对比

| 特性 | CoPaw | kimi-cli | openclaw | opencode |
|------|-------|----------|----------|----------|
| **日志系统** | Python logging + ColorFormatter | 无独立系统 | tslog + 子系统日志器 | 自定义 Logger |
| **结构化日志** | ❌ | ✅ Wire 事件 | ✅ JSONL | ❌ |
| **日志轮转** | RotatingFileHandler | ❌ | 日期 + 大小限制 | 保留10个文件 |
| **链路追踪** | SessionBase | Wire 事件流 | AgentTraceBase + CacheTrace | BusEvent 总线 |
| **Trace ID** | ❌ | ❌（session_id） | runId + sessionId | SessionID + MessageID + PartID |
| **Span 层级** | ❌ | Turn > Step > Tool | ❌ | Message > Part |
| **重放机制** | JSON 会话文件 | 脚本化测试 | 故障观察 | Git 快照 + 会话恢复 |
| **事件溯源** | ❌ | ✅ Wire 日志 | ❌ | ✅ Bus 事件 |
| **指标收集** | TokenUsageManager | StatusUpdateEvent | CronRunLog | getUsage 成本计算 |
| **健康检查** | Heartbeat 任务 | ❌ | ❌ | ❌ |
| **持久化** | JSON 文件 | JSONL | JSONL | SQLite + Git |
| **调试工具** | ❌ | E2E Wire 测试 | Playwright 追踪 | CLI snapshot 命令 |

### 推荐混合架构

```
┌─────────────────────────────────────────────────────────────┐
│                    Observability Stack                      │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Logging (openclaw tslog + CoPaw ColorFormatter)    │   │
│  │  - 子系统隔离    - 彩色输出    - 多目标输出         │   │
│  │  - 日志轮转      - 大小限制    - 自动清理           │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Tracing (kimi-cli Wire + opencode BusEvent)        │   │
│  │  - Wire 事件流   - Bus 总线      - 上下文传播       │   │
│  │  - Trace ID      - Span 层级     - 嵌套追踪         │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Metrics (CoPaw TokenUsage + opencode 成本计算)      │   │
│  │  - Token 统计    - 成本追踪    - 性能指标           │   │
│  │  - 多维度聚合    - 历史查询    - 导出报表           │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Replay (kimi-cli Wire + opencode Git 快照)          │   │
│  │  - Wire 重放     - 会话恢复    - 代码快照           │   │
│  │  - 时间旅行      - 检查点      - 差异对比           │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Health (CoPaw Heartbeat)                           │   │
│  │  - 定时心跳      - 指标上报    - 告警通知           │   │
│  │  - 活跃时段      - 超时保护    - 状态报告           │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 关键设计建议

1. **日志系统**
   - 结构化 JSON 日志（便于分析）
   - 子系统命名空间隔离
   - 自动轮转和清理
   - 多级别控制（DEBUG/INFO/WARN/ERROR）

2. **链路追踪**
   - Trace ID 全链路传播
   - Span 层级：Session > Turn > Step > Tool
   - 事件总线解耦（发布-订阅）
   - 支持嵌套子 Agent 追踪

3. **重放机制**
   - Wire 事件日志（I/O 重放）
   - Git 代码快照（状态恢复）
   - 检查点保存（时间旅行）
   - 脚本化测试（确定性验证）

4. **指标收集**
   - Token 使用（按模型/提供商聚合）
   - 成本计算（精确到小数点后6位）
   - 性能指标（延迟/成功率）
   - 健康检查（心跳/资源监控）

---

## 附录：关键代码文件

| 项目 | 关键文件 | 说明 |
|------|----------|------|
| **CoPaw** | `utils/logging.py` | 彩色日志 |
| **CoPaw** | `token_usage/manager.py` | Token 使用统计 |
| **CoPaw** | `app/crons/heartbeat.py` | 健康检查 |
| **CoPaw** | `agents/session.py` | 会话追踪 |
| **kimi-cli** | `web/src/hooks/wireTypes.ts` | Wire 事件类型 |
| **kimi-cli** | `web/src/hooks/useWire.ts` | Wire 状态聚合 |
| **kimi-cli** | `tests_e2e/wire_helpers.py` | E2E 测试辅助 |
| **kimi-cli** | `wire/file.py` | Wire 日志持久化 |
| **openclaw** | `logging/logger.ts` | tslog 封装 |
| **openclaw** | `agents/trace-base.ts` | 追踪基础 |
| **openclaw** | `agents/cache-trace.ts` | 缓存追踪 |
| **openclaw** | `cron/run-log.ts` | Cron 运行日志 |
| **opencode** | `util/log.ts` | 自定义日志 |
| **opencode** | `session/index.ts` | 会话事件总线 |
| **opencode** | `session/revert.ts` | 会话恢复 |
| **opencode** | `snapshot/index.ts` | Git 快照 |

---

*报告生成时间: 2025-03-13*
*分析项目: CoPaw, kimi-cli, openclaw, opencode*
