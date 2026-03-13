# AI Agent Model Provider 抽象层与多模型路由机制深度调研报告

## 概述

本报告对四个开源 AI Agent 项目（CoPaw、kimi-cli、openclaw、opencode）的 Model Provider 抽象层与多模型路由机制进行深度技术分析，对比各自的 Provider 抽象设计、多模型配置、负载均衡、Fallback 机制、Streaming 实现和成本追踪。

---

## 一、各项目 Provider 架构概览

### 架构对比表

| 维度 | CoPaw | kimi-cli | openclaw | opencode |
|------|-------|----------|----------|----------|
| **抽象层** | AgentScope + 自定义 | kosong (Protocol) | Pi Agent | Vercel AI SDK |
| **语言** | Python | Python | TypeScript | TypeScript |
| **配置格式** | JSON | TOML | JSON | JSON/JSONC |
| **内置 Provider** | 10+ | 6+ | 20+ | 15+ |
| **本地模型** | llama.cpp, MLX, Ollama | Ollama (via OpenAI) | Ollama | Ollama |
| **Streaming** | AsyncGenerator | AsyncIterator | Pi Events | Vercel Streams |
| **成本追踪** | TokenUsageManager | TokenUsage class | Usage in meta | Built-in cost |
| **Fallback** | RetryChatModel | 手动重试 | 自动重试 | 自动重试 |

---

## 二、各项目 Provider 详解

### 1. CoPaw - AgentScope + 自定义 Provider 架构

#### 核心架构

```
┌─────────────────────────────────────────────────────────────────┐
│                     CoPaw Provider Stack                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Application Layer                                        │   │
│  │  - ProviderManager (Singleton)                            │   │
│  │  - TokenUsageManager                                      │   │
│  │  - RoutingChatModel                                       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│  ┌───────────────────────────┼───────────────────────────────┐ │
│  │                           ▼                               │ │
│  │  ┌─────────────────────────────────────────────────────┐ │ │
│  │  │  Provider Abstraction Layer                         │ │ │
│  │  │  - Provider (ABC)                                   │ │ │
│  │  │  - OpenAIProvider                                   │ │ │
│  │  │  - AnthropicProvider                                │ │ │
│  │  │  - OllamaProvider                                   │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  │                           │                               │ │
│  │                           ▼                               │ │
│  │  ┌─────────────────────────────────────────────────────┐ │ │
│  │  │  ChatModel Layer (AgentScope)                       │ │ │
│  │  │  - OpenAIChatModel                                  │ │ │
│  │  │  - AnthropicChatModel                               │ │ │
│  │  │  - LocalChatModel                                   │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  │                           │                               │ │
│  │                           ▼                               │ │
│  │  ┌─────────────────────────────────────────────────────┐ │ │
│  │  │  Wrapper Layer                                      │ │ │
│  │  │  - TokenRecordingModelWrapper                       │ │ │
│  │  │  - RetryChatModel                                   │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────────────────┘ │
│                              │                                  │
│  ┌───────────────────────────┼───────────────────────────────┐ │
│  │                           ▼                               │ │
│  │  ┌─────────────────────────────────────────────────────┐ │ │
│  │  │  Storage Layer                                      │ │ │
│  │  │  - providers/ (builtin + custom)                    │ │ │
│  │  │  - active_model.json                                │ │ │
│  │  │  - token_usage/                                     │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### Provider 抽象接口

```python
# src/copaw/providers/provider.py
class Provider(ProviderInfo, ABC):
    """Represents a provider instance with its configuration."""

    @abstractmethod
    async def check_connection(self, timeout: float = 5) -> tuple[bool, str]:
        """Check if the provider is reachable."""

    @abstractmethod
    async def fetch_models(self, timeout: float = 5) -> List[ModelInfo]:
        """Fetch available models from the provider."""

    @abstractmethod
    def get_chat_model_instance(self, model_id: str) -> ChatModelBase:
        """Return a ChatModel instance for this provider and model."""
```

#### Provider 信息模型

```python
class ProviderInfo(BaseModel):
    id: str                          # Provider 标识符
    name: str                        # 人类可读名称
    base_url: str                    # API 基础 URL
    api_key: str                     # API 密钥
    chat_model: str                  # AgentScope ChatModel 类名
    models: List[ModelInfo]          # 预定义模型列表
    extra_models: List[ModelInfo]    # 用户添加的模型
    is_local: bool                   # 是否为本地托管
    require_api_key: bool            # 是否需要 API 密钥
    support_model_discovery: bool    # 是否支持模型发现
```

#### 内置 Provider 列表

| Provider ID | 类型 | Base URL | 特点 |
|-------------|------|----------|------|
| `openai` | OpenAIProvider | https://api.openai.com/v1 | 官方 API |
| `anthropic` | AnthropicProvider | https://api.anthropic.com | Claude 系列 |
| `dashscope` | OpenAIProvider | https://dashscope.aliyuncs.com | 阿里云 |
| `modelscope` | OpenAIProvider | https://api-inference.modelscope.cn | 魔搭社区 |
| `ollama` | OllamaProvider | http://localhost:11434 | 本地模型 |
| `lmstudio` | OpenAIProvider | http://localhost:1234/v1 | LM Studio |
| `llamacpp` | DefaultProvider | - | llama.cpp 本地 |
| `mlx` | DefaultProvider | - | Apple Silicon 本地 |

#### ProviderManager - 核心管理器

```python
# src/copaw/providers/provider_manager.py
class ProviderManager:
    _instance = None

    def __init__(self):
        self.builtin_providers: Dict[str, Provider] = {}
        self.custom_providers: Dict[str, Provider] = {}
        self.active_model: ModelSlotConfig | None = None
        self._init_builtins()
        self._init_from_storage()

    async def activate_model(self, provider_id: str, model_id: str):
        """Set the active provider and model."""
        self.active_model = ModelSlotConfig(
            provider_id=provider_id,
            model=model_id,
        )
        self.save_active_model(self.active_model)

    @staticmethod
    def get_active_chat_model() -> ChatModelBase:
        """Get currently active ChatModel instance."""
        model = manager.get_active_model()
        provider = manager.get_provider(model.provider_id)

        if provider.is_local:
            return create_local_chat_model(model.model)
        return provider.get_chat_model_instance(model.model)
```

#### Fallback 与重试机制

```python
# src/copaw/providers/retry_chat_model.py
class RetryChatModel(ChatModelBase):
    """Transparent retry wrapper around any ChatModelBase."""

    async def __call__(self, *args, **kwargs):
        retries = LLM_MAX_RETRIES  # 默认 3 次

        for attempt in range(1, retries + 1):
            try:
                return await self._inner(*args, **kwargs)
            except Exception as exc:
                if not _is_retryable(exc) or attempt >= retries:
                    raise
                delay = _compute_backoff(attempt)  # 指数退避
                await asyncio.sleep(delay)

RETRYABLE_STATUS_CODES = {429, 500, 502, 503, 504}

def _is_retryable(exc: Exception) -> bool:
    retryable = _get_openai_retryable() + _get_anthropic_retryable()
    if isinstance(exc, retryable):
        return True
    status = getattr(exc, "status_code", None)
    return status in RETRYABLE_STATUS_CODES
```

#### Token 计费与成本追踪

```python
# src/copaw/token_usage/manager.py
class TokenUsageManager:
    async def record(
        self,
        provider_id: str,
        model_name: str,
        prompt_tokens: int,
        completion_tokens: int,
        at_date: date | None = None,
    ) -> None:
        """Record token usage for a given provider, model and date."""
        composite_key = f"{provider_id}:{model_name}"

        with self._file_lock:
            data = await self._load_data()
            if date_str not in data:
                data[date_str] = {}

            by_key = data[date_str]
            if composite_key not in by_key:
                by_key[composite_key] = {
                    "provider_id": provider_id,
                    "model_name": model_name,
                    "prompt_tokens": 0,
                    "completion_tokens": 0,
                    "call_count": 0,
                }

            entry = by_key[composite_key]
            entry["prompt_tokens"] += prompt_tokens
            entry["completion_tokens"] += completion_tokens
            entry["call_count"] += 1

            await self._save_data(data)
```

#### 本地/云端路由

```python
# src/copaw/agents/routing_chat_model.py
class RoutingChatModel(ChatModelBase):
    """Routes between local and cloud slots."""

    def __init__(
        self,
        local_endpoint: RoutingEndpoint,
        cloud_endpoint: RoutingEndpoint,
        routing_cfg: AgentsLLMRoutingConfig,
    ):
        self.local_endpoint = local_endpoint
        self.cloud_endpoint = cloud_endpoint
        self.routing_cfg = routing_cfg
        self.policy = RoutingPolicy(routing_cfg)

    async def __call__(self, messages: list[dict], ...):
        text = " ".join(
            message["content"] for message in messages
            if message.get("role") == "user"
        )
        decision = self.policy.decide(
            text=text,
            tools_available=tools is not None
        )

        endpoint = (
            self.local_endpoint
            if decision.route == "local"
            else self.cloud_endpoint
        )

        return await endpoint.model(...)
```

---

### 2. kimi-cli - kosong Protocol 架构

#### 核心架构

```
┌─────────────────────────────────────────────────────────────────┐
│                    kimi-cli kosong Architecture                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Application Layer                                        │   │
│  │  - Agent                                                  │   │
│  │  - KimiSoul                                               │   │
│  │  - LaborMarket                                            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│  ┌───────────────────────────┼───────────────────────────────┐ │
│  │                           ▼                               │ │
│  │  ┌─────────────────────────────────────────────────────┐ │ │
│  │  │  kosong Library                                     │ │ │
│  │  │                                                     │ │ │
│  │  │  ┌─────────────────────────────────────────────┐   │ │ │
│  │  │  │ ChatProvider (Protocol)                     │   │ │ │
│  │  │  │ - generate()                                │   │ │ │
│  │  │  │ - model_name                                │   │ │ │
│  │  │  │ - thinking_effort                           │   │ │ │
│  │  │  └─────────────────────────────────────────────┘   │ │ │
│  │  │                          │                          │ │ │
│  │  │  ┌───────────────────────┼───────────────────────┐ │ │ │
│  │  │  │                       ▼                       │ │ │ │
│  │  │  │  ┌─────────────────────────────────────────┐ │ │ │ │
│  │  │  │  │ Implementations                         │ │ │ │ │
│  │  │  │  │ - KimiChatProvider                      │ │ │ │ │
│  │  │  │  │ - OpenAILegacyChatProvider              │ │ │ │ │
│  │  │  │  │ - OpenAIResponsesChatProvider           │ │ │ │ │
│  │  │  │  │ - AnthropicChatProvider                 │ │ │ │ │
│  │  │  │  │ - GeminiChatProvider                    │ │ │ │ │
│  │  │  │  │ - VertexAIChatProvider                  │ │ │ │ │
│  │  │  │  └─────────────────────────────────────────┘ │ │ │ │
│  │  │  └─────────────────────────────────────────────┘   │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────────────────┘ │
│                              │                                  │
│  ┌───────────────────────────┼───────────────────────────────┐ │
│  │                           ▼                               │ │
│  │  ┌─────────────────────────────────────────────────────┐ │ │
│  │  │  Configuration (TOML)                               │ │ │
│  │  │  - agent-spec.toml                                  │ │ │
│  │  │  - providers configuration                          │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### kosong ChatProvider Protocol

```python
# packages/kosong/src/kosong/chat_provider/__init__.py
@runtime_checkable
class ChatProvider(Protocol):
    """The interface of chat providers."""
    name: str

    @property
    def model_name(self) -> str: ...

    @property
    def thinking_effort(self) -> "ThinkingEffort | None": ...

    async def generate(
        self,
        system_prompt: str,
        tools: Sequence[Tool],
        history: Sequence[Message],
    ) -> "StreamedMessage": ...

    def with_thinking(self, effort: ThinkingEffort) -> Self: ...
```

#### 配置示例 (TOML)

```toml
# agent-spec.toml
[providers.kimi-for-coding]
type = "kimi"
base_url = "https://api.kimi.com/coding/v1"
api_key = "sk-xxx"

[providers.openai]
type = "openai_legacy"
base_url = "https://api.openai.com/v1"
api_key = "sk-xxx"

[providers.anthropic]
type = "anthropic"
base_url = "https://api.anthropic.com"
api_key = "sk-ant-xxx"

[providers.gemini]
type = "gemini"
api_key = "xxx"
```

#### 支持的 Provider Types

| Type | Provider | API |
|------|----------|-----|
| `kimi` | Kimi API | Custom |
| `openai_legacy` | OpenAI | Chat Completions |
| `openai_responses` | OpenAI | Responses API |
| `anthropic` | Anthropic Claude | Messages API |
| `gemini` | Google Gemini | Generative AI |
| `vertexai` | Google Vertex AI | Enterprise |

#### Streaming 实现

```python
# packages/kosong/src/kosong/chat_provider/kimi.py
class KimiStreamedMessage:
    def __aiter__(self) -> AsyncIterator[StreamedMessagePart]:
        return self

    async def __anext__(self) -> StreamedMessagePart:
        return await self._iter.__anext__()

    async def _convert_stream_response(
        self,
        response: AsyncIterator[ChatCompletionChunk],
    ) -> AsyncIterator[StreamedMessagePart]:
        async for chunk in response:
            delta = chunk.choices[0].delta
            if delta.content:
                yield TextPart(text=delta.content)
            if delta.tool_calls:
                for tc in delta.tool_calls:
                    yield ToolCallPart(...)
```

#### 工具集成

```python
# packages/kosong/src/kosong/tooling/__init__.py
class Tool(BaseModel):
    name: str
    description: str
    parameters: ParametersType  # JSON Schema

class CallableTool2[Params: BaseModel](ABC):
    name: str
    description: str
    params: type[Params]

    async def call(self, arguments: JsonType) -> ToolReturnValue: ...
```

---

### 3. openclaw - Pi Agent + ModelRef 架构

#### 核心架构

```
┌─────────────────────────────────────────────────────────────────┐
│                   openclaw Model Architecture                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Application Layer                                        │   │
│  │  - Agent                                                  │   │
│  │  - SubagentRegistry                                       │   │
│  │  - ModelResolver                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│  ┌───────────────────────────┼───────────────────────────────┐ │
│  │                           ▼                               │ │
│  │  ┌─────────────────────────────────────────────────────┐ │ │
│  │  │  Model Selection Layer                              │ │ │
│  │  │                                                     │ │ │
│  │  │  ┌─────────────────────────────────────────────┐   │ │ │
│  │  │  │ ModelRef                                      │   │ │ │
│  │  │  │ - provider: string                            │   │ │ │
│  │  │  │ - model: string                               │   │ │ │
│  │  │  │                                               │   │ │ │
│  │  │  │ parseModelRef("anthropic/claude-3-opus")      │   │ │ │
│  │  │  │ -> { provider: "anthropic", model: "claude-3-opus" }│ │ │
│  │  │  └─────────────────────────────────────────────┘   │ │ │
│  │  │                                                     │ │ │
│  │  │  ┌─────────────────────────────────────────────┐   │ │ │
│  │  │  │ Model Resolution                              │   │ │ │
│  │  │  │ - resolveDefaultModelForAgent()               │   │ │ │
│  │  │  │ - resolveSubagentSpawnModelSelection()        │   │ │ │
│  │  │  │ - normalizeModelSelection()                   │   │ │ │
│  │  │  └─────────────────────────────────────────────┘   │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────────────────┘ │
│                              │                                  │
│  ┌───────────────────────────┼───────────────────────────────┐ │
│  │                           ▼                               │ │
│  │  ┌─────────────────────────────────────────────────────┐ │ │
│  │  │  Pi Agent Layer                                     │ │ │
│  │  │  - Pi Embedded Runner                               │ │ │
│  │  │  - Streaming Wrappers                               │ │ │
│  │  │  - Tool Definitions                                 │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────────────────┘ │
│                              │                                  │
│  ┌───────────────────────────┼───────────────────────────────┐ │
│  │                           ▼                               │ │
│  │  ┌─────────────────────────────────────────────────────┐ │ │
│  │  │  Configuration (models.json)                        │ │ │
│  │  │  - 20+ built-in providers                           │ │ │
│  │  │  - Auth profiles                                    │ │ │
│  │  │  - Custom providers                                 │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### ModelRef 解析

```typescript
// src/agents/model-selection.ts
export type ModelRef = {
  provider: string;
  model: string;
};

export function parseModelRef(raw: string, defaultProvider: string): ModelRef | null {
  const trimmed = raw.trim();
  const slash = trimmed.indexOf("/");

  if (slash === -1) {
    // No provider specified, use default
    return normalizeModelRef(defaultProvider, trimmed);
  }

  const providerRaw = trimmed.slice(0, slash).trim();
  const model = trimmed.slice(slash + 1).trim();
  return normalizeModelRef(providerRaw, model);
}

// Usage: parseModelRef("anthropic/claude-3-opus", "openai")
// -> { provider: "anthropic", model: "claude-3-opus" }
```

#### 支持的 Providers (20+)

| Provider | Type | Features |
|----------|------|----------|
| GitHub Copilot | copilot | IDE integration |
| Anthropic | anthropic | Claude series |
| Amazon Bedrock | bedrock | AWS models |
| Google Gemini | google | Gemini Pro/Ultra |
| Google Vertex AI | vertexai | Enterprise |
| OpenAI | openai | GPT-4/o1 series |
| OpenRouter | openrouter | Multi-provider |
| Ollama | ollama | Local models |
| Cloudflare AI | cloudflare | Edge deployment |
| Vercel AI | vercel | Serverless |

#### 子 Agent 模型继承

```typescript
// src/agents/model-selection.ts
export function resolveSubagentSpawnModelSelection(params: {
  cfg: OpenClawConfig;
  agentId: string;
  modelOverride?: unknown;
}): string {
  const runtimeDefault = resolveDefaultModelForAgent({
    cfg: params.cfg,
    agentId: params.agentId,
  });

  return (
    // 1. Explicit override from spawn call
    normalizeModelSelection(params.modelOverride) ??
    // 2. Configured subagent model
    resolveSubagentConfiguredModelSelection({
      cfg: params.cfg,
      agentId: params.agentId,
    }) ??
    // 3. Default model from agent config
    normalizeModelSelection(
      resolveAgentModelPrimaryValue(params.cfg.agents?.defaults?.model)
    ) ??
    // 4. Runtime default
    `${runtimeDefault.provider}/${runtimeDefault.model}`
  );
}
```

#### Pi Agent Streaming

```typescript
// src/agents/pi-embedded-subscribe.ts
export function subscribeEmbeddedPiSession(params: {
  sessionManager: SessionManager;
  onMessage: (message: AgentMessage) => void;
  onError: (error: Error) => void;
  onComplete: () => void;
}): Subscription {
  // Handles streaming message events from Pi agent
  const subscription = sessionManager.subscribe({
    next: (event) => {
      switch (event.type) {
        case "assistant.messageDelta":
          onMessage({
            role: "assistant",
            content: event.delta,
          });
          break;
        case "assistant.toolCall":
          onMessage({
            role: "assistant",
            tool_calls: [event.toolCall],
          });
          break;
      }
    },
  });

  return subscription;
}
```

---

### 4. opencode - Vercel AI SDK 架构

#### 核心架构

```
┌─────────────────────────────────────────────────────────────────┐
│                  opencode Vercel AI SDK Architecture            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Application Layer                                        │   │
│  │  - Session                                                │   │
│  │  - Agent                                                  │   │
│  │  - SessionProcessor                                       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│  ┌───────────────────────────┼───────────────────────────────┐ │
│  │                           ▼                               │ │
│  │  ┌─────────────────────────────────────────────────────┐ │ │
│  │  │  Provider SDK Layer                                 │ │ │
│  │  │                                                     │ │ │
│  │  │  ┌─────────────────────────────────────────────┐   │ │ │
│  │  │  │ Vercel AI SDK Providers                       │   │ │ │
│  │  │  │ - @ai-sdk/openai                              │   │ │ │
│  │  │  │ - @ai-sdk/anthropic                           │   │ │ │
│  │  │  │ - @ai-sdk/google                              │   │ │ │
│  │  │  │ - @ai-sdk/amazon-bedrock                      │   │ │ │
│  │  │  │ - @ai-sdk/mistral                             │   │ │ │
│  │  │  │ - @ai-sdk/groq                                │   │ │ │
│  │  │  │ - @openrouter/ai-sdk-provider                 │   │ │ │
│  │  │  │ - ... (15+ providers)                         │   │ │ │
│  │  │  └─────────────────────────────────────────────┘   │ │ │
│  │  │                                                     │ │ │
│  │  │  ┌─────────────────────────────────────────────┐   │ │ │
│  │  │  │ Custom Implementations                        │   │ │ │
│  │  │  │ - GitHub Copilot Provider                     │   │ │ │
│  │  │  │ - OpenAI-Compatible Provider                  │   │ │ │
│  │  │  │ - OpenAI Responses Provider                   │   │ │ │
│  │  │  └─────────────────────────────────────────────┘   │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────────────────┘ │
│                              │                                  │
│  ┌───────────────────────────┼───────────────────────────────┐ │
│  │                           ▼                               │ │
│  │  ┌─────────────────────────────────────────────────────┐ │ │
│  │  │  LanguageModelV2 Interface                          │ │ │
│  │  │  - doGenerate()                                     │ │ │
│  │  │  - doStream()                                       │ │ │
│  │  │  - specificationVersion: "v2"                       │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────────────────┘ │
│                              │                                  │
│  ┌───────────────────────────┼───────────────────────────────┐ │
│  │                           ▼                               │ │
│  │  ┌─────────────────────────────────────────────────────┐ │ │
│  │  │  Configuration Layer                                │ │ │
│  │  │  - opencode.json                                    │ │ │
│  │  │  - Remote .well-known/opencode                      │ │ │
│  │  │  - Environment variables                            │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### Provider Factory

```typescript
// packages/opencode/src/provider/provider.ts
export async function fromConfig(config: Config.Info): Promise<Provider> {
  const model = await getModel(config)
  const client = await getClient(config)

  return {
    chat: {
      model: client,
      // Model capabilities and metadata
    },
    // ...
  }
}

async function getClient(config: Config.Info) {
  switch (config.provider) {
    case "openai":
      return createOpenAI({ apiKey: config.apiKey })(config.model)
    case "anthropic":
      return createAnthropic({ apiKey: config.apiKey })(config.model)
    case "google":
      return createGoogleGenerativeAI({ apiKey: config.apiKey })(config.model)
    case "bedrock":
      return createAmazonBedrock({...})(config.model)
    // ... 15+ providers
  }
}
```

#### Model Definition with Cost

```typescript
// packages/opencode/src/provider/models.ts
export const Model = z.object({
  id: z.string(),
  name: z.string(),
  cost: z.object({
    input: z.number(),           // Input token cost per 1M
    output: z.number(),          // Output token cost per 1M
    cache_read: z.number().optional(),
    cache_write: z.number().optional(),
    context_over_200k: z.object({
      input: z.number(),
      output: z.number(),
    }).optional(),
  }).optional(),
  limit: z.object({
    context: z.number(),         // Context window size
    input: z.number().optional(),
    output: z.number(),
  }),
  // Capabilities
  tool_call: z.boolean(),
  reasoning: z.boolean(),
  attachment: z.boolean(),
})
```

#### Streaming with Vercel AI SDK

```typescript
// packages/opencode/src/session/processor.ts
const stream = await LLM.stream(streamInput)

for await (const value of stream.fullStream) {
  switch (value.type) {
    case "start":
      SessionStatus.set(input.sessionID, { type: "busy" })
      break
    case "reasoning-start":
      // Handle reasoning start
      break
    case "reasoning-delta":
      // Stream reasoning content
      break
    case "tool-call":
      // Handle tool call
      await handleToolCall(value)
      break
    case "tool-result":
      // Handle tool result
      await handleToolResult(value)
      break
    case "finish":
      // Complete
      return
  }
}
```

#### OpenAI-Compatible Provider

```typescript
// packages/opencode/src/provider/sdk/copilot/copilot-provider.ts
export interface OpenaiCompatibleProviderSettings {
  apiKey?: string
  baseURL?: string
  name?: string
  headers?: Record<string, string>
  fetch?: FetchFunction
}

export function createOpenaiCompatible(
  options: OpenaiCompatibleProviderSettings = {}
): OpenaiCompatibleProvider {
  const baseURL = withoutTrailingSlash(
    options.baseURL ?? "https://api.openai.com/v1"
  )

  const createChatModel = (modelId: OpenaiCompatibleModelId) => {
    return new OpenAICompatibleChatLanguageModel(modelId, {
      provider: `${options.name ?? "openai-compatible"}.chat`,
      headers: getHeaders,
      url: ({ path }) => `${baseURL}${path}`,
      fetch: options.fetch,
    })
  }

  return {
    chat: createChatModel,
    // ...
  }
}
```

---

## 三、Streaming 实现对比

| 项目 | 实现方式 | 事件类型 | 特点 |
|------|---------|---------|------|
| **CoPaw** | AgentScope AsyncGenerator | ChatResponse | 与 AgentScope 深度集成 |
| **kimi-cli** | kosong AsyncIterator | StreamedMessagePart | 协议化设计 |
| **openclaw** | Pi Events | messageDelta, toolCall | Pi Agent 原生 |
| **opencode** | Vercel AI SDK | fullStream | 标准化事件类型 |

### 事件类型对比

```python
# CoPaw (AgentScope)
ChatResponse(
    content=[{"type": "text", "text": "..."}],
    usage=ChatUsage(input_tokens=10, output_tokens=20)
)

# kimi-cli (kosong)
StreamedMessagePart = TextPart | ToolCallPart | ReasoningPart

# openclaw (Pi)
event.type = "assistant.messageDelta" | "assistant.toolCall" | "assistant.finish"

# opencode (Vercel AI SDK)
value.type = "start" | "reasoning-start" | "reasoning-delta" | "tool-call" | "finish"
```

---

## 四、成本追踪对比

| 项目 | 追踪粒度 | 存储方式 | 特色功能 |
|------|---------|---------|---------|
| **CoPaw** | Provider + Model + Date | JSON 文件 | TokenUsageManager，多维度聚合 |
| **kimi-cli** | Model level | 内存统计 | TokenUsage class |
| **openclaw** | Usage in metadata | Session storage | Pi Agent 内置 |
| **opencode** | Model config | SQLite | Cost field 在 Model schema 中 |

### CoPaw 成本追踪详情

```python
class TokenUsageSummary(BaseModel):
    """Aggregated token usage summary."""

    total_prompt_tokens: int
    total_completion_tokens: int
    total_calls: int
    by_model: dict[str, TokenUsageByModel]      # 按模型聚合
    by_provider: dict[str, TokenUsageStats]     # 按 Provider 聚合
    by_date: dict[str, TokenUsageStats]         # 按日期聚合
```

### opencode 成本定义

```typescript
const Model = z.object({
  cost: z.object({
    input: z.number(),              // per 1M tokens
    output: z.number(),             // per 1M tokens
    cache_read: z.number().optional(),
    cache_write: z.number().optional(),
  }),
})
```

---

## 五、推荐架构

基于四个项目的最佳实践，推荐以下融合架构：

```
┌─────────────────────────────────────────────────────────────────┐
│                Recommended Provider Architecture                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Application Layer                                        │   │
│  │  - ProviderManager (Singleton)                            │   │
│  │  - ModelRouter (Local/Cloud/Subagent)                     │   │
│  │  - CostTracker                                            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│  ┌───────────────────────────┼───────────────────────────────┐ │
│  │                           ▼                               │ │
│  │  ┌─────────────────────────────────────────────────────┐ │ │
│  │  │  Provider Interface Layer                           │ │ │
│  │  │                                                     │ │ │
│  │  │  ┌─────────────────────────────────────────────┐   │ │ │
│  │  │  │ Unified Interface (Inspired by Vercel AI SDK) │   │ │ │
│  │  │  │                                               │   │ │ │
│  │  │  │ interface LanguageModel {                     │   │ │ │
│  │  │  │   doGenerate(options): Promise<Generated>     │   │ │ │
│  │  │  │   doStream(options): Promise<Stream<Chunk>>   │   │ │ │
│  │  │  │ }                                             │   │ │ │
│  │  │  └─────────────────────────────────────────────┘   │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────────────────┘ │
│                              │                                  │
│  ┌───────────────────────────┼───────────────────────────────┐ │
│  │                           ▼                               │ │
│  │  ┌─────────────────────────────────────────────────────┐ │ │
│  │  │  Provider Implementations                           │ │ │
│  │  │  - OpenAI Provider                                  │ │ │
│  │  │  - Anthropic Provider                               │ │ │
│  │  │  - Google Provider                                  │ │ │
│  │  │  - OpenAI-Compatible Provider (kimi-cli style)      │ │ │
│  │  │  - Local Provider (llama.cpp, MLX, Ollama)          │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────────────────┘ │
│                              │                                  │
│  ┌───────────────────────────┼───────────────────────────────┐ │
│  │                           ▼                               │ │
│  │  ┌─────────────────────────────────────────────────────┐ │ │
│  │  │  Wrapper Layer (CoPaw style)                        │ │ │
│  │  │  - RetryModel (exponential backoff)                 │ │ │
│  │  │  - TokenRecordingModel                              │ │ │
│  │  │  - RoutingModel (Local/Cloud)                       │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────────────────┘ │
│                              │                                  │
│  ┌───────────────────────────┼───────────────────────────────┐ │
│  │                           ▼                               │ │
│  │  ┌─────────────────────────────────────────────────────┐ │ │
│  │  │  Configuration                                      │ │ │
│  │  │  - providers.json (openclaw style)                  │ │ │
│  │  │  - active_model.json                                │ │ │
│  │  │  - token_usage/                                     │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 关键实现代码

```typescript
// Recommended Provider Interface
interface LanguageModel {
  readonly specificationVersion: "v1"
  readonly modelId: string
  readonly provider: string

  doGenerate(options: GenerateOptions): Promise<GenerateResult>
  doStream(options: StreamOptions): Promise<StreamResult>
}

interface GenerateResult {
  text: string
  toolCalls: ToolCall[]
  usage: {
    promptTokens: number
    completionTokens: number
    totalTokens: number
  }
  cost?: {
    input: number
    output: number
  }
}

// Recommended Provider Manager
class ProviderManager {
  private static instance: ProviderManager
  private providers: Map<string, Provider>
  private activeModel: ModelRef

  static getInstance(): ProviderManager {
    if (!ProviderManager.instance) {
      ProviderManager.instance = new ProviderManager()
    }
    return ProviderManager.instance
  }

  async activateModel(providerId: string, modelId: string): Promise<void> {
    const provider = this.providers.get(providerId)
    if (!provider) {
      throw new Error(`Provider ${providerId} not found`)
    }
    if (!provider.hasModel(modelId)) {
      throw new Error(`Model ${modelId} not found in provider ${providerId}`)
    }
    this.activeModel = { provider: providerId, model: modelId }
    await this.saveActiveModel()
  }

  getActiveModel(): LanguageModel {
    const { provider, model } = this.activeModel
    const providerImpl = this.providers.get(provider)
    return providerImpl.getModel(model)
  }
}

// Recommended Retry Wrapper
class RetryModel implements LanguageModel {
  constructor(
    private inner: LanguageModel,
    private maxRetries: number = 3,
    private backoffBase: number = 1000
  ) {}

  async doGenerate(options: GenerateOptions): Promise<GenerateResult> {
    for (let attempt = 1; attempt <= this.maxRetries; attempt++) {
      try {
        return await this.inner.doGenerate(options)
      } catch (error) {
        if (!isRetryableError(error) || attempt === this.maxRetries) {
          throw error
        }
        const delay = this.backoffBase * Math.pow(2, attempt - 1)
        await sleep(delay)
      }
    }
    throw new Error("Max retries exceeded")
  }

  async doStream(options: StreamOptions): Promise<StreamResult> {
    // Similar retry logic for streaming
  }
}

// Recommended Cost Tracker
class CostTracker {
  private records: TokenUsageRecord[] = []

  async record(usage: TokenUsage): Promise<void> {
    const model = await ProviderManager.getInstance().getActiveModel()
    const cost = this.calculateCost(usage, model)

    this.records.push({
      timestamp: new Date(),
      provider: model.provider,
      model: model.modelId,
      promptTokens: usage.promptTokens,
      completionTokens: usage.completionTokens,
      cost,
    })

    await this.persist()
  }

  private calculateCost(usage: TokenUsage, model: Model): number {
    if (!model.cost) return 0

    const inputCost = (usage.promptTokens / 1_000_000) * model.cost.input
    const outputCost = (usage.completionTokens / 1_000_000) * model.cost.output

    return inputCost + outputCost
  }

  getSummary(filters?: UsageFilters): UsageSummary {
    // Aggregate by provider, model, date
  }
}
```

---

## 六、总结

### 各项目优势

| 项目 | Provider 优势 | 独特机制 |
|------|-------------|---------|
| **CoPaw** | 完整的 Provider 管理 + 包装器 | TokenUsageManager + RoutingChatModel |
| **kimi-cli** | kosong Protocol 设计 | 类型安全的 Provider Protocol |
| **openclaw** | 20+ Providers + ModelRef | Pi Agent 集成 + 子 Agent 继承 |
| **opencode** | Vercel AI SDK 生态 | 标准化 LanguageModelV2 接口 |

### 推荐技术选型

| 组件 | 推荐实现 | 来源 |
|------|---------|------|
| **Provider Interface** | LanguageModelV2 (Vercel style) | opencode |
| **Provider Manager** | Singleton + ModelRef | CoPaw + openclaw |
| **Configuration** | JSON with schema validation | CoPaw |
| **Retry/Fallback** | Exponential backoff wrapper | CoPaw |
| **Cost Tracking** | Multi-dimensional aggregation | CoPaw |
| **Streaming** | Standardized event types | Vercel AI SDK |
| **Local Models** | llama.cpp + MLX + Ollama | CoPaw |

### 最终推荐架构

```
┌─────────────────────────────────────────────────────────────────┐
│                    最终推荐 Provider 架构                      │
├─────────────────────────────────────────────────────────────────┤
│ 1. 接口设计:    Vercel AI SDK LanguageModelV2 标准             │
│ 2. 管理器:      Singleton ProviderManager + ModelRef           │
│ 3. 包装器:      RetryModel + TokenRecordingModel + RoutingModel│
│ 4. 配置:        JSON Schema + 文件存储                         │
│ 5. 成本:        多维聚合 (Provider/Model/Date)                 │
│ 6. 流式:        标准化事件类型                                 │
│ 7. 本地模型:    llama.cpp + MLX + Ollama 统一接口              │
│ 8. 子 Agent:    模型继承 + 覆盖机制                            │
└─────────────────────────────────────────────────────────────────┘
```

此方案融合了四个项目的最佳实践，兼顾标准化、扩展性和成本追踪，适用于生产级 AI Agent 系统。
