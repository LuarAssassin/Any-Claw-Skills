# Channel Adapter 架构分析：飞书/钉钉/QQ/Web 统一协议

## 目录
1. [核心概念](#核心概念)
2. [CoPaw 多渠道架构](#copaw-多渠道架构)
3. [kimi-cli Wire 通信机制](#kimi-cli-wire-通信机制)
4. [openclaw Adapter 组合架构](#openclaw-adapter-组合架构)
5. [opencode Provider 扩展架构](#opencode-provider-扩展架构)
6. [架构对比与推荐](#架构对比与推荐)

---

## 核心概念

### Channel Adapter 设计目标

| 挑战 | 解决方案方向 |
|------|-------------|
| 多平台协议差异 | 统一消息抽象层 |
| 身份认证方式不同 | 渠道独立配置 + 统一认证接口 |
| 媒体类型差异 | 内容类型系统标准化 |
| 消息格式不兼容 | 双向转换器（Native ↔ Internal） |
| 连接方式差异 | 连接管理抽象（WebSocket/HTTP/长轮询） |

### 统一协议关键组件

```
┌─────────────────────────────────────────────────────────────┐
│                    外部消息渠道层                            │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐          │
│  │  飞书   │ │  钉钉   │ │   QQ    │ │ Discord │  ...     │
│  │ WebSocket│ │ Stream  │ │  HTTP   │ │ Gateway │          │
│  └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘          │
└───────┼──────────┼──────────┼──────────┼──────────────────┘
        │          │          │          │
        ▼          ▼          ▼          ▼
┌─────────────────────────────────────────────────────────────┐
│                    Channel Adapter 层                        │
│  ┌─────────────────────────────────────────────────────────┐│
│  │  Native Message Converter                               ││
│  │  - 协议解析 (飞书 Card / 钉钉 Markdown / QQ XML)          ││
│  │  - 身份验证 (Token/AppKey/SessionWebhook)                ││
│  │  - 媒体处理 (下载/上传/格式转换)                          ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    统一内部协议层                            │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────┐ │
│  │AgentRequest │◀──▶│ ContentPart │◀──▶│  ChannelAddress │ │
│  │ - message   │    │ - text      │    │  - kind (dm/group)│
│  │ - sender    │    │ - image     │    │  - id           │ │
│  │ - metadata  │    │ - file      │    │  - extra        │ │
│  └─────────────┘    └─────────────┘    └─────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Agent 核心处理层                          │
│              LLM 调用 / 工具执行 / 记忆管理                   │
└─────────────────────────────────────────────────────────────┘
```

---

## CoPaw 多渠道架构

### 整体架构

CoPaw 实现了完整的多渠道适配器架构，支持 **11 种渠道**：飞书、钉钉、QQ、Discord、iMessage、Telegram、Matrix、Mattermost、MQTT、Console、Voice。

```
┌─────────────────────────────────────────────────────────────┐
│                    ChannelManager                           │
│  ┌─────────────────────────────────────────────────────────┐│
│  │  - 队列管理 (asyncio.Queue × N channels)                 ││
│  │  - 并发处理 (4 workers per channel)                      ││
│  │  - 会话防抖 (same session merge)                         ││
│  │  - 线程安全入队 (sync → async bridge)                    ││
│  └─────────────────────────────────────────────────────────┘│
└────────────┬──────────────┬──────────────┬───────────────────┘
             │              │              │
    ┌────────▼────────┐    ┌▼─────────┐   ┌▼──────────┐
    │   BaseChannel   │    │ Registry │   │  Schema   │
    │   (抽象基类)     │    │(动态加载) │   │(统一协议) │
    └─────────────────┘    └──────────┘   └───────────┘
```

### BaseChannel 抽象基类

```python
# src/copaw/app/channels/base.py
class BaseChannel(ABC):
    """Base for all channels. Queue lives in ChannelManager; channel defines
    how to consume via consume_one().
    """
    channel: ChannelType
    uses_manager_queue: bool = True

    def __init__(
        self,
        process: ProcessHandler,           # 消息处理器注入
        on_reply_sent: OnReplySent = None,
        show_tool_details: bool = True,
        filter_tool_messages: bool = False,
        filter_thinking: bool = False,
        dm_policy: str = "open",           # DM 权限策略
        group_policy: str = "open",        # 群聊权限策略
        allow_from: Optional[list] = None, # 白名单
        deny_message: str = "",
        require_mention: bool = False,     # 群聊是否需要 @
    ):
```

### 统一协议 Schema

```python
# src/copaw/app/channels/schema.py
@dataclass
class ChannelAddress:
    """
    Unified routing for send: kind + id + extra.
    Replaces ad-hoc meta keys (channel_id, user_id, session_webhook, etc.).
    """
    kind: str  # "dm" | "channel" | "webhook" | "console"
    id: str
    extra: Optional[Dict[str, Any]] = None

@runtime_checkable
class ChannelMessageConverter(Protocol):
    """Protocol for channel message conversion."""

    def build_agent_request_from_native(
        self,
        native_payload: Any
    ) -> AgentRequest:
        """Convert native message payload to AgentRequest."""

    async def send_response(
        self,
        to_handle: str,
        response: AgentResponse,
        meta: Optional[dict] = None,
    ) -> None:
        """Convert AgentResponse to channel reply and send."""
```

### 内容类型系统

```python
# 统一内容类型枚举
class ContentType(Enum):
    TEXT = "text"
    IMAGE = "image"
    VIDEO = "video"
    AUDIO = "audio"
    FILE = "file"
    REFUSAL = "refusal"
    TOOL_CALL = "tool_call"
    TOOL_RESULT = "tool_result"

# 统一消息结构
@dataclass
class AgentRequest:
    content: List[ContentPart]      # 多模态内容支持
    sender: SenderInfo              # 统一发件人标识
    session_id: str                 # 会话 ID
    channel_address: ChannelAddress # 路由地址
    metadata: Dict[str, Any]        # 渠道特定元数据

@dataclass
class AgentResponse:
    content: List[ContentPart]
    tool_calls: Optional[List[ToolCall]]
    metadata: Dict[str, Any]
```

### 渠道注册与动态加载

```python
# src/copaw/app/channels/registry.py
_BUILTIN_SPECS: dict[str, tuple[str, str]] = {
    "imessage": (".imessage", "IMessageChannel"),
    "discord": (".discord_", "DiscordChannel"),
    "dingtalk": (".dingtalk", "DingTalkChannel"),
    "feishu": (".feishu", "FeishuChannel"),
    "qq": (".qq", "QQChannel"),
    "telegram": (".telegram", "TelegramChannel"),
    "matrix": (".matrix", "MatrixChannel"),
    "mattermost": (".mattermost", "MattermostChannel"),
    "mqtt": (".mqtt", "MQTTChannel"),
    "console": (".console", "ConsoleChannel"),
    "voice": (".voice", "VoiceChannel"),
}

def get_channel_registry() -> dict[str, type[BaseChannel]]:
    """Built-in channels + custom channels from custom_channels/."""
    out = _get_cached_builtin_channels()
    out.update(_discover_custom_channels())  # 动态加载自定义渠道
    return out

def _discover_custom_channels() -> dict[str, type[BaseChannel]]:
    """Load custom channel classes from custom_channels/ directory."""
    custom_dir = Path("custom_channels")
    if not custom_dir.exists():
        return {}

    channels = {}
    for file_path in custom_dir.glob("*.py"):
        module_name = file_path.stem
        spec = importlib.util.spec_from_file_location(
            f"custom_channels.{module_name}", file_path
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        # 查找 BaseChannel 子类
        for name, obj in inspect.getmembers(module, inspect.isclass):
            if issubclass(obj, BaseChannel) and obj is not BaseChannel:
                channels[obj.channel] = obj
    return channels
```

### 飞书渠道实现

```python
# src/copaw/app/channels/feishu/channel.py
class FeishuChannel(BaseChannel):
    """Feishu/Lark channel: WebSocket receive, Open API send."""
    channel = "feishu"

    def __init__(
        self,
        process: ProcessHandler,
        enabled: bool,
        app_id: str,
        app_secret: str,
        bot_prefix: str = "bot",
        encrypt_key: Optional[str] = None,
        verification_token: Optional[str] = None,
    ):
        super().__init__(process, ...)
        self.app_id = app_id
        self.app_secret = app_secret
        self.bot_prefix = bot_prefix

    # ========== 入站消息处理 ==========
    async def consume_one(self, payload: dict) -> None:
        """Consume one message from the queue."""
        # 1. 验证消息签名
        if not self._verify_signature(payload):
            return

        # 2. 解析飞书消息格式
        feishu_msg = json.loads(payload.get("body", "{}"))

        # 3. 转换为统一 AgentRequest
        agent_request = self._build_agent_request(feishu_msg)

        # 4. 调用 process handler
        response = await self.process(agent_request)

        # 5. 发送回复
        await self.send_response(agent_request.channel_address, response)

    def _build_agent_request(self, feishu_msg: dict) -> AgentRequest:
        """Convert Feishu message to unified AgentRequest."""
        message_type = feishu_msg.get("header", {}).get("event_type")
        event = feishu_msg.get("event", {})

        # 提取内容
        content = self._parse_content(event.get("message", {}).get("content"))

        # 构建统一地址
        chat_type = event.get("message", {}).get("chat_type")  # "p2p" | "group"
        address = ChannelAddress(
            kind="dm" if chat_type == "p2p" else "channel",
            id=event.get("message", {}).get("chat_id"),
            extra={
                "message_id": event.get("message", {}).get("message_id"),
                "sender_open_id": event.get("sender", {}).get("sender_id", {}).get("open_id"),
            }
        )

        return AgentRequest(
            content=[ContentPart(type=ContentType.TEXT, text=content)],
            sender=SenderInfo(
                id=event.get("sender", {}).get("sender_id", {}).get("open_id"),
                name=event.get("sender", {}).get("sender_id", {}).get("name"),
            ),
            session_id=self._build_session_id(address),
            channel_address=address,
            metadata={"raw_event": feishu_msg},
        )

    # ========== 出站消息发送 ==========
    async def send_response(
        self,
        address: ChannelAddress,
        response: AgentResponse,
        meta: Optional[dict] = None,
    ) -> None:
        """Send response via Feishu Open API."""
        access_token = await self._get_access_token()

        for part in response.content:
            if part.type == ContentType.TEXT:
                await self._send_text(
                    chat_id=address.id,
                    text=part.text,
                    reply_message_id=address.extra.get("message_id"),
                )
            elif part.type == ContentType.IMAGE:
                await self._send_image(
                    chat_id=address.id,
                    image_key=await self._upload_image(part.image_data),
                )
            elif part.type == ContentType.FILE:
                await self._send_file(
                    chat_id=address.id,
                    file_key=await self._upload_file(part.file_data),
                )

    async def _send_text(self, chat_id: str, text: str, reply_message_id: str = None):
        """Send text message via Feishu API."""
        url = "https://open.feishu.cn/open-apis/im/v1/messages"
        headers = {"Authorization": f"Bearer {await self._get_access_token()}"}
        payload = {
            "receive_id": chat_id,
            "content": json.dumps({"text": text}),
            "msg_type": "text",
        }
        if reply_message_id:
            payload["reply_in_thread"] = True
            # or use reply_to_message_id for specific reply
        async with aiohttp.ClientSession() as session:
            async with session.post(url, headers=headers, json=payload) as resp:
                return await resp.json()
```

### 钉钉渠道实现

```python
# src/copaw/app/channels/dingtalk/channel.py
class DingTalkChannel(BaseChannel):
    """DingTalk Channel: DingTalk Stream -> Incoming -> to_agent_request ->
    process -> send_response -> DingTalk reply.
    """
    channel = "dingtalk"

    def __init__(
        self,
        process: ProcessHandler,
        enabled: bool,
        client_id: str,
        client_secret: str,
        bot_prefix: str = "bot",
    ):
        super().__init__(process, ...)
        self.client_id = client_id
        self.client_secret = client_secret
        # 钉钉特有：存储 sessionWebhook 用于主动推送
        self._session_webhook_store: Dict[str, str] = {}

    async def consume_one(self, payload: dict) -> None:
        """Handle DingTalk incoming message."""
        # 钉钉 Stream 推送格式
        dingtalk_msg = payload.get("data", {})

        # 存储 sessionWebhook（用于后续主动推送）
        session_webhook = dingtalk_msg.get("sessionWebhook")
        conversation_id = dingtalk_msg.get("conversationId")
        if session_webhook and conversation_id:
            self._session_webhook_store[conversation_id] = session_webhook

        # 转换为统一格式
        agent_request = self._build_agent_request(dingtalk_msg)
        response = await self.process(agent_request)
        await self.send_response(agent_request.channel_address, response)

    def _build_agent_request(self, dingtalk_msg: dict) -> AgentRequest:
        """Convert DingTalk message to AgentRequest."""
        msg_type = dingtalk_msg.get("msgtype", "text")

        # 提取内容（钉钉支持 text/markdown/action_card）
        content = self._extract_content(dingtalk_msg, msg_type)

        # 判断消息来源（单聊/群聊）
        conversation_type = dingtalk_msg.get("conversationType")  # "1"=单聊, "2"=群聊

        address = ChannelAddress(
            kind="dm" if conversation_type == "1" else "channel",
            id=dingtalk_msg.get("conversationId"),
            extra={
                "session_webhook": dingtalk_msg.get("sessionWebhook"),
                "sender_staff_id": dingtalk_msg.get("senderStaffId"),
                "msg_id": dingtalk_msg.get("msgId"),
            }
        )

        return AgentRequest(
            content=[ContentPart(type=ContentType.TEXT, text=content)],
            sender=SenderInfo(
                id=dingtalk_msg.get("senderStaffId"),
                name=dingtalk_msg.get("senderNick"),
            ),
            session_id=self._build_session_id(address),
            channel_address=address,
            metadata={
                "msg_type": msg_type,
                "raw_message": dingtalk_msg,
            },
        )

    async def send_response(
        self,
        address: ChannelAddress,
        response: AgentResponse,
        meta: Optional[dict] = None,
    ) -> None:
        """Send response via DingTalk API."""
        # 使用 sessionWebhook 回复（更快速）
        session_webhook = address.extra.get("session_webhook")
        if session_webhook:
            await self._send_via_webhook(session_webhook, response)
        else:
            # 回退到 Open API
            await self._send_via_openapi(address.id, response)

    async def _send_via_webhook(
        self,
        webhook_url: str,
        response: AgentResponse
    ) -> None:
        """Send via DingTalk session webhook."""
        text_parts = [p.text for p in response.content if p.type == ContentType.TEXT]
        payload = {
            "msgtype": "markdown",
            "markdown": {
                "title": "AI Response",
                "text": "\n".join(text_parts),
            }
        }
        async with aiohttp.ClientSession() as session:
            async with session.post(webhook_url, json=payload) as resp:
                return await resp.json()
```

### QQ 渠道实现

```python
# src/copaw/app/channels/qq/channel.py
class QQChannel(BaseChannel):
    """QQ Channel implementation using QQ Bot API."""
    channel = "qq"

    def __init__(
        self,
        process: ProcessHandler,
        enabled: bool,
        app_id: str,
        token: str,
        secret: Optional[str] = None,
        sandbox: bool = False,
    ):
        super().__init__(process, ...)
        self.app_id = app_id
        self.token = token
        self.secret = secret
        self.sandbox = sandbox
        self.api_base = "https://sandbox.api.sgroup.qq.com" if sandbox else "https://api.sgroup.qq.com"

    def _build_agent_request(self, qq_msg: dict) -> AgentRequest:
        """Convert QQ Bot message to AgentRequest."""
        # QQ 消息类型：0=文字, 2=Markdown, 4=ARK, ...
        msg_type = qq_msg.get("d", {}).get("message_type", 0)

        # 提取内容
        content = qq_msg.get("d", {}).get("content", "")
        # 去除 @机器人的部分
        content = self._remove_mention(content, qq_msg.get("d", {}).get("mentions", []))

        # QQ 渠道类型：0=频道, 1=频道私信, 2=群聊, 3=单聊
        channel_type = qq_msg.get("d", {}).get("channel_type", 0)

        channel_id = qq_msg.get("d", {}).get("channel_id") or qq_msg.get("d", {}).get("group_id")

        address = ChannelAddress(
            kind="dm" if channel_type in [1, 3] else "channel",
            id=channel_id,
            extra={
                "guild_id": qq_msg.get("d", {}).get("guild_id"),
                "message_id": qq_msg.get("d", {}).get("id"),
                "channel_type": channel_type,
            }
        )

        return AgentRequest(
            content=[ContentPart(type=ContentType.TEXT, text=content)],
            sender=SenderInfo(
                id=qq_msg.get("d", {}).get("author", {}).get("id"),
                name=qq_msg.get("d", {}).get("author", {}).get("username"),
            ),
            session_id=self._build_session_id(address),
            channel_address=address,
            metadata={
                "seq": qq_msg.get("s"),  # WebSocket sequence
                "raw_message": qq_msg,
            },
        )

    async def send_response(
        self,
        address: ChannelAddress,
        response: AgentResponse,
        meta: Optional[dict] = None,
    ) -> None:
        """Send response via QQ Bot API."""
        url = f"{self.api_base}/channels/{address.id}/messages"
        headers = {"Authorization": f"QQBot {await self._get_access_token()}"}

        for part in response.content:
            if part.type == ContentType.TEXT:
                payload = {"content": part.text}
                # 回复指定消息
                if address.extra.get("message_id"):
                    payload["msg_id"] = address.extra["message_id"]

                async with aiohttp.ClientSession() as session:
                    async with session.post(url, headers=headers, json=payload) as resp:
                        result = await resp.json()
```

### ChannelManager 队列与并发管理

```python
# src/copaw/app/channels/manager.py
class ChannelManager:
    """Owns queues and consumer loops; channels define how to consume."""

    def __init__(self, channels: List[BaseChannel]):
        self.channels = channels
        self._queues: Dict[str, asyncio.Queue] = {}
        self._consumer_tasks: List[asyncio.Task[None]] = []
        self._lock = asyncio.Lock()

    async def start(self) -> None:
        """Start all channel consumers."""
        for channel in self.channels:
            if not channel.enabled:
                continue

            # 每个渠道独立队列
            queue = asyncio.Queue(maxsize=1000)
            self._queues[channel.channel] = queue

            # 启动 4 个消费者 worker
            for i in range(4):
                task = asyncio.create_task(
                    self._consumer_loop(channel, queue),
                    name=f"{channel.channel}-worker-{i}"
                )
                self._consumer_tasks.append(task)

            # 启动渠道特定的接收器
            await channel.start_receiving(self)

    async def _consumer_loop(
        self,
        channel: BaseChannel,
        queue: asyncio.Queue
    ) -> None:
        """Consume messages from queue with debouncing."""
        pending_sessions: Dict[str, List[dict]] = {}

        while True:
            try:
                # 获取消息（带超时）
                payload = await asyncio.wait_for(
                    queue.get(),
                    timeout=0.5
                )

                session_id = self._extract_session_id(payload)

                # 防抖：合并同一会话的连续消息
                if session_id in pending_sessions:
                    pending_sessions[session_id].append(payload)
                else:
                    pending_sessions[session_id] = [payload]

                # 处理待处理的消息
                await self._process_pending_sessions(channel, pending_sessions)

            except asyncio.TimeoutError:
                # 超时后处理积累的会话
                if pending_sessions:
                    await self._process_pending_sessions(channel, pending_sessions)

    async def enqueue(self, channel_id: str, payload: dict) -> bool:
        """Thread-safe enqueue from sync WebSocket/polling threads."""
        queue = self._queues.get(channel_id)
        if not queue:
            return False

        try:
            queue.put_nowait(payload)
            return True
        except asyncio.QueueFull:
            return False
```

---

## kimi-cli Wire 通信机制

### 架构定位

kimi-cli 是**纯 CLI 工具**，不实现多渠道适配，其 Wire 架构专注于**本地 Soul 与 UI 的通信**。

```
┌─────────────────────────────────────────────────────────────┐
│                    Soul (Agent Runtime)                     │
│  ┌─────────────────┐                                       │
│  │  WireSoulSide   │──────▶ Raw Queue                      │
│  │  (事件生产者)    │         (原始事件)                     │
│  └─────────────────┘               │                        │
└────────────────────────────────────┼────────────────────────┘
                                     │ broadcast
                                     ▼
┌─────────────────────────────────────────────────────────────┐
│                      Wire (SPMC Channel)                    │
│  ┌─────────────────────────────────────────────────────────┐│
│  │  BroadcastQueue                                         ││
│  │  - _raw_queue: 原始事件流                               ││
│  │  - _merged_queue: 合并后事件（减少UI更新）               ││
│  │  - _consumers: 多消费者订阅                              ││
│  └─────────────────────────────────────────────────────────┘│
└────────────────────────────────────┼────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────┐
│                    UI (Terminal Interface)                  │
│  ┌─────────────────┐    ┌─────────────────┐                │
│  │  Live Display   │    │  File Backend   │                │
│  │  (实时渲染)      │    │  (wire.jsonl)   │                │
│  └─────────────────┘    └─────────────────┘                │
└─────────────────────────────────────────────────────────────┘
```

### Wire SPMC 通信机制

```python
# src/kimi_cli/wire/__init__.py
class Wire:
    """
    A spmc channel for communication between the soul and the UI during a soul run.
    Single Producer Multiple Consumer: Soul produces, UI and file backend consume.
    """

    def __init__(self, *, file_backend: WireFile | None = None):
        self._raw_queue = WireMessageQueue()
        self._merged_queue = WireMessageQueue()
        self._soul_side = WireSoulSide(self._raw_queue, self._merged_queue)
        self._file_backend = file_backend

    def soul_side(self) -> WireSoulSide:
        return self._soul_side

    def subscribe(self) -> WireSubscription:
        """Subscribe to merged events."""
        return self._merged_queue.subscribe()

    async def run_file_backend(self) -> None:
        """Run file backend consumer."""
        if self._file_backend is None:
            return

        sub = self._raw_queue.subscribe()
        try:
            async for msg in sub:
                await self._file_backend.append_message(msg)
        finally:
            sub.close()
```

### 消息类型系统

```python
# src/kimi_cli/wire/types.py
# 事件类型（Soul -> UI）
class TurnBegin(BaseModel):
    type: Literal["turn_begin"] = "turn_begin"
    request_id: str
    timestamp: float

class ContentPart(BaseModel):
    type: Literal["content"] = "content"
    request_id: str
    index: int
    delta: str  # 增量文本

class ToolCall(BaseModel):
    type: Literal["tool_call"] = "tool_call"
    request_id: str
    tool_id: str
    name: str
    input_preview: str

class ToolResult(BaseModel):
    type: Literal["tool_result"] = "tool_result"
    request_id: str
    tool_id: str
    result_preview: str
    is_error: bool

class TurnEnd(BaseModel):
    type: Literal["turn_end"] = "turn_end"
    request_id: str
    finish_reason: str  # "stop" | "length" | "tool_calls"

# 请求类型（UI -> Soul）
class ApprovalRequest(BaseModel):
    type: Literal["approval_request"] = "approval_request"
    request_id: str
    tool_name: str
    tool_input: dict
    checkpoint_id: int

class ApprovalResponse(BaseModel):
    type: Literal["approval_response"] = "approval_response"
    request_id: str
    approved: bool
    feedback: Optional[str]

# 联合类型
Event = TurnBegin | TurnEnd | ContentPart | ToolCall | ToolResult | ...
Request = ApprovalRequest | ApprovalResponse | QuestionRequest
WireMessage = Event | Request
```

### 消息合并优化

```python
# src/kimi_cli/wire/queue.py
class WireMessageQueue:
    """Broadcast queue with message merging for UI efficiency."""

    def __init__(self):
        self._subscribers: List[_QueueSubscription] = []
        self._last_content: Dict[str, ContentPart] = {}  # 缓存最后内容

    def publish(self, msg: WireMessage) -> None:
        """Publish message to all subscribers with merging."""
        # 合并连续的内容增量
        if isinstance(msg, ContentPart):
            last = self._last_content.get(msg.request_id)
            if last and last.index == msg.index:
                # 合并到同一个内容块
                last.delta += msg.delta
                return  # 不发布增量，合并到现有块
            self._last_content[msg.request_id] = msg

        # 广播到所有订阅者
        for sub in self._subscribers:
            sub.put_nowait(msg)
```

---

## openclaw Adapter 组合架构

### 整体架构

openclaw 采用**细粒度 Adapter 组合模式**，支持 9 种核心聊天渠道。

```
┌─────────────────────────────────────────────────────────────┐
│                    Channel Dock (组合入口)                   │
│  ┌─────────────────────────────────────────────────────────┐│
│  │  ChannelDock                                            ││
│  │  - id: ChannelId                                        ││
│  │  - capabilities: ChannelCapabilities                    ││
│  │  - config?: ConfigAdapter                               ││
│  │  - outbound?: OutboundAdapter                           ││
│  │  - gateway?: GatewayAdapter                             ││
│  │  - groups?: GroupAdapter                                ││
│  │  - threading?: ThreadingAdapter                         ││
│  │  - security?: SecurityAdapter                           ││
│  │  - ... (10+ 种可选 Adapter)                              ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    具体渠道实现                              │
│  ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────┐   │
│  │ Telegram  │ │ WhatsApp  │ │  Discord  │ │  Signal   │   │
│  │  Bot API  │ │   Web     │ │  Gateway  │ │  Bridge   │   │
│  └───────────┘ └───────────┘ └───────────┘ └───────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 核心类型定义

```typescript
// src/channels/plugins/types.core.ts
export type ChannelId = ChatChannelId | (string & {});

export type ChatChannelId =
  | "telegram"
  | "whatsapp"
  | "discord"
  | "irc"
  | "googlechat"
  | "slack"
  | "signal"
  | "imessage"
  | "line";

// 渠道能力声明
export type ChannelCapabilities = {
  chatTypes: Array<ChatType | "thread">;  // 支持的聊天类型
  polls?: boolean;        // 是否支持投票
  reactions?: boolean;    // 是否支持表情反应
  edit?: boolean;         // 是否支持编辑消息
  unsend?: boolean;       // 是否支持撤回
  reply?: boolean;        // 是否支持回复
  effects?: boolean;      // 是否支持消息特效
  groupManagement?: boolean;  // 是否支持群管理
  threads?: boolean;      // 是否支持线程
  media?: boolean;        // 是否支持多媒体
  nativeCommands?: boolean;   // 是否支持原生命令
  blockStreaming?: boolean;   // 是否阻塞流式输出
};

export type ChannelMeta = {
  id: ChannelId;
  label: string;
  selectionLabel: string;
  docsPath: string;
  blurb: string;
  systemImage?: string;
  aliases?: string[];
  recommended?: boolean;
  tags?: string[];
};
```

### 细粒度 Adapter 接口

```typescript
// src/channels/plugins/types.adapters.ts

// ========== 配置适配器 ==========
export type ChannelConfigAdapter<ResolvedAccount> = {
  listAccountIds: (cfg: OpenClawConfig) => string[];
  resolveAccount: (
    cfg: OpenClawConfig,
    accountId?: string | null
  ) => ResolvedAccount;
  resolveAllowFrom?: (params: {
    cfg: OpenClawConfig;
    accountId?: string | null;
  }) => Array<string | number> | undefined;
  formatAllowFrom?: (id: string | number) => string;
};

// ========== 出站消息适配器 ==========
export type ChannelOutboundAdapter = {
  deliveryMode: "direct" | "gateway" | "hybrid";
  sendText?: (ctx: ChannelOutboundContext) => Promise<OutboundDeliveryResult>;
  sendMedia?: (ctx: ChannelOutboundContext) => Promise<OutboundDeliveryResult>;
  sendPoll?: (ctx: ChannelPollContext) => Promise<ChannelPollResult>;
};

// ========== 网关适配器 ==========
export type ChannelGatewayAdapter<ResolvedAccount = unknown> = {
  startAccount?: (ctx: ChannelGatewayContext<ResolvedAccount>) => Promise<unknown>;
  stopAccount?: (ctx: ChannelGatewayContext<ResolvedAccount>) => Promise<void>;
  loginWithQrStart?: (params: {
    cfg: OpenClawConfig;
    accountId?: string | null;
  }) => Promise<ChannelLoginWithQrStartResult>;
  loginWithQrWait?: (params: {
    cfg: OpenClawConfig;
    accountId?: string | null;
    qrData: ChannelLoginWithQrStartResult;
  }) => Promise<ChannelLoginWithQrWaitResult>;
};

// ========== 群组适配器 ==========
export type ChannelGroupAdapter = {
  resolveRequireMention?: (
    params: ChannelGroupContext
  ) => boolean | undefined;
  resolveGroupIntroHint?: (
    params: ChannelGroupContext
  ) => string | undefined;
  resolveToolPolicy?: (
    params: ChannelGroupContext
  ) => GroupToolPolicyConfig | undefined;
};

// ========== 线程适配器 ==========
export type ChannelThreadingAdapter = {
  resolveReplyToMode?: (params: {
    cfg: OpenClawConfig;
    accountId?: string | null;
    conversation: Conversation;
  }) => "off" | "first" | "all";
  buildToolContext?: (params: {
    cfg: OpenClawConfig;
    accountId?: string | null;
    conversation: Conversation;
    toolCall: ToolCall;
  }) => ChannelThreadingToolContext | undefined;
};

// ========== 安全适配器 ==========
export type ChannelSecurityAdapter<ResolvedAccount = unknown> = {
  resolveDmPolicy?: (
    ctx: ChannelSecurityContext<ResolvedAccount>
  ) => ChannelSecurityDmPolicy | null;
  collectWarnings?: (
    ctx: ChannelSecurityContext<ResolvedAccount>
  ) => Promise<string[]> | string[];
};

// ========== Mention 适配器 ==========
export type ChannelMentionAdapter = {
  resolveMentionText?: (params: {
    cfg: OpenClawConfig;
    accountId?: string | null;
    account: AccountBase;
  }) => string | undefined;
  resolveMentionHtml?: (params: {
    cfg: OpenClawConfig;
    accountId?: string | null;
    account: AccountBase;
  }) => string | undefined;
  resolveMentionMarkdown?: (params: {
    cfg: OpenClawConfig;
    accountId?: string | null;
    account: AccountBase;
  }) => string | undefined;
};

// ========== Agent Prompt 适配器 ==========
export type ChannelAgentPromptAdapter = {
  buildSystemPrompt?: (params: {
    cfg: OpenClawConfig;
    accountId?: string | null;
    agentPersonality: string;
    channelMeta: ChannelMeta;
  }) => string | undefined;
};
```

### Channel Dock 组合模式

```typescript
// src/channels/dock.ts
export type ChannelDock = {
  id: ChannelId;
  capabilities: ChannelCapabilities;

  // 命令处理
  commands?: ChannelCommandAdapter;

  // 出站消息
  outbound?: {
    textChunkLimit?: number;  // 文本分块限制
  };

  // 流式输出配置
  streaming?: ChannelDockStreaming;

  // 提权操作
  elevated?: ChannelElevatedAdapter;

  // 配置管理
  config?: Pick<
    ChannelConfigAdapter<unknown>,
    "resolveAllowFrom" | "formatAllowFrom" | "resolveDefaultTo"
  >;

  // 群组管理
  groups?: ChannelGroupAdapter;

  // Mention 处理
  mentions?: ChannelMentionAdapter;

  // 线程处理
  threading?: ChannelThreadingAdapter;

  // Agent 提示词
  agentPrompt?: ChannelAgentPromptAdapter;

  // 安全策略
  security?: ChannelSecurityAdapter;

  // 网关管理
  gateway?: ChannelGatewayAdapter;
};

// 创建 Channel Dock 的工厂函数
export function createChannelDock(
  channelId: ChannelId,
  adapters: Partial<ChannelDock>
): ChannelDock {
  return {
    id: channelId,
    capabilities: getDefaultCapabilities(channelId),
    ...adapters,
  };
}
```

### Telegram 渠道实现示例

```typescript
// src/channels/plugins/telegram/dock.ts
export const telegramDock: ChannelDock = createChannelDock("telegram", {
  capabilities: {
    chatTypes: ["dm", "group", "thread"],
    polls: true,
    reactions: true,
    edit: true,
    unsend: true,
    reply: true,
    effects: false,
    groupManagement: true,
    threads: true,
    media: true,
    nativeCommands: true,
    blockStreaming: false,
  },

  // 配置适配器
  config: {
    listAccountIds: (cfg) => {
      return cfg.channels?.telegram?.accounts?.map(a => a.id) || [];
    },
    resolveAccount: (cfg, accountId) => {
      const accounts = cfg.channels?.telegram?.accounts || [];
      return accounts.find(a => a.id === accountId) || accounts[0];
    },
    resolveAllowFrom: (params) => {
      const account = params.cfg.channels?.telegram?.accounts?.[0];
      return account?.allowFrom;
    },
    formatAllowFrom: (id) => {
      // Telegram 用户名格式化
      return id.toString().startsWith("@") ? id : `@${id}`;
    },
  },

  // 出站消息适配器
  outbound: {
    deliveryMode: "direct",
    sendText: async (ctx) => {
      const { account, conversation, text } = ctx;
      const bot = new Telegraf(account.token);

      const result = await bot.telegram.sendMessage(
        conversation.id,
        text,
        {
          reply_to_message_id: ctx.replyTo?.messageId,
          parse_mode: "MarkdownV2",
        }
      );

      return {
        messageId: result.message_id.toString(),
        timestamp: new Date(result.date * 1000),
      };
    },
    sendMedia: async (ctx) => {
      const { account, conversation, media } = ctx;
      const bot = new Telegraf(account.token);

      switch (media.type) {
        case "image":
          return bot.telegram.sendPhoto(conversation.id, media.url);
        case "video":
          return bot.telegram.sendVideo(conversation.id, media.url);
        case "file":
          return bot.telegram.sendDocument(conversation.id, media.url);
        default:
          throw new Error(`Unsupported media type: ${media.type}`);
      }
    },
  },

  // 网关适配器
  gateway: {
    startAccount: async (ctx) => {
      const { account, onMessage } = ctx;
      const bot = new Telegraf(account.token);

      // 消息处理器
      bot.on("message", async (tgMsg) => {
        const message = convertTelegramMessage(tgMsg);
        await onMessage(message);
      });

      // 启动轮询
      await bot.launch();
      return bot;
    },
    stopAccount: async (ctx) => {
      const { connection } = ctx;
      await connection.stop();
    },
  },

  // Mention 适配器
  mentions: {
    resolveMentionText: (params) => {
      const { account } = params;
      return `@${account.username}`;
    },
    resolveMentionMarkdown: (params) => {
      const { account } = params;
      return `[${account.displayName}](tg://user?id=${account.id})`;
    },
  },

  // 群组适配器
  groups: {
    resolveRequireMention: (params) => {
      const { conversation } = params;
      // 群聊需要 @bot
      return conversation.type === "group";
    },
    resolveToolPolicy: (params) => {
      return {
        requireConfirmation: ["shell", "file_write"],
        autoApprove: ["read_file", "search"],
      };
    },
  },

  // Agent 提示词适配器
  agentPrompt: {
    buildSystemPrompt: (params) => {
      const { agentPersonality } = params;
      return `${agentPersonality}\n\nYou are chatting via Telegram. ` +
        `You can use Markdown formatting. ` +
        `For code blocks, use triple backticks with language identifier.`;
    },
  },
});
```

### 渠道注册表

```typescript
// src/channels/registry.ts
export const CHAT_CHANNEL_ORDER = [
  "telegram",
  "whatsapp",
  "discord",
  "irc",
  "googlechat",
  "slack",
  "signal",
  "imessage",
  "line",
] as const;

export type ChatChannelId = (typeof CHAT_CHANNEL_ORDER)[number];

const CHAT_CHANNEL_META: Record<ChatChannelId, ChannelMeta> = {
  telegram: {
    id: "telegram",
    label: "Telegram",
    selectionLabel: "Telegram (Bot API)",
    detailLabel: "Telegram Bot",
    docsPath: "/channels/telegram",
    blurb: "Simplest way to get started. Fast and reliable.",
    systemImage: "paperplane",
    recommended: true,
  },
  whatsapp: {
    id: "whatsapp",
    label: "WhatsApp",
    selectionLabel: "WhatsApp (Web)",
    detailLabel: "WhatsApp via whatsapp-web.js",
    docsPath: "/channels/whatsapp",
    blurb: "Connect through WhatsApp Web. Requires QR scan.",
    systemImage: "phone",
  },
  discord: {
    id: "discord",
    label: "Discord",
    selectionLabel: "Discord (Gateway)",
    detailLabel: "Discord Bot",
    docsPath: "/channels/discord",
    blurb: "Full Discord bot integration with slash commands.",
    systemImage: "discord",
  },
  // ... 其他渠道
};

// 加载所有渠道 dock
export function loadChannelDocks(): Record<ChatChannelId, ChannelDock> {
  return {
    telegram: telegramDock,
    whatsapp: whatsappDock,
    discord: discordDock,
    irc: ircDock,
    googlechat: googlechatDock,
    slack: slackDock,
    signal: signalDock,
    imessage: imessageDock,
    line: lineDock,
  };
}
```

---

## opencode Provider 扩展架构

### 架构定位

opencode 的 Provider 架构专注于 **AI 模型提供商**的抽象，而非消息渠道适配。

```
┌─────────────────────────────────────────────────────────────┐
│                    Provider Registry                        │
│  ┌─────────────────────────────────────────────────────────┐│
│  │  - anthropic                                            ││
│  │  - openai                                               ││
│  │  - google                                               ││
│  │  - azure                                                ││
│  │  - bedrock                                              ││
│  │  - groq                                                 ││
│  │  - mistral                                              ││
│  │  - ...                                                  ││
│  └─────────────────────────────────────────────────────────┘│
└──────────────┬──────────────────────────────────────────────┘
               │ 统一 ProviderSdk 接口
               ▼
┌─────────────────────────────────────────────────────────────┐
│                    ProviderSdk                              │
│  ┌─────────────────────────────────────────────────────────┐│
│  │  - chat(): Stream<ChatChunk>                            ││
│  │  - complete(): Completion                               ││
│  │  - embed(): Embedding                                   ││
│  │  - listModels(): Model[]                                ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### Provider 注册机制

```typescript
// packages/opencode/src/provider/provider.ts
export interface ProviderSdk {
  chat(params: ChatParams): AsyncIterable<ChatChunk>;
  complete?(params: CompleteParams): Promise<Completion>;
  embed?(params: EmbedParams): Promise<Embedding>;
  listModels?(): Promise<Model[]>;
}

export class Provider {
  private static providers: Array<{ name: string; sdk: ProviderSdk }> = [];

  static async get(name: string, opts?: ProviderGetOpts): Promise<ProviderSdk> {
    const p = Provider.providers.find((p) => p.name === name);
    if (!p) throw new NoSuchProviderError(name);

    // 延迟初始化
    if (typeof p.sdk === "function") {
      p.sdk = await p.sdk(opts);
    }
    return p.sdk;
  }

  static async all(): Promise<ProviderSdk[]> {
    const providers = Provider.providers.map((p) => Provider.get(p.name));
    return Promise.all(providers);
  }

  static register(name: string, sdk: ProviderSdk | ProviderFactory): void {
    Provider.providers.push({ name, sdk: sdk as ProviderSdk });
  }
}

// 注册内置 providers
Provider.register("anthropic", anthropicProvider);
Provider.register("openai", openaiProvider);
Provider.register("google", googleProvider);
// ...
```

### 多接口支持（非渠道适配）

```typescript
// packages/opencode/src/index.ts
let cli = yargs(hideBin(process.argv))
  .command(RunCommand)           // 运行任务
  .command(GenerateCommand)      // 代码生成
  .command(DebugCommand)         // 调试
  .command(ServeCommand)         // HTTP Server
  .command(WebCommand)           // Web UI
  .command(AcpCommand)           // ACP Protocol
  .command(McpCommand)           // MCP Protocol
  .command(TuiThreadCommand)     // Terminal UI
  .command(ConfigCommand)        // 配置管理
  .command(InstallCommand)       // 安装
  .command(UpgradeCommand);      // 升级
```

---

## 架构对比与推荐

### 四项目架构对比

| 维度 | CoPaw | kimi-cli | openclaw | opencode |
|------|-------|----------|----------|----------|
| **定位** | 多平台 AI 助手 | 本地 CLI 工具 | 多平台 AI 助手 | AI 开发助手 |
| **支持渠道** | 11种（飞书/钉钉/QQ等） | 仅 CLI | 9种（Telegram/WhatsApp等） | CLI/Web/API |
| **适配架构** | Class 继承 + Protocol | 无 | Adapter 组合模式 | Provider 模式 |
| **消息抽象** | AgentRequest/AgentResponse | WireMessage | 多类型 Adapter | 无 |
| **队列机制** | asyncio.Queue + 多 Worker | BroadcastQueue | 插件运行时 | 无 |
| **连接方式** | WebSocket/Webhook/HTTP | 本地进程 | 长连接/轮询 | 本地/HTTP |
| **身份认证** | 渠道独立配置 | OAuth + API Key | 渠道独立配置 | OAuth + Token |
| **扩展机制** | 动态加载 custom_channels | 插件扩展 | npm 插件系统 | Provider 注册 |

### 消息抽象层对比

```python
# CoPaw: 统一消息模型
AgentRequest = {
    content: List[ContentPart],
    sender: SenderInfo,
    session_id: str,
    channel_address: ChannelAddress(kind, id, extra),
    metadata: Dict,
}

# kimi-cli: 本地事件流
WireMessage = TurnBegin | ContentPart | ToolCall | ToolResult | TurnEnd

# openclaw: 渠道特定类型
Message = {
    conversation: Conversation,
    sender: Sender,
    content: TextContent | MediaContent | PollContent,
    threading?: ThreadInfo,
}
```

### 推荐架构

基于四个项目的最佳实践，推荐以下分层架构：

```
┌─────────────────────────────────────────────────────────────┐
│                    外部消息渠道层                            │
│  飞书(WS)  钉钉(Stream)  QQ(HTTP)  Discord(Gateway) ...     │
└────────────┬────────────┬──────────┬────────────────────────┘
             │            │          │
             ▼            ▼          ▼
┌─────────────────────────────────────────────────────────────┐
│                    Protocol Adapter 层                       │
│  ┌─────────────────────────────────────────────────────────┐│
│  │  NativeMessageConverter                                 ││
│  │  - 协议解析 (飞书Card/钉钉Markdown/QQ XML)               ││
│  │  - 身份验证 (Token/AppKey/SessionWebhook)              ││
│  │  - 媒体处理 (下载/上传/格式转换)                         ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    统一内部协议层                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │AgentRequest │  │ ContentPart │  │   ChannelAddress    │ │
│  │ - message   │  │ - text      │  │  - kind (dm/group)  │ │
│  │ - sender    │  │ - image     │  │  - id               │ │
│  │ - metadata  │  │ - file      │  │  - extra (webhook)  │ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Channel Manager 层                        │
│  ┌─────────────────────────────────────────────────────────┐│
│  │  - 队列管理 (asyncio.Queue per channel)                  ││
│  │  - 并发控制 (worker pool)                                ││
│  │  - 会话防抖 (session debouncing)                         ││
│  │  - 负载均衡 (round-robin)                                ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Agent 核心处理层                          │
│              LLM 调用 / 工具执行 / 记忆管理                   │
└─────────────────────────────────────────────────────────────┘
```

### 关键设计建议

1. **Adapter 模式**: 采用 openclaw 的组合式 Adapter 而非继承
   - 每个渠道选择性实现需要的 Adapter 接口
   - 避免强制实现不必要的方法

2. **消息抽象**: 采用 CoPaw 的 AgentRequest/AgentResponse
   - 统一的内容类型系统（Text/Image/Video/File）
   - ChannelAddress 统一路由

3. **队列管理**: 采用 CoPaw 的 ChannelManager
   - 每渠道独立队列
   - 多 worker 并发
   - 会话防抖

4. **连接管理**: 根据渠道特性选择
   - WebSocket: 飞书、Discord
   - Stream: 钉钉
   - HTTP Polling: QQ
   - Webhook: 回调处理

5. **扩展机制**: 支持动态加载
   - 内置渠道注册表
   - custom_channels/ 目录热加载
   - npm/pip 插件系统

---

## 附录：关键代码文件汇总

| 项目 | 关键文件 | 说明 |
|------|----------|------|
| **CoPaw** | `channels/base.py` | BaseChannel 抽象基类 |
| **CoPaw** | `channels/schema.py` | ChannelAddress 统一路由 |
| **CoPaw** | `channels/manager.py` | ChannelManager 队列管理 |
| **CoPaw** | `channels/registry.py` | 渠道注册与动态加载 |
| **CoPaw** | `channels/feishu/` | 飞书渠道实现 |
| **CoPaw** | `channels/dingtalk/` | 钉钉渠道实现 |
| **CoPaw** | `channels/qq/` | QQ 渠道实现 |
| **kimi-cli** | `wire/__init__.py` | Wire SPMC 通信 |
| **kimi-cli** | `wire/types.py` | WireMessage 类型 |
| **kimi-cli** | `wire/queue.py` | BroadcastQueue |
| **openclaw** | `channels/plugins/types.core.ts` | 核心类型 |
| **openclaw** | `channels/plugins/types.adapters.ts` | Adapter 接口 |
| **openclaw** | `channels/dock.ts` | ChannelDock 组合 |
| **openclaw** | `channels/registry.ts` | 渠道注册表 |
| **opencode** | `provider/provider.ts` | Provider 管理 |

---

*报告生成时间: 2025-03-13*
*分析项目: CoPaw, kimi-cli, openclaw, opencode*
