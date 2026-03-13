# Storage Schema 与核心对象模型分析

## 目录
1. [核心概念](#核心概念)
2. [CoPaw JSON + Pydantic 模型](#copaw-json--pydantic-模型)
3. [agent-browser 加密状态存储](#agent-browser-加密状态存储)
4. [edict PostgreSQL + JSONB](#edict-postgresql--jsonb)
5. [pinchtab 纯内存 + 快照](#pinchtab-纯内存--快照)
6. [架构对比与推荐](#架构对比与推荐)

---

## 核心概念

### 存储架构层次

```
┌─────────────────────────────────────────────────────────────┐
│                    Storage Architecture                     │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │   Memory     │  │    File      │  │    Database      │  │
│  │   (Runtime)  │  │   (Local)    │  │    (Remote)      │  │
│  │              │  │              │  │                  │  │
│  │ - Fast       │  │ - Persistent │  │ - Structured     │  │
│  │ - Volatile   │  │ - Portable   │  │ - Queryable      │  │
│  └──────┬───────┘  └──────┬───────┘  └────────┬─────────┘  │
│         │                 │                   │            │
│         └─────────────────┼───────────────────┘            │
│                           ▼                                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Object Model Layer                       │   │
│  │                                                      │   │
│  │  Session -> Message -> Part                         │   │
│  │  Agent -> Tool -> Skill                             │   │
│  │  User -> Workspace -> Project                       │   │
│  └─────────────────────────────────────────────────────┘   │
│                           │                                 │
│                           ▼                                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Serialization                            │   │
│  │                                                      │   │
│  │  JSON / Binary / Encrypted / Compressed             │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 核心对象关系

```
┌─────────────────────────────────────────────────────────────┐
│                    Core Object Relationships                │
│                                                             │
│  ┌─────────────┐         ┌─────────────┐                   │
│  │   User      │◀───────▶│  Workspace  │                   │
│  │             │         │             │                   │
│  └─────────────┘         └──────┬──────┘                   │
│                                  │                          │
│                    ┌─────────────┼─────────────┐            │
│                    │             │             │            │
│              ┌─────▼─────┐ ┌────▼────┐ ┌─────▼────┐       │
│              │  Session  │ │ Project │ │   Agent  │       │
│              │           │ │         │ │          │       │
│              └─────┬─────┘ └─────────┘ └────┬─────┘       │
│                    │                        │              │
│              ┌─────┼────────┐         ┌─────┼─────┐       │
│              │     │        │         │     │     │       │
│         ┌────▼─┐ ┌▼────┐ ┌─▼──┐   ┌──▼──┐ ┌▼───┐ ┌▼──┐  │
│         │Msg   │ │Event│ │Snap│   │Tool │ │Skill│ │Cron│  │
│         └──────┘ └─────┘ └────┘   └─────┘ └────┘ └────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## CoPaw JSON + Pydantic 模型

### 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                    CoPaw Storage Architecture               │
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐│
│  │   Memory    │  │    JSON     │  │   ReMeLight         ││
│  │   (Runtime) │  │   (Files)   │  │   (Vector/FTS)      ││
│  │             │  │             │  │                     ││
│  │ - ChatSpec  │  │ - chats.json│  │ - ChromaDB          ││
│  │ - ChatHistory│ │ - session.json│ │ - SQLite            ││
│  └─────────────┘  └─────────────┘  └─────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### 核心对象模型

```python
# src/copaw/app/runner/models.py
class ChatSpec(BaseModel):
    """Chat session specification."""
    id: str = Field(default_factory=lambda: str(uuid4()))
    name: str = Field(default="New Chat")
    session_id: str = Field(...)  # format: channel:user_id
    user_id: str = Field(...)
    channel: str = Field(default=DEFAULT_CHANNEL)
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    meta: Dict[str, Any] = Field(default_factory=dict)

class ChatHistory(BaseModel):
    """Chat message history."""
    messages: list[Message] = Field(default_factory=list)

class ChatsFile(BaseModel):
    """Root storage container."""
    version: int = 1  # Schema version for migrations
    chats: list[ChatSpec] = Field(default_factory=list)


# src/copaw/app/channels/schema.py
@dataclass
class ChannelAddress:
    """Unified routing address."""
    kind: str  # "dm" | "channel" | "webhook" | "console"
    id: str
    extra: Optional[Dict[str, Any]] = None


# src/copaw/app/crons/models.py
class CronJobSpec(BaseModel):
    """Cron job specification."""
    id: str
    name: str
    enabled: bool = True
    schedule: ScheduleSpec
    task_type: TaskType = "agent"
    text: Optional[str] = None
    request: Optional[CronJobRequest] = None
    dispatch: DispatchSpec
    runtime: JobRuntimeSpec = Field(default_factory=JobRuntimeSpec)
    meta: Dict[str, Any] = Field(default_factory=dict)
```

### JSON 存储实现

```python
# src/copaw/app/runner/repo/json_repo.py
class JSONChatRepository(BaseChatRepository):
    """JSON file-based chat repository with atomic writes."""

    def __init__(self, path: Path):
        self._path = path
        self._lock = asyncio.Lock()

    async def _atomic_save(self, jobs_file: ChatsFile) -> None:
        """Atomic save using tmp + replace pattern."""
        async with self._lock:
            # 1. 序列化为 JSON
            payload = jobs_file.model_dump(mode="json")

            # 2. 写入临时文件
            tmp_path = self._path.with_suffix(self._path.suffix + ".tmp")
            tmp_path.write_text(
                json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True),
                encoding="utf-8",
            )

            # 3. 原子替换
            tmp_path.replace(self._path)

    async def load(self) -> ChatsFile:
        """Load from JSON file."""
        if not self._path.exists():
            return ChatsFile()

        async with aiofiles.open(self._path, "r", encoding="utf-8") as f:
            content = await f.read()
            data = json.loads(content)

        # Pydantic 验证
        return ChatsFile(**data)

    async def save(self, jobs_file: ChatsFile) -> None:
        """Save with validation."""
        # 验证
        jobs_file.validate_self()
        await self._atomic_save(jobs_file)
```

### SafeJSONSession

```python
# src/copaw/app/runner/session.py
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
        # Windows 文件名安全处理
        self.session_file = self._get_safe_path(
            working_dir,
            f"{session_id}.json"
        )
        self.memory = memory or TemporaryMemory()

    def _get_safe_path(self, base: Path, filename: str) -> Path:
        """Get cross-platform safe file path."""
        if platform.system() == "Windows":
            # 替换 Windows 非法字符
            filename = re.sub(r'[<>:"/\\|?*]', '_', filename)
        return base / filename

    async def save_session_state(self, state: Dict[str, Any]) -> None:
        """Atomic session state save."""
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
```

---

## agent-browser 加密状态存储

### 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                 agent-browser Storage                       │
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐│
│  │   CDP       │  │    JSON     │  │   Encryption        ││
│  │   State     │  │   (Files)   │  │   (AES-256-GCM)     ││
│  │             │  │             │  │                     ││
│  │ - Cookies   │  │ - .json     │  │ - Environment key   ││
│  │ - localStorage│ │ - .json.enc │  │ - SHA256 key derive ││
│  │ - sessionStorage│           │  │ - Random nonce      ││
│  └─────────────┘  └─────────────┘  └─────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### CDP 存储状态模型

```rust
// cli/src/native/state.rs
#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StorageState {
    pub cookies: Vec<Cookie>,
    pub origins: Vec<OriginStorage>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct OriginStorage {
    pub origin: String,
    pub local_storage: Vec<StorageEntry>,
    pub session_storage: Vec<StorageEntry>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct StorageEntry {
    pub name: String,
    pub value: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Cookie {
    pub name: String,
    pub value: String,
    pub domain: String,
    pub path: String,
    pub expires: f64,
    pub size: i64,
    pub http_only: bool,
    pub secure: bool,
    pub session: bool,
    pub same_site: Option<String>,
}
```

### AES-256-GCM 加密

```rust
// cli/src/native/state.rs
use aes_gcm::{
    aead::{Aead, KeyInit},
    Aes256Gcm, Key, Nonce,
};
use sha2::{Sha256, Digest};

pub fn encrypt_data(data: &[u8], key_str: &str) -> Result<Vec<u8>, String> {
    // 1. SHA256 密钥派生
    let mut hasher = Sha256::new();
    hasher.update(key_str.as_bytes());
    let key_bytes = hasher.finalize();

    // 2. 创建 cipher
    let cipher = Aes256Gcm::new_from_slice(&key_bytes)
        .map_err(|e| e.to_string())?;

    // 3. 随机 nonce (12 bytes)
    let mut nonce = [0u8; 12];
    getrandom::getrandom(&mut nonce)
        .map_err(|e| e.to_string())?;

    // 4. 加密
    let ciphertext = cipher
        .encrypt(Nonce::from_slice(&nonce), data)
        .map_err(|e| e.to_string())?;

    // 5. nonce + ciphertext
    let mut result = Vec::with_capacity(12 + ciphertext.len());
    result.extend_from_slice(&nonce);
    result.extend_from_slice(&ciphertext);

    Ok(result)
}

pub fn decrypt_data(encrypted: &[u8], key_str: &str) -> Result<Vec<u8>, String> {
    if encrypted.len() < 12 {
        return Err("Invalid encrypted data".to_string());
    }

    // 1. 提取 nonce
    let nonce = &encrypted[0..12];
    let ciphertext = &encrypted[12..];

    // 2. 密钥派生
    let mut hasher = Sha256::new();
    hasher.update(key_str.as_bytes());
    let key_bytes = hasher.finalize();

    // 3. 解密
    let cipher = Aes256Gcm::new_from_slice(&key_bytes)
        .map_err(|e| e.to_string())?;

    cipher
        .decrypt(Nonce::from_slice(nonce), ciphertext)
        .map_err(|e| e.to_string())
}
```

### 状态保存流程

```rust
// cli/src/native/state.rs
pub async fn save_state(
    &self,
    file_path: Option<PathBuf>,
) -> Result<String, String> {
    // 1. 获取 cookies
    let cookies = self.get_all_cookies().await?;

    // 2. 获取 localStorage/sessionStorage
    let origins = self.get_all_storage().await?;

    // 3. 构建状态
    let state = StorageState {
        cookies,
        origins,
    };

    // 4. 序列化
    let json = serde_json::to_string_pretty(&state)
        .map_err(|e| e.to_string())?;

    // 5. 检查加密
    let data = if let Ok(key) = env::var("AGENT_BROWSER_ENCRYPTION_KEY") {
        // 加密模式
        let encrypted = encrypt_data(json.as_bytes(), &key)?;
        file_path.with_extension("json.enc")
    } else {
        // 明文模式
        json.into_bytes()
    };

    // 6. 原子写入
    let tmp_path = file_path.with_extension("tmp");
    fs::write(&tmp_path, data).await?;
    fs::rename(&tmp_path, &file_path).await?;

    Ok(file_path.to_string_lossy().to_string())
}
```

---

## edict PostgreSQL + JSONB

### 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                    edict PostgreSQL Schema                  │
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐│
│  │    tasks    │  │    events   │  │    thoughts         ││
│  │             │  │             │  │                     ││
│  │ - JSONB     │  │ - JSONB     │  │ - JSONB             ││
│  │ - GIN idx   │  │ - Composite │  │ - Composite         ││
│  │ - Alembic   │  │ - Index     │  │ - Index             ││
│  └─────────────┘  └─────────────┘  └─────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### 核心对象模型

```python
# backend/app/models/task.py
class Task(Base):
    """Task model with JSONB flexible fields."""
    __tablename__ = "tasks"

    id = Column(String(32), primary_key=True)  # JJC-20260301-001 format
    title = Column(Text, nullable=False)
    state = Column(Enum(TaskState), nullable=False, default=TaskState.Taizi)
    org = Column(String(32), nullable=False, default="太子")
    official = Column(String(32), default="")
    now = Column(Text, default="")  # Current progress
    eta = Column(String(64), default="-")
    block = Column(Text, default="无")
    output = Column(Text, default="")
    priority = Column(String(16), default="normal")
    archived = Column(Boolean, default=False)

    # JSONB flexible fields
    flow_log = Column(JSONB, default=list)      # Flow history
    progress_log = Column(JSONB, default=list)  # Progress history
    todos = Column(JSONB, default=list)         # Subtasks
    scheduler = Column(JSONB, default=dict)     # Scheduler metadata

    created_at = Column(DateTime(timezone=True), ...)
    updated_at = Column(DateTime(timezone=True), ...)


# backend/app/models/event.py
class Event(Base):
    """Event model for traceability."""
    __tablename__ = "events"

    event_id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    trace_id = Column(String(32), nullable=False, index=True)
    timestamp = Column(DateTime(timezone=True), ...)

    topic = Column(String(128), nullable=False, index=True)
    event_type = Column(String(128), nullable=False)
    producer = Column(String(128), nullable=False)

    payload = Column(JSONB, default=dict)
    meta = Column(JSONB, default=dict)


# backend/app/models/thought.py
class Thought(Base):
    """Thought model for agent reasoning."""
    __tablename__ = "thoughts"

    thought_id = Column(UUID(as_uuid=True), primary_key=True)
    trace_id = Column(String(32), nullable=False, index=True)
    agent = Column(String(32), nullable=False, index=True)
    step = Column(Integer, nullable=False, default=0)
    type = Column(String(32), nullable=False, default="reasoning")
    source = Column(String(16), default="llm")  # llm|tool|human
    content = Column(Text, nullable=False)
    tokens = Column(Integer, default=0)
    confidence = Column(Float, default=0.0)
    sensitive = Column(Boolean, default=False)
    timestamp = Column(DateTime(timezone=True), ...)
```

### Alembic 迁移

```python
# migration/versions/001_initial.py
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

def upgrade():
    # tasks table
    op.create_table(
        "tasks",
        sa.Column("task_id", sa.UUID(), nullable=False),
        sa.Column("trace_id", sa.String(64), nullable=False),
        sa.Column("title", sa.Text(), nullable=False),
        sa.Column("state", sa.Enum("Taizi", "Zhongshu", "Menxia", ...), nullable=False),
        sa.Column("tags", postgresql.JSONB(), server_default="[]"),
        sa.Column("flow_log", postgresql.JSONB(), server_default="[]"),
        sa.Column("progress_log", postgresql.JSONB(), server_default="[]"),
        sa.Column("scheduler", postgresql.JSONB(), server_default="{}"),
        sa.PrimaryKeyConstraint("task_id"),
    )

    # Composite indexes
    op.create_index("ix_tasks_state_archived", "tasks", ["state", "archived"])
    op.create_index("ix_tasks_tags", "tasks", ["tags"], postgresql_using="gin")

    # Foreign keys
    op.create_foreign_key(
        None, "tasks", "users",
        ["user_id"], ["user_id"],
        ondelete="CASCADE"
    )

    # events table
    op.create_table(
        "events",
        sa.Column("event_id", sa.UUID(), primary_key=True),
        sa.Column("trace_id", sa.String(32), nullable=False),
        sa.Column("topic", sa.String(128), nullable=False),
        sa.Column("event_type", sa.String(128), nullable=False),
        sa.Column("payload", postgresql.JSONB()),
        sa.Column("meta", postgresql.JSONB()),
    )

    op.create_index("ix_events_trace_topic", "events", ["trace_id", "topic"])
```

### 异步连接池

```python
# backend/app/db.py
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

# PostgreSQL async URL
DATABASE_URL = "postgresql+asyncpg://user:pass@localhost/edict"

engine = create_async_engine(
    DATABASE_URL,
    echo=settings.debug,
    pool_size=10,
    max_overflow=20,
    pool_pre_ping=True,  # 自动检测断开连接
)

async_session = sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
)

# 依赖注入
async def get_db() -> AsyncSession:
    async with async_session() as session:
        yield session
```

---

## pinchtab 纯内存 + 快照

### 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                    pinchtab Storage                         │
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐│
│  │   Memory    │  │    JSON     │  │     Hash IDs        ││
│  │   (Go)      │  │   (Snapshot)│  │                     ││
│  │             │  │             │  │ - prof_XXXXXXXX     ││
│  │ - Profile   │  │ - sessions  │  │ - inst_XXXXXXXX     ││
│  │ - Instance  │  │ - Profile   │  │                     ││
│  │ - Tab       │  │             │  │                     ││
│  └─────────────┘  └─────────────┘  └─────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### 核心对象模型

```go
// internal/api/types/types.go
type Profile struct {
    ID         string    `json:"id,omitempty"`
    Name       string    `json:"name"`
    Path       string    `json:"path,omitempty"`
    PathExists bool      `json:"pathExists,omitempty"`
    Created    time.Time `json:"created"`
    LastUsed   time.Time `json:"lastUsed"`
    DiskUsage  int64     `json:"diskUsage"`
    SizeMB     float64   `json:"sizeMB,omitempty"`
    Running    bool      `json:"running"`
    Temporary  bool      `json:"temporary,omitempty"`
}

type Instance struct {
    ID          string    `json:"id"`           // hash-based
    ProfileID   string    `json:"profileId"`    // prof_XXXXXXXX
    ProfileName string    `json:"profileName"`
    Port        string    `json:"port"`
    Headless    bool      `json:"headless"`
    Status      string    `json:"status"`       // starting/running/stopping
    StartTime   time.Time `json:"startTime"`
    Error       string    `json:"error,omitempty"`
}

type Agent struct {
    ID           string    `json:"id"`
    Name         string    `json:"name,omitempty"`
    ConnectedAt  time.Time `json:"connectedAt"`
    LastActivity time.Time `json:"lastActivity,omitempty"`
    RequestCount int       `json:"requestCount"`
}

type ActivityEvent struct {
    ID        string                 `json:"id"`
    AgentID   string                 `json:"agentId"`
    Type      string                 `json:"type"` // navigate/snapshot/...
    Method    string                 `json:"method"`
    Path      string                 `json:"path"`
    Timestamp time.Time              `json:"timestamp"`
    Details   map[string]interface{} `json:"details,omitempty"`
}
```

### 会话状态快照

```go
// internal/bridge/state.go
type TabState struct {
    ID    string `json:"id"`
    URL   string `json:"url"`
    Title string `json:"title"`
}

type SessionState struct {
    Tabs    []TabState `json:"tabs"`
    SavedAt string     `json:"savedAt"`
}

// 保存快照
func (b *Bridge) SaveSession() error {
    state := SessionState{
        Tabs:    []TabState{},
        SavedAt: time.Now().Format(time.RFC3339),
    }

    // 获取所有 targets
    targets, err := b.client.Target.GetTargets(context.Background())
    if err != nil {
        return err
    }

    // 过滤 transient URLs
    for _, target := range targets {
        if isTransientURL(target.URL) {
            continue
        }
        state.Tabs = append(state.Tabs, TabState{
            ID:    target.TargetID,
            URL:   target.URL,
            Title: target.Title,
        })
    }

    // JSON 序列化
    data, err := json.MarshalIndent(state, "", "  ")
    if err != nil {
        return err
    }

    // 写入文件
    return os.WriteFile("sessions.json", data, 0644)
}

// 并发恢复
func (b *Bridge) RestoreSession() error {
    data, err := os.ReadFile("sessions.json")
    if err != nil {
        return err
    }

    var state SessionState
    if err := json.Unmarshal(data, &state); err != nil {
        return err
    }

    // 并发控制
    const maxConcurrentTabs = 3
    const maxConcurrentNavs = 2

    tabSem := make(chan struct{}, maxConcurrentTabs)
    navSem := make(chan struct{}, maxConcurrentNavs)

    for _, tab := range state.Tabs {
        tabSem <- struct{}{}

        go func(tabCtx context.Context, url string) {
            defer func() { <-tabSem }()

            // 创建 tab
            tabID, ctx, cancel, err := b.CreateTab("")
            if err != nil {
                return
            }
            defer cancel()

            // 导航信号量
            navSem <- struct{}{}
            defer func() { <-navSem }()

            // 异步导航
            b.Navigate(tabID, url)
        }(ctx, tab.URL)
    }

    return nil
}
```

---

## 架构对比与推荐

### 四项目对比

| 特性 | CoPaw | agent-browser | edict | pinchtab |
|------|-------|---------------|-------|----------|
| **数据库** | ❌ | ❌ | PostgreSQL | ❌ |
| **文件系统** | JSON | JSON + Enc | ❌ | JSON |
| **内存** | ✅ | CDP State | SQLAlchemy | Go structs |
| **加密** | ❌ | AES-256-GCM | ❌ | ❌ |
| **向量存储** | ChromaDB | ❌ | ❌ | ❌ |
| **迁移** | Version 字段 | Serde | Alembic | ❌ |
| **ORM** | Pydantic | Serde | SQLAlchemy | ❌ |
| **索引** | ❌ | ❌ | GIN + Composite | ❌ |

### 推荐混合架构

```
┌─────────────────────────────────────────────────────────────┐
│                    Recommended Storage                      │
│                                                             │
│  Layer 1: Memory (Runtime)                                  │
│  - Pydantic models (CoPaw)                                  │
│  - Go structs (pinchtab)                                    │
│                                                             │
│  Layer 2: JSON Files (Local)                                │
│  - Atomic writes (tmp + replace)                            │
│  - Encryption optional (AES-256-GCM)                        │
│  - Version field for migrations                             │
│                                                             │
│  Layer 3: PostgreSQL (Remote)                               │
│  - Structured data                                          │
│  - JSONB flexible fields                                    │
│  - Alembic migrations                                       │
│  - GIN indexes                                              │
│                                                             │
│  Layer 4: Vector Store (Optional)                           │
│  - ChromaDB / Pinecone                                      │
│  - Embedding cache                                          │
└─────────────────────────────────────────────────────────────┘
```

### 关键设计建议

1. **对象模型**
   - Session -> Message -> Part 层级
   - UUID 主键
   - JSONB 灵活字段

2. **存储策略**
   - 运行时：内存 (Pydantic/dataclasses)
   - 本地：JSON + 原子写入
   - 远程：PostgreSQL + Alembic

3. **加密**
   - 环境变量密钥
   - AES-256-GCM
   - SHA256 密钥派生

4. **迁移**
   - 版本字段
   - Alembic for SQL
   - 向后兼容

---

## 附录：关键代码文件

| 项目 | 关键文件 | 说明 |
|------|----------|------|
| **CoPaw** | `app/runner/models.py` | Chat models |
| **CoPaw** | `app/runner/repo/json_repo.py` | JSON repository |
| **agent-browser** | `cli/src/native/state.rs` | State storage |
| **edict** | `backend/app/models/task.py` | Task model |
| **edict** | `migration/versions/001_initial.py` | Alembic migration |
| **pinchtab** | `internal/api/types/types.go` | Go types |
| **pinchtab** | `internal/bridge/state.go` | Session state |

---

*报告生成时间: 2025-03-13*
*分析项目: CoPaw, agent-browser, edict, pinchtab*
