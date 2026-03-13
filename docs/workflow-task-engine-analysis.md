# Workflow/Task Engine 架构分析

## 目录
1. [核心概念](#核心概念)
2. [CoPaw ReAct + Cron 调度](#copaw-react--cron-调度)
3. [kimi-cli Step Loop + Flow DSL](#kimi-cli-step-loop--flow-dsl)
4. [opencode 流式处理器 + Scheduler](#opencode-流式处理器--scheduler)
5. [openclaw Skill 工具库](#openclaw-skill-工具库)
6. [架构对比与推荐](#架构对比与推荐)

---

## 核心概念

### Workflow Engine 核心组件

```
┌─────────────────────────────────────────────────────────────┐
│                    Workflow Definition                      │
│  ┌─────────────────────────────────────────────────────────┐│
│  │  - 声明方式: Code / Config / DSL                        ││
│  │  - 节点类型: LLM / Tool / Condition / Loop / Parallel   ││
│  │  - 数据流: 输入/输出映射                                ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────┬───────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      Task Scheduler                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │   Queue     │  │  Executor   │  │   State Machine     │ │
│  │ (Priority)  │  │(Concurrency)│  │ (Pending/Running/   │ │
│  │             │  │             │  │  Completed/Failed)  │ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘ │
└─────────────────────────────┬───────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Error Handling                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │    Retry    │  │  Circuit    │  │   Compensation      │ │
│  │ (Backoff)   │  │   Breaker   │  │    (Rollback)       │ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Task 状态机

```
                    ┌─────────────┐
         ┌─────────▶│   Pending   │◀────────┐
         │          │  (等待调度)  │         │
         │          └──────┬──────┘         │
         │                 │ submit         │
         │          ┌──────▼──────┐         │
         │    retry │   Running   │         │
         │◀─────────│  (执行中)   │─────────┘
         │          └──────┬──────┘  complete
         │                 │
    ┌────┴────┐      ┌─────┴─────┐
    │  Failed │◀─────│Completed  │
    │ (可重试) │ error │ (成功)    │
    └────┬────┘      └───────────┘
         │ max_retry
         ▼
    ┌──────────┐
    │  Dead    │
    │  Letter  │
    └──────────┘
```

---

## CoPaw ReAct + Cron 调度

### 整体架构

CoPaw 采用 **ReAct Agent 循环** 作为核心执行模型，配合 **APScheduler** 实现定时任务调度。

```
┌─────────────────────────────────────────────────────────────┐
│                    CoPaw Agent 架构                         │
│  ┌─────────────────┐      ┌──────────────────────┐        │
│  │   ReActAgent    │◀────▶│   Memory Manager     │        │
│  │                 │      │   (InMemory + ReMe)  │        │
│  │  - _reasoning() │      └──────────────────────┘        │
│  │  - _acting()    │                                      │
│  │  - _react_loop()│      ┌──────────────────────┐        │
│  └─────────────────┘      │   ToolGuardMixin     │        │
│           │               │   (权限拦截)          │        │
│           │               └──────────────────────┘        │
│           ▼                                                │
│  ┌─────────────────┐      ┌──────────────────────┐        │
│  │   CronManager   │      │   Skill Registry     │        │
│  │  (APScheduler)  │      │   (动态加载)          │        │
│  └─────────────────┘      └──────────────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

### ReAct 循环实现

```python
# src/copaw/agents/base.py
class ReActAgent(Agent, ToolGuardMixin):
    """Base ReAct Agent with reasoning-acting loop."""

    async def _react_loop(self) -> AgentResponse:
        """Main ReAct loop: reasoning -> acting -> observation."""
        while True:
            # Step 1: Reasoning (LLM call)
            reasoning_result = await self._reasoning()

            if reasoning_result.is_final:
                return reasoning_result.response

            # Step 2: Acting (Tool execution)
            for tool_call in reasoning_result.tool_calls:
                # ToolGuard 拦截检查
                guard_result = await self._check_tool_guard(tool_call)
                if guard_result.blocked:
                    observation = guard_result.message
                else:
                    observation = await self._acting(tool_call)

                # Step 3: Observation feedback
                await self.memory.add_observation(
                    tool_name=tool_call.name,
                    tool_input=tool_call.input,
                    observation=observation
                )

            # Step 4: Token check and compaction
            if await self._should_compact():
                await self._compact_memory()

    async def _reasoning(self) -> ReasoningResult:
        """Call LLM for reasoning."""
        messages = self.memory.get_messages()
        response = await self.llm.chat(messages, tools=self.tools)
        return self._parse_reasoning_response(response)

    async def _acting(self, tool_call: ToolCall) -> str:
        """Execute tool call."""
        tool = self.tool_registry.get(tool_call.name)
        result = await tool.execute(**tool_call.input)
        return str(result)
```

### Cron 任务调度

```python
# src/copaw/app/crons/manager.py
class CronManager:
    """APScheduler-based cron job manager with concurrency control."""

    def __init__(
        self,
        *,
        repo: BaseJobRepository,
        runner: Any,
        channel_manager: Any,
        max_concurrent_jobs: int = 10,
    ):
        self._scheduler = AsyncIOScheduler(timezone=timezone)
        self._executor = CronExecutor(runner=runner, channel_manager=channel_manager)
        self._sem = asyncio.Semaphore(max_concurrent_jobs)  # 全局并发控制

    async def start(self) -> None:
        """Start scheduler and load jobs."""
        jobs = await self._repo.list_jobs()
        for job in jobs:
            if job.enabled:
                self._schedule_job(job)
        self._scheduler.start()

    def _schedule_job(self, job: CronJobSpec) -> None:
        """Schedule a cron job with APScheduler."""
        trigger = self._build_trigger(job.schedule)
        self._scheduler.add_job(
            func=self._execute_job,
            trigger=trigger,
            id=job.id,
            args=(job,),
            replace_existing=True,
            max_instances=job.max_concurrency,  # 每任务并发限制
        )

    async def _execute_job(self, job: CronJobSpec) -> None:
        """Execute job with semaphore and error handling."""
        async with self._sem:  # 全局并发控制
            state = await self._repo.get_state(job.id)
            state.last_status = "running"
            state.run_count += 1
            await self._repo.save_state(state)

            try:
                await self._executor.execute(job)
                state.last_status = "success"
                state.last_success = datetime.now(timezone.utc)
            except Exception as e:
                state.last_status = "error"
                state.last_error = str(e)
                state.error_count += 1
                if job.retry and state.error_count <= job.max_retries:
                    await self._schedule_retry(job, state.error_count)
            finally:
                state.last_run = datetime.now(timezone.utc)
                await self._repo.save_state(state)

    async def _schedule_retry(self, job: CronJobSpec, attempt: int) -> None:
        """Schedule retry with exponential backoff."""
        delay = min(2 ** attempt, 300)  # 最大 5 分钟
        await asyncio.sleep(delay)
        await self._execute_job(job)
```

### Cron Job 配置

```python
# src/copaw/app/crons/models.py
class ScheduleSpec(BaseModel):
    """Cron schedule specification."""
    type: Literal["cron", "interval", "date"] = "cron"
    # Cron 表达式: "*/5 * * * *" (每5分钟)
    cron: Optional[str] = None
    # 或间隔: minutes=5
    interval: Optional[IntervalSpec] = None
    # 或具体日期
    date: Optional[datetime] = None
    timezone: str = "UTC"

class CronJobSpec(BaseModel):
    """Cron job specification."""
    id: str
    name: str
    enabled: bool = True
    schedule: ScheduleSpec
    agent: str  # 使用的 Agent 配置
    prompt: str  # 执行的 Prompt
    channels: List[str] = []  # 输出渠道
    max_concurrency: int = 1  # 最大并发数
    max_retries: int = 3  # 最大重试次数
    retry: bool = True  # 是否启用重试
    timeout: int = 300  # 超时(秒)

class CronJobState(BaseModel):
    """Cron job execution state."""
    job_id: str
    last_status: Literal["success", "error", "running", "skipped"] = "skipped"
    last_run: Optional[datetime] = None
    last_success: Optional[datetime] = None
    last_error: Optional[str] = None
    run_count: int = 0
    error_count: int = 0
    next_run: Optional[datetime] = None
```

### 任务状态持久化

```python
# src/copaw/app/crons/repository.py
class SafeJSONJobRepository(BaseJobRepository):
    """File-based job state repository with atomic writes."""

    def __init__(self, base_path: Path):
        self.base_path = base_path
        self.jobs_file = base_path / "jobs.json"
        self.states_file = base_path / "states.json"
        self._lock = asyncio.Lock()

    async def save_state(self, state: CronJobState) -> None:
        """Atomic state write using temp file + rename."""
        async with self._lock:
            states = await self._load_states()
            states[state.job_id] = state.model_dump()

            temp_file = self.states_file.with_suffix(".tmp")
            async with aiofiles.open(temp_file, "w") as f:
                await f.write(json.dumps(states, indent=2))
            temp_file.rename(self.states_file)  # Atomic rename

    async def list_jobs(self) -> List[CronJobSpec]:
        """Load all cron jobs."""
        if not self.jobs_file.exists():
            return []
        async with aiofiles.open(self.jobs_file) as f:
            content = await f.read()
            data = json.loads(content)
            return [CronJobSpec(**item) for item in data.get("jobs", [])]
```

### 并发控制策略

```python
# 三层并发控制

# 1. 全局并发: CronManager 级别
self._sem = asyncio.Semaphore(max_concurrent_jobs)

# 2. 单任务并发: APScheduler 级别
max_instances=job.max_concurrency

# 3. Agent 级别: ReActAgent 内部
async def _acting(self, tool_call: ToolCall) -> str:
    # ToolGuard 检查
    if self._tool_guard_engine.is_blocked(tool_call.name):
        raise ToolBlockedError(tool_call.name)
    # 实际执行
    return await super()._acting(tool_call)
```

---

## kimi-cli Step Loop + Flow DSL

### 整体架构

kimi-cli 采用 **Step-based Agent Loop**，支持 **Flow DSL**（基于 D2 图表的工作流定义）和 **D-Mail 时间回溯**机制。

```
┌─────────────────────────────────────────────────────────────┐
│                    kimi-cli 架构                            │
│  ┌─────────────────┐      ┌──────────────────────┐        │
│  │    KimiSoul     │◀────▶│   DenwaRenji         │        │
│  │                 │      │   (D-Mail 系统)       │        │
│  │  - _agent_loop()│      │   - send_dmail()     │        │
│  │  - _step()      │      │   - checkpoints      │        │
│  │  - _turn()      │      └──────────────────────┘        │
│  └─────────────────┘                                      │
│           │               ┌──────────────────────┐        │
│           │               │   LaborMarket        │        │
│           ▼               │   (SubAgent 市场)     │        │
│  ┌─────────────────┐      └──────────────────────┘        │
│  │    Context      │                                      │
│  │  (Wire + JSONL) │      ┌──────────────────────┐        │
│  └─────────────────┘      │   Flow Engine        │        │
│                           │   (D2 DSL)           │        │
│                           └──────────────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

### Step Loop 实现

```python
# src/kimi_cli/soul/kimisoul.py
class KimiSoul:
    """Step-based agent loop with retry and recovery."""

    async def _agent_loop(self) -> TurnOutcome:
        """
        Main agent loop with step counting and outcome handling.
        """
        step_no = 0
        while True:
            step_no += 1

            # 1. 检查步数限制
            if step_no > self._loop_control.max_steps_per_turn:
                raise MaxStepsReached(
                    f"Max steps ({self._loop_control.max_steps_per_turn}) reached"
                )

            # 2. 检查 token 限制
            if await self._should_compact():
                await self._compact_context()

            # 3. 发送 StepBegin 事件
            self._wire.send(StepBegin(n=step_no))

            # 4. 执行单步
            step_outcome = await self._step()

            # 5. 处理 Step 结果
            if step_outcome.stop_reason == "no_tool_calls":
                # 无工具调用，Turn 完成
                return TurnOutcome(
                    stop_reason="normal",
                    final_message=step_outcome.assistant_message,
                    step_count=step_no,
                )
            elif step_outcome.stop_reason == "tool_rejected":
                # 工具被拒绝，继续循环
                continue
            elif step_outcome.stop_reason == "subagent_spawned":
                # 子 Agent 启动，等待结果
                subagent_result = await self._wait_subagent()
                continue

    async def _step(self) -> StepOutcome:
        """
        Single step: LLM call -> parse tool calls -> execute.
        With retry and connection recovery.
        """
        messages = self._context.get_messages()

        # Retry wrapper with tenacity
        @tenacity.retry(
            retry=retry_if_exception(self._is_retryable_error),
            wait=wait_exponential_jitter(
                initial=0.3,  # 初始等待
                max=5,        # 最大等待
                jitter=0.5,   # 抖动
            ),
            stop=stop_after_attempt(
                self._loop_control.max_retries_per_step
            ),
            before_sleep=self._log_retry_attempt,
        )
        async def _run_with_retry() -> LLMResponse:
            return await self._llm.chat(messages, tools=self._tools)

        try:
            response = await _run_with_retry()
        except RetryError as e:
            return StepOutcome(
                stop_reason="max_retries_reached",
                assistant_message=self._create_error_message(e),
            )

        # 解析工具调用
        tool_calls = self._parse_tool_calls(response)

        if not tool_calls:
            # 无工具调用，直接返回 LLM 回复
            return StepOutcome(
                stop_reason="no_tool_calls",
                assistant_message=response.message,
            )

        # 执行工具调用
        results = []
        for tc in tool_calls:
            # 检查 D-Mail
            if dmail := self._denwa_renji.fetch_pending_dmail():
                raise BackToTheFuture(
                    checkpoint_id=dmail.checkpoint_id,
                    messages=[Message(...)],
                )

            # 执行工具
            result = await self._execute_tool_call(tc)
            results.append(result)

        return StepOutcome(
            stop_reason="tool_calls_executed",
            assistant_message=self._build_assistant_message(results),
        )

    async def _execute_tool_call(self, tc: ToolCall) -> ToolResult:
        """Execute single tool call with approval handling."""
        # 1. 检查预批准
        if self._is_pre_approved(tc.name, tc.input):
            return await self._run_tool(tc)

        # 2. 发送审批请求
        approval_req = ApprovalRequest(
            request_id=str(uuid.uuid4()),
            tool_name=tc.name,
            tool_input=tc.input,
            checkpoint_id=self._denwa_renji.current_checkpoint(),
        )
        self._wire.send(approval_req)

        # 3. 等待审批响应
        response = await self._wire.wait_for(ApprovalResponse, timeout=300)

        if response.approved:
            return await self._run_tool(tc)
        else:
            return ToolResult(
                tool_id=tc.id,
                error=f"Tool rejected: {response.feedback}",
            )

    def _is_retryable_error(self, error: Exception) -> bool:
        """Determine if error is retryable."""
        if isinstance(error, (ConnectionError, TimeoutError)):
            return True
        if isinstance(error, LLMRateLimitError):
            return True
        if isinstance(error, MCPConnectionError):
            return True
        return False
```

### D-Mail 时间回溯机制

```python
# src/kimi_cli/soul/denwa_renji.py
class DenwaRenji:
    """D-Mail system for time travel in agent execution."""

    def __init__(self):
        self._checkpoints: List[Checkpoint] = []
        self._pending_dmail: Optional[DMail] = None
        self._n_checkpoints = 0

    def checkpoint(self) -> int:
        """Create a checkpoint and return its ID."""
        cp = Checkpoint(
            id=self._n_checkpoints,
            messages=self._context.get_messages().copy(),
            timestamp=time.time(),
        )
        self._checkpoints.append(cp)
        self._n_checkpoints += 1
        return cp.id

    def send_dmail(self, dmail: DMail) -> None:
        """Send D-Mail to past checkpoint."""
        if dmail.checkpoint_id >= self._n_checkpoints:
            raise DenwaRenjiError("Checkpoint does not exist")
        if self._pending_dmail is not None:
            raise DenwaRenjiError("DMail already pending")
        self._pending_dmail = dmail

    def fetch_pending_dmail(self) -> Optional[DMail]:
        """Fetch and clear pending D-Mail."""
        dmail = self._pending_dmail
        self._pending_dmail = None
        return dmail

    def jump_to(self, checkpoint_id: int) -> List[Message]:
        """Jump to checkpoint, return messages to restore."""
        if checkpoint_id >= len(self._checkpoints):
            raise DenwaRenjiError("Checkpoint not found")
        return self._checkpoints[checkpoint_id].messages


class BackToTheFuture(Exception):
    """Exception to trigger time travel."""
    def __init__(self, checkpoint_id: int, messages: List[Message]):
        self.checkpoint_id = checkpoint_id
        self.messages = messages
        super().__init__(f"Time travel to checkpoint {checkpoint_id}")


# 在 _step() 中使用
async def _step(self) -> StepOutcome:
    try:
        # ... 执行步骤
        pass
    except BackToTheFuture as bttf:
        # 时间回溯！
        self._context.restore_messages(bttf.messages)
        return StepOutcome(
            stop_reason="time_travel",
            assistant_message=Message(...),
        )
```

### Flow DSL（D2 图表工作流）

```python
# src/kimi_cli/flow/models.py
@dataclass
class FlowNode:
    """Node in a Flow workflow."""
    id: str
    type: Literal["start", "llm", "tool", "condition", "end"]
    config: Dict[str, Any]
    next: Optional[str] = None  # 下一个节点 ID
    branches: Optional[Dict[str, str]] = None  # 条件分支

@dataclass
class FlowEdge:
    """Edge connecting nodes."""
    from_node: str
    to_node: str
    condition: Optional[str] = None  # 条件表达式

@dataclass
class Flow:
    """Flow workflow definition."""
    name: str
    nodes: Dict[str, FlowNode]
    edges: List[FlowEdge]
    variables: Dict[str, Any]  # 上下文变量

    @classmethod
    def from_d2(cls, d2_source: str) -> "Flow":
        """Parse D2 diagram to Flow."""
        # D2 example:
        # start -> llm_call: "Call LLM"
        # llm_call -> check_result: "Parse result"
        # check_result -> tool_call: if "needs_tool"
        # check_result -> end: if "complete"
        parser = D2Parser()
        ast = parser.parse(d2_source)
        return cls._build_from_ast(ast)


# Flow 执行引擎
class FlowEngine:
    """Execute Flow workflows."""

    def __init__(self, soul: KimiSoul):
        self.soul = soul
        self.node_executors = {
            "llm": self._execute_llm_node,
            "tool": self._execute_tool_node,
            "condition": self._execute_condition_node,
        }

    async def execute(self, flow: Flow, inputs: Dict[str, Any]) -> FlowResult:
        """Execute flow from start to end."""
        context = FlowContext(variables=inputs)
        current_node = flow.nodes["start"]

        while current_node.type != "end":
            # 执行当前节点
            executor = self.node_executors.get(current_node.type)
            if not executor:
                raise FlowError(f"Unknown node type: {current_node.type}")

            result = await executor(current_node, context)

            # 确定下一个节点
            if current_node.type == "condition":
                # 条件分支
                branch = result["branch"]
                next_id = current_node.branches.get(branch)
                if not next_id:
                    raise FlowError(f"Branch '{branch}' not found")
            else:
                next_id = current_node.next

            current_node = flow.nodes.get(next_id)
            if not current_node:
                raise FlowError(f"Node '{next_id}' not found")

        return FlowResult(
            output=context.variables,
            trace=context.execution_trace,
        )

    async def _execute_llm_node(
        self,
        node: FlowNode,
        context: FlowContext
    ) -> Dict[str, Any]:
        """Execute LLM call node."""
        prompt = node.config["prompt"].format(**context.variables)
        response = await self.soul.llm.chat([Message.user(prompt)])
        context.variables[node.config["output_var"]] = response.content
        return {"content": response.content}

    async def _execute_condition_node(
        self,
        node: FlowNode,
        context: FlowContext
    ) -> Dict[str, Any]:
        """Evaluate condition and return branch."""
        condition_expr = node.config["expression"]
        # 简单的表达式求值
        result = eval(condition_expr, {}, context.variables)
        branch = "true" if result else "false"
        return {"branch": branch}
```

### Labor Market（SubAgent 调度）

```python
# src/kimi_cli/soul/labor_market.py
class LaborMarket:
    """Marketplace for sub-agents."""

    def __init__(self):
        self.agents: Dict[str, AgentSpec] = {}
        self.running: Dict[str, SubAgentTask] = {}

    def register(self, spec: AgentSpec) -> None:
        """Register a sub-agent type."""
        self.agents[spec.name] = spec

    async def spawn(
        self,
        agent_name: str,
        task: str,
        context: Dict[str, Any]
    ) -> SubAgentTask:
        """Spawn a sub-agent to handle task."""
        spec = self.agents.get(agent_name)
        if not spec:
            raise LaborMarketError(f"Agent '{agent_name}' not found")

        task_id = str(uuid.uuid4())
        sub_agent = await self._create_subagent(spec, context)

        task_obj = SubAgentTask(
            id=task_id,
            agent=sub_agent,
            status="running",
        )
        self.running[task_id] = task_obj

        # 异步执行
        asyncio.create_task(self._run_subagent(task_obj, task))

        return task_obj

    async def _run_subagent(self, task: SubAgentTask, input_text: str) -> None:
        """Run sub-agent and collect result."""
        try:
            result = await task.agent.run(input_text)
            task.result = result
            task.status = "completed"
        except Exception as e:
            task.error = str(e)
            task.status = "failed"

    async def wait_for(self, task_id: str, timeout: float = 300) -> SubAgentResult:
        """Wait for sub-agent completion."""
        task = self.running.get(task_id)
        if not task:
            raise LaborMarketError(f"Task '{task_id}' not found")

        start = time.time()
        while task.status == "running":
            if time.time() - start > timeout:
                raise TimeoutError(f"Task '{task_id}' timeout")
            await asyncio.sleep(0.1)

        if task.status == "failed":
            raise SubAgentError(task.error)

        return task.result
```

---

## opencode 流式处理器 + Scheduler

### 整体架构

opencode 采用 **流式处理器（Stream Processor）** 架构，配合 **Scheduler** 实现定时任务，支持 **死循环检测** 和 **细粒度权限控制**。

```
┌─────────────────────────────────────────────────────────────┐
│                    opencode 架构                            │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              SessionProcessor                       │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌───────────┐   │   │
│  │  │  LLM Stream │  │  Tool Exec  │  │  Snapshot │   │   │
│  │  │  (async gen)│  │             │  │   Track   │   │   │
│  │  └─────────────┘  └─────────────┘  └───────────┘   │   │
│  │                                                    │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌───────────┐   │   │
│  │  │ Doom Loop   │  │ Permission  │  │  Part     │   │   │
│  │  │  Detection  │  │   Next      │  │  Manager  │   │   │
│  │  └─────────────┘  └─────────────┘  └───────────┘   │   │
│  └─────────────────────────────────────────────────────┘   │
│                           │                                │
│           ┌───────────────┼───────────────┐                │
│           ▼               ▼               ▼                │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐       │
│  │  Scheduler   │ │  Compaction  │ │   Session    │       │
│  │              │ │              │ │   (SQLite)   │       │
│  └──────────────┘ └──────────────┘ └──────────────┘       │
└─────────────────────────────────────────────────────────────┘
```

### 流式处理器

```typescript
// packages/opencode/src/session/processor.ts
export namespace SessionProcessor {
  const DOOM_LOOP_THRESHOLD = 3; // 死循环检测阈值

  export function create(input: {
    assistantMessage: MessageV2.Assistant;
    sessionID: SessionID;
    model: Provider.Model;
    abort: AbortSignal;
  }) {
    const result = {
      async process(streamInput: LLM.StreamInput) {
        const { sessionID } = input;
        let snapshot: Snapshot.Info | undefined;
        let lastThree: ToolCallInfo[] = [];

        // 重试循环
        while (true) {
          const stream = await LLM.stream(streamInput);

          for await (const value of stream.fullStream) {
            switch (value.type) {
              case "start-step": {
                // 开始步骤，记录快照
                snapshot = await Snapshot.track();
                await Session.updatePart({
                  type: "step-start",
                  sessionID,
                  step: value.step,
                });
                break;
              }

              case "finish-step": {
                await Session.updatePart({
                  type: "step-finish",
                  sessionID,
                  step: value.step,
                  finishReason: value.finishReason,
                });
                break;
              }

              case "tool-call": {
                const toolCall: ToolCallInfo = {
                  name: value.name,
                  input: value.input,
                  timestamp: Date.now(),
                };
                lastThree.push(toolCall);
                if (lastThree.length > DOOM_LOOP_THRESHOLD) {
                  lastThree.shift();
                }

                // 死循环检测：相同工具重复调用
                if (
                  lastThree.length === DOOM_LOOP_THRESHOLD &&
                  lastThree.every(
                    (t) =>
                      t.name === lastThree[0].name &&
                      JSON.stringify(t.input) ===
                        JSON.stringify(lastThree[0].input)
                  )
                ) {
                  // 触发权限询问
                  await PermissionNext.ask({
                    permission: "doom_loop",
                    sessionID,
                    message: `Detected potential infinite loop: ${value.name} called repeatedly`,
                  });
                }

                // 执行工具
                await executeTool(value, sessionID);
                break;
              }

              case "text-delta": {
                // 流式文本更新
                await Session.updatePart({
                  type: "text",
                  sessionID,
                  delta: value.delta,
                });
                break;
              }

              case "error": {
                // 错误处理
                await Session.updatePart({
                  type: "error",
                  sessionID,
                  error: value.error,
                });

                // 是否重试
                if (isRetryable(value.error)) {
                  continue; // 重试
                }
                throw value.error;
              }
            }
          }

          // 检查是否需要继续（还有工具调用）
          if (stream.finishReason === "tool_calls") {
            continue;
          }
          break; // 完成
        }
      },
    };

    return result;
  }

  async function executeTool(
    toolCall: LLM.ToolCall,
    sessionID: SessionID
  ): Promise<void> {
    const tool = ToolRegistry.get(toolCall.name);

    // 权限检查
    const permitted = await PermissionNext.check({
      tool: toolCall.name,
      input: toolCall.input,
      sessionID,
    });

    if (!permitted) {
      throw new ToolBlockedError(toolCall.name);
    }

    // 执行
    const result = await tool.execute(toolCall.input);

    // 更新结果
    await Session.updatePart({
      type: "tool-result",
      sessionID,
      toolName: toolCall.name,
      result,
    });
  }
}
```

### Scheduler 定时任务

```typescript
// packages/opencode/src/scheduler/index.ts
export namespace Scheduler {
  export type Task = {
    id: string;
    interval: number; // 毫秒
    run: () => Promise<void>;
    scope?: "instance" | "global"; // 实例级或全局级
    retry?: {
      maxAttempts: number;
      backoff: "fixed" | "exponential";
      delay: number;
    };
  };

  const tasks = new Map<string, Task>();
  const timers = new Map<string, NodeJS.Timeout>();
  const running = new Map<string, boolean>();

  export function register(task: Task): void {
    tasks.set(task.id, task);

    // 立即执行一次
    void execute(task);

    // 设置定时器
    const timer = setInterval(() => {
      void execute(task);
    }, task.interval);

    timers.set(task.id, timer);
  }

  export async function execute(task: Task): Promise<void> {
    // 防止并发执行
    if (running.get(task.id)) {
      console.log(`Task ${task.id} already running, skipping`);
      return;
    }

    running.set(task.id, true);
    let attempts = 0;

    try {
      await task.run();
    } catch (error) {
      console.error(`Task ${task.id} failed:`, error);

      // 重试逻辑
      if (task.retry) {
        while (attempts < task.retry.maxAttempts) {
          attempts++;
          const delay =
            task.retry.backoff === "exponential"
              ? task.retry.delay * Math.pow(2, attempts - 1)
              : task.retry.delay;

          await sleep(delay);

          try {
            await task.run();
            break; // 成功
          } catch (e) {
            if (attempts >= task.retry.maxAttempts) {
              throw e; // 重试耗尽
            }
          }
        }
      }
    } finally {
      running.set(task.id, false);
    }
  }

  export function unregister(taskId: string): void {
    const timer = timers.get(taskId);
    if (timer) {
      clearInterval(timer);
      timers.delete(taskId);
    }
    tasks.delete(taskId);
    running.delete(taskId);
  }

  export function clear(): void {
    for (const [id, timer] of timers) {
      clearInterval(timer);
    }
    timers.clear();
    tasks.clear();
    running.clear();
  }
}

// 使用示例
Scheduler.register({
  id: "session-sync",
  interval: 30000, // 30秒
  run: async () => {
    await Session.sync();
  },
  retry: {
    maxAttempts: 3,
    backoff: "exponential",
    delay: 1000,
  },
});
```

### 死循环检测

```typescript
// packages/opencode/src/session/processor.ts
export namespace SessionProcessor {
  // 检测连续相同工具调用
  function detectDoomLoop(
    history: ToolCallInfo[],
    threshold: number
  ): boolean {
    if (history.length < threshold) {
      return false;
    }

    const lastN = history.slice(-threshold);
    const first = lastN[0];

    // 检查是否完全相同
    return lastN.every(
      (t) =>
        t.name === first.name &&
        deepEqual(t.input, first.input)
    );
  }

  // 检测工具调用循环模式
  function detectToolCycle(history: ToolCallInfo[]): string[] | null {
    const seen = new Map<string, number>();

    for (let i = history.length - 1; i >= 0; i--) {
      const signature = `${history[i].name}:${JSON.stringify(
        history[i].input
      )}`;

      if (seen.has(signature)) {
        const cycleStart = seen.get(signature)!;
        return history.slice(i, cycleStart + 1).map((t) => t.name);
      }

      seen.set(signature, i);
    }

    return null;
  }
}
```

### Session Compaction

```typescript
// packages/opencode/src/session/compaction.ts
export namespace SessionCompaction {
  const COMPACTION_BUFFER = 4000; // Token 缓冲区

  export async function isOverflow(input: {
    tokens: MessageV2.Assistant["tokens"];
    model: Provider.Model;
  }): Promise<boolean> {
    const config = await Config.get();
    if (config.compaction?.auto === false) return false;

    const context = input.model.limit.context;
    if (context === 0) return false;

    const count =
      input.tokens.total ||
      input.tokens.input +
        input.tokens.output +
        input.tokens.tools;

    // 计算可用空间
    const reserved =
      config.compaction?.reserved ??
      Math.min(
        COMPACTION_BUFFER,
        ProviderTransform.maxOutputTokens(input.model)
      );

    const usable = input.model.limit.input
      ? input.model.limit.input - reserved
      : context - ProviderTransform.maxOutputTokens(input.model);

    return count >= usable;
  }

  export async function compact(sessionID: SessionID): Promise<void> {
    const messages = await Message.list({ session_id: sessionID });

    // 保留最近 N 条
    const config = await Config.get();
    const reserveCount = config.compaction?.reserve ?? 10;
    const toSummarize = messages.slice(0, -reserveCount);
    const toKeep = messages.slice(-reserveCount);

    // 生成摘要
    const summary = await generateSummary(toSummarize);

    // 更新 Session
    await Session.update({
      id: sessionID,
      summary_additions: summary.additions,
      summary_deletions: summary.deletions,
      summary_files: summary.files,
      time_compacting: Date.now(),
    });

    // 标记旧消息为已压缩
    for (const msg of toSummarize) {
      await Message.update({
        id: msg.id,
        compacted: true,
      });
    }
  }
}
```

---

## openclaw Skill 工具库

### 架构定位

openclaw 主要是一个 **Skill/工具仓库**，而非完整的 Workflow/Task Engine。

```
┌─────────────────────────────────────────────────────────────┐
│                    openclaw Skills                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │   Python    │  │     Go      │  │      Shell          │ │
│  │   Skills    │  │   Skills    │  │     Scripts         │ │
│  │             │  │             │  │                     │ │
│  │ - translate │  │ - fetch     │  │ - setup             │ │
│  │ - image-gen │  │ - search    │  │ - backup            │ │
│  │ - doc-parse │  │ - parse     │  │ - deploy            │ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Skill 结构

```python
# skills/translate/skill.py
"""
name: translate
description: Translate documents between languages
author: openclaw
tags: ["translation", "nlp"]
"""

from openclaw import skill, Context

@skill
async def translate(ctx: Context, input_file: str, target_lang: str) -> str:
    """
    Translate a document to target language.

    Args:
        input_file: Path to input document
        target_lang: Target language code (en, zh, ja, etc.)

    Returns:
        Path to translated output file
    """
    # Load document
    content = await ctx.fs.read(input_file)

    # Call translation API
    result = await ctx.llm.chat([
        Message.system("You are a professional translator."),
        Message.user(f"Translate to {target_lang}:\n{content}")
    ])

    # Save output
    output_path = ctx.fs.with_suffix(input_file, f".{target_lang}.md")
    await ctx.fs.write(output_path, result.content)

    return output_path
```

### 与 Workflow Engine 的关系

openclaw 本身**不提供**以下 Workflow Engine 功能：
- ❌ 任务调度器
- ❌ 状态机管理
- ❌ 工作流编排
- ❌ 错误重试机制
- ❌ 并发控制

但可通过 **外部框架**（如 CoPaw/kimi-cli/opencode）调用其 Skills。

---

## 架构对比与推荐

### 四项目对比

| 维度 | CoPaw | kimi-cli | opencode | openclaw |
|------|-------|----------|----------|----------|
| **核心循环** | ReAct | Step Loop | Stream Processor | N/A |
| **调度方式** | APScheduler Cron | Asyncio Queue | Event Loop + Scheduler | N/A |
| **工作流定义** | 代码 + 配置 | Flow DSL (D2) | 流式配置 | N/A |
| **重试机制** | 基础重试 | tenacity 指数退避 | 手动重试循环 | N/A |
| **并发控制** | Semaphore | Asyncio.Semaphore | AbortSignal | N/A |
| **死循环检测** | ❌ | ❌ | ✅ Doom Loop | N/A |
| **时间回溯** | ❌ | ✅ D-Mail | ❌ | N/A |
| **子 Agent** | ❌ | ✅ Labor Market | ❌ | N/A |
| **状态持久化** | JSON 文件 | JSONL + Context | SQLite | N/A |
| **权限系统** | ToolGuard | Checkpoint | PermissionNext | N/A |

### 推荐混合架构

```
┌─────────────────────────────────────────────────────────────┐
│                    Workflow Definition                      │
│  ┌─────────────────────────────────────────────────────────┐│
│  │  - Flow DSL (kimi-cli D2) for visual workflow          ││
│  │  - Code-based (CoPaw) for complex logic                ││
│  │  - Config-based (YAML) for simple tasks                ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Task Scheduler                           │
│  ┌─────────────────────────────────────────────────────────┐│
│  │  Core: opencode Stream Processor                        ││
│  │  - Async generator for streaming                       ││
│  │  - Real-time Part updates                              ││
│  │                                                         ││
│  │  Cron: CoPaw APScheduler                               ││
│  │  - Cron expression support                             ││
│  │  - Per-job concurrency limit                           ││
│  │                                                         ││
│  │  SubAgent: kimi-cli Labor Market                       ││
│  │  - Spawn child agents                                  ││
│  │  - Async task delegation                               ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Execution Engine                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │ Step Loop   │  │ Retry       │  │  Doom Loop          │ │
│  │ (kimi-cli)  │  │ (tenacity)  │  │  (opencode)         │ │
│  │             │  │             │  │                     │ │
│  │ - _step()   │  │ - Exponential│  │ - Detect cycles     │ │
│  │ - Checkpoint│  │ - Jitter    │  │ - Permission ask    │ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    State Management                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │ D-Mail      │  │ SQLite      │  │  JSONL              │ │
│  │ (kimi-cli)  │  │ (opencode)  │  │  (kimi-cli)         │ │
│  │             │  │             │  │                     │ │
│  │ - Time      │  │ - Messages  │  │  - Wire events      │ │
│  │   travel    │  │ - Parts     │  │  - Checkpoints      │ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### 关键设计建议

1. **工作流定义**: 混合模式
   - 简单流程: YAML 配置
   - 复杂流程: Flow DSL (D2)
   - 动态逻辑: Python/TypeScript 代码

2. **调度策略**:
   - 实时交互: Stream Processor (opencode)
   - 定时任务: APScheduler (CoPaw)
   - 子任务: Labor Market (kimi-cli)

3. **错误处理**:
   - 重试: tenacity 指数退避
   - 死循环: Doom Loop Detection
   - 恢复: D-Mail Checkpoint

4. **状态管理**:
   - 运行时: SQLite (结构化查询)
   - 事件流: JSONL (审计日志)
   - 回溯: Checkpoint (时间旅行)

---

## 附录：关键代码文件

| 项目 | 关键文件 | 说明 |
|------|----------|------|
| **CoPaw** | `agents/base.py` | ReActAgent 循环 |
| **CoPaw** | `app/crons/manager.py` | CronManager 调度 |
| **CoPaw** | `app/crons/models.py` | CronJob 配置 |
| **kimi-cli** | `soul/kimisoul.py` | Step Loop 实现 |
| **kimi-cli** | `soul/denwa_renji.py` | D-Mail 系统 |
| **kimi-cli** | `soul/labor_market.py` | SubAgent 市场 |
| **kimi-cli** | `flow/models.py` | Flow DSL |
| **opencode** | `session/processor.ts` | Stream Processor |
| **opencode** | `scheduler/index.ts` | Scheduler |
| **opencode** | `session/compaction.ts` | Compaction |
| **openclaw** | `skills/**` | Skill 工具库 |

---

*报告生成时间: 2025-03-13*
*分析项目: CoPaw, kimi-cli, openclaw, opencode*
