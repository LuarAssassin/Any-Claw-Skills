# Plugin Architecture 分析

## 目录
1. [核心概念](#核心概念)
2. [CoPaw 技能与渠道插件](#copaw-技能与渠道插件)
3. [kimi-cli 分层技能系统](#kimi-cli-分层技能系统)
4. [openclaw 完整插件架构](#openclaw-完整插件架构)
5. [opencode Hooks 插件系统](#opencode-hooks-插件系统)
6. [架构对比与推荐](#架构对比与推荐)

---

## 核心概念

### 插件架构核心组件

```
┌─────────────────────────────────────────────────────────────┐
│                    Plugin Architecture                      │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │   Discovery  │  │    Load      │  │    Lifecycle     │  │
│  │              │  │              │  │                  │  │
│  │ - Scan dirs  │  │ - import()   │  │ - install        │  │
│  │ - Registry   │  │ - require()  │  │ - enable/disable │  │
│  │ - npm search │  │ - jiti       │  │ - uninstall      │  │
│  └──────┬───────┘  └──────┬───────┘  └────────┬─────────┘  │
│         │                 │                   │            │
│         └─────────────────┼───────────────────┘            │
│                           ▼                                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                    Extension Points                   │   │
│  │                                                      │   │
│  │  Tools │ Hooks │ Channels │ Providers │ Commands    │   │
│  │                                                      │   │
│  └─────────────────────────────────────────────────────┘   │
│                           │                                 │
│                           ▼                                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                    Security & Isolation               │   │
│  │                                                      │   │
│  │  - Path validation    - Sandboxing    - Permissions  │   │
│  │  - Dependency mgmt    - Resource limits              │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 插件生命周期

```
        Install          Enable
           │               │
           ▼               ▼
    ┌──────────┐    ┌──────────┐
    │ Installed│───▶│ Enabled  │◀───┐
    │          │    │ (Active) │    │
    └──────────┘    └────┬─────┘    │
                         │          │
                    Load │          │ Enable
                         ▼          │
                   ┌──────────┐     │
                   │  Loaded  │─────┘
                   └──────────┘

                         │
                    Disable
                         ▼
    ┌──────────┐    ┌──────────┐
    │Disabled  │◀───│ Enabled  │
    │ (Inactive)    │          │
    └──────────┘    └──────────┘


                         │
                   Uninstall
                         ▼
                   ┌──────────┐
                   │  Removed │
                   └──────────┘
```

---

## CoPaw 技能与渠道插件

### 整体架构

CoPaw 采用**基于目录的技能系统**，支持从多个来源安装技能。

```
┌─────────────────────────────────────────────────────────────┐
│                    CoPaw Plugin Architecture                │
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐│
│  │   Builtin   │  │ Customized  │  │       Active        ││
│  │   Skills    │  │   Skills    │  │       Skills        ││
│  │             │  │             │  │                     ││
│  │  (bundled)  │  │ (user mod)  │  │   (runtime copy)    ││
│  │             │  │             │  │                     ││
│  └─────────────┘  └─────────────┘  └─────────────────────┘│
│         │                │                    │            │
│         └────────────────┼────────────────────┘            │
│                          ▼                                 │
│  ┌─────────────────────────────────────────────────────┐  │
│  │                    Skills Manager                     │  │
│  │  - install / enable / disable / delete               │  │
│  │  - sync to working dir                               │  │
│  └─────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 技能发现

```python
# src/copaw/agents/skills_manager.py
class SkillsManager:
    """Manage skills lifecycle and synchronization."""

    def __init__(self):
        self.builtin_skills_dir = Path(__file__).parent / "skills"
        self.customized_skills_dir = Path(os.getenv(
            "CUSTOMIZED_SKILLS_DIR",
            Path.home() / ".copaw" / "customized_skills"
        ))
        self.active_skills_dir = Path(os.getenv(
            "ACTIVE_SKILLS_DIR",
            Path.cwd() / ".copaw" / "active_skills"
        ))

    def _collect_skills_from_dir(self, directory: Path) -> dict[str, Path]:
        """Scan directory for valid skills."""
        skills: dict[str, Path] = {}
        if directory.exists():
            for skill_dir in directory.iterdir():
                if skill_dir.is_dir() and (skill_dir / "SKILL.md").exists():
                    skills[skill_dir.name] = skill_dir
        return skills

    def list_skills(self) -> list[SkillInfo]:
        """List all skills from all sources."""
        builtin = self._collect_skills_from_dir(self.builtin_skills_dir)
        customized = self._collect_skills_from_dir(self.customized_skills_dir)
        active = self._collect_skills_from_dir(self.active_skills_dir)

        skills = []
        for name, path in {**builtin, **customized, **active}.items():
            skill_info = self._parse_skill_md(path / "SKILL.md")
            skills.append(SkillInfo(
                name=name,
                path=str(path),
                source="builtin" if name in builtin else (
                    "customized" if name in customized else "active"
                ),
                **skill_info
            ))
        return skills

    def _parse_skill_md(self, skill_md_path: Path) -> dict:
        """Parse SKILL.md frontmatter."""
        content = skill_md_path.read_text()

        # 解析 YAML frontmatter
        if content.startswith("---"):
            _, frontmatter, body = content.split("---", 2)
            metadata = yaml.safe_load(frontmatter)
        else:
            metadata = {}
            body = content

        return {
            "description": metadata.get("description", ""),
            "content": body.strip(),
            "references": metadata.get("references", {}),
            "scripts": metadata.get("scripts", {}),
        }
```

### 技能生命周期

```python
# src/copaw/agents/skills_manager.py
class SkillsManager:
    async def install_skill_from_hub(
        self,
        source: str,  # "clawhub", "github", "skills.sh"
        identifier: str,  # skill slug or GitHub repo
        version: str = "latest",
    ) -> SkillInfo:
        """Install skill from hub."""
        if source == "clawhub":
            return await self._install_from_clawhub(identifier, version)
        elif source == "github":
            return await self._install_from_github(identifier, version)
        elif source == "skills.sh":
            return await self._install_from_skillssh(identifier)
        else:
            raise ValueError(f"Unknown source: {source}")

    async def enable_skill(self, skill_name: str) -> None:
        """Enable skill by copying to active directory."""
        # 1. 查找技能源
        source_path = self._find_skill_source(skill_name)
        if not source_path:
            raise SkillNotFoundError(skill_name)

        # 2. 复制到 active 目录
        target_path = self.active_skills_dir / skill_name
        if target_path.exists():
            shutil.rmtree(target_path)
        shutil.copytree(source_path, target_path)

        # 3. 验证 SKILL.md
        if not (target_path / "SKILL.md").exists():
            raise InvalidSkillError(f"SKILL.md not found in {skill_name}")

    async def disable_skill(self, skill_name: str) -> None:
        """Disable skill by removing from active directory."""
        target_path = self.active_skills_dir / skill_name
        if target_path.exists():
            shutil.rmtree(target_path)

    async def sync_skills_to_working_dir(self, force: bool = False) -> None:
        """Sync all enabled skills to working directory."""
        active_skills = self._collect_skills_from_dir(self.active_skills_dir)

        for name, source_path in active_skills.items():
            target_path = self.working_dir / ".copaw" / "skills" / name

            # 检查是否需要同步
            if target_path.exists() and not force:
                source_mtime = max(
                    f.stat().st_mtime for f in source_path.rglob("*")
                )
                target_mtime = max(
                    f.stat().st_mtime for f in target_path.rglob("*")
                )
                if target_mtime >= source_mtime:
                    continue  # 已是最新

            # 同步
            if target_path.exists():
                shutil.rmtree(target_path)
            shutil.copytree(source_path, target_path)
```

### ClawHub 集成

```python
# src/copaw/agents/skills_hub.py
class SkillsHubClient:
    """Client for ClawHub skill marketplace."""

    CLAWHUB_API = "https://api.clawhub.ai/v1"
    SKILLS_SH_API = "https://skills.sh/api/v1"

    async def search_skills(
        self,
        query: str,
        category: str | None = None,
    ) -> list[HubSkillResult]:
        """Search skills from ClawHub."""
        async with aiohttp.ClientSession() as session:
            params = {"q": query}
            if category:
                params["category"] = category

            async with session.get(
                f"{self.CLAWHUB_API}/skills",
                params=params,
            ) as resp:
                data = await resp.json()
                return [HubSkillResult(**item) for item in data["skills"]]

    async def install_from_github(
        self,
        repo: str,  # "owner/repo"
        ref: str = "main",  # branch/tag
    ) -> SkillInfo:
        """Install skill from GitHub repository."""
        # 下载 zip
        url = f"https://github.com/{repo}/archive/refs/heads/{ref}.zip"
        async with aiohttp.ClientSession() as session:
            async with session.get(url) as resp:
                zip_content = await resp.read()

        # 解压到 customized_skills
        import zipfile
        import io

        with zipfile.ZipFile(io.BytesIO(zip_content)) as zf:
            zf.extractall(self.customized_skills_dir)

        # 重命名目录
        skill_name = repo.split("/")[-1]
        extracted_dir = self.customized_skills_dir / f"{repo.replace('/', '-')}-{ref}"
        target_dir = self.customized_skills_dir / skill_name
        extracted_dir.rename(target_dir)

        return self._parse_skill(target_dir)
```

### 渠道动态加载

```python
# src/copaw/app/channels/registry.py
import importlib
import inspect
from pathlib import Path

_BUILTIN_SPECS: dict[str, tuple[str, str]] = {
    "imessage": (".imessage", "IMessageChannel"),
    "discord": (".discord_", "DiscordChannel"),
    "dingtalk": (".dingtalk", "DingTalkChannel"),
    "feishu": (".feishu", "FeishuChannel"),
    "qq": (".qq", "QQChannel"),
    # ...
}

_BUILTINS_LOCK = threading.Lock()
_BUILTINS_CACHE: dict[str, type[BaseChannel]] | None = None

@functools.cache
def _get_cached_builtin_channels() -> dict[str, type[BaseChannel]]:
    """Lazy load builtin channels with caching."""
    builtins: dict[str, type[BaseChannel]] = {}
    for channel_id, (module_path, class_name) in _BUILTIN_SPECS.items():
        module = importlib.import_module(module_path, package=__package__)
        cls = getattr(module, class_name)
        builtins[channel_id] = cls
    return builtins


def _discover_custom_channels() -> dict[str, type[BaseChannel]]:
    """Discover custom channels from filesystem."""
    custom_dir = Path(os.getenv("CUSTOM_CHANNELS_DIR", "./custom_channels"))
    if not custom_dir.exists():
        return {}

    channels: dict[str, type[BaseChannel]] = {}

    # 支持 .py 文件或 Python 包
    for item in custom_dir.iterdir():
        if item.suffix == ".py":
            # 单文件插件
            spec = importlib.util.spec_from_file_location(
                f"custom_channels.{item.stem}",
                item,
            )
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
        elif item.is_dir() and (item / "__init__.py").exists():
            # 包插件
            module = importlib.import_module(f"custom_channels.{item.name}")
        else:
            continue

        # 查找 BaseChannel 子类
        for name, obj in inspect.getmembers(module, inspect.isclass):
            if issubclass(obj, BaseChannel) and obj is not BaseChannel:
                channels[obj.channel] = obj

    return channels
```

---

## kimi-cli 分层技能系统

### 整体架构

kimi-cli 采用**分层目录解析**技能系统，支持项目级、用户级、内置三级覆盖。

```
┌─────────────────────────────────────────────────────────────┐
│                    kimi-cli Skill Layers                    │
│                                                             │
│  Priority: Project > User > Built-in                        │
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐│
│  │   Project   │  │    User     │  │      Built-in       ││
│  │   Level     │  │    Level    │  │       Level         ││
│  │             │  │             │  │                     ││
│  │  ./.kimi/   │  │  ~/.kimi/   │  │  (package bundled)  ││
│  │  ./.agents/ │  │ ~/.agents/  │  │                     ││
│  │             │  │ ~/.config/  │  │                     ││
│  └─────────────┘  └─────────────┘  └─────────────────────┘│
│         │                │                    │            │
│         └────────────────┼────────────────────┘            │
│                          ▼                                 │
│  ┌─────────────────────────────────────────────────────┐  │
│  │                 SkillResolver                       │  │
│  │  - Resolve by name                                  │  │
│  │  - Merge layers                                     │  │
│  └─────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 分层解析

```python
# src/kimi_cli/skill/__init__.py
class SkillResolver:
    """Resolve skills from layered directories."""

    def get_user_skills_dir_candidates(self) -> tuple[Path, ...]:
        """Standard skill directory locations."""
        return (
            Path.home() / ".config" / "agents" / "skills",
            Path.home() / ".agents" / "skills",
            Path.home() / ".kimi" / "skills",
            Path.home() / ".claude" / "skills",
            Path.home() / ".codex" / "skills",
        )

    def resolve_skill(
        self,
        name: str,
        work_dir: Path | None = None,
    ) -> Skill | None:
        """Resolve skill by name with priority order."""
        # 1. 项目级 (最高优先级)
        if work_dir:
            project_paths = [
                work_dir / ".kimi" / "skills" / name,
                work_dir / ".agents" / "skills" / name,
            ]
            for path in project_paths:
                if path.exists():
                    return self._load_skill(path)

        # 2. 用户级
        for dir_candidate in self.get_user_skills_dir_candidates():
            path = dir_candidate / name
            if path.exists():
                return self._load_skill(path)

        # 3. 内置级
        builtin_path = Path(__file__).parent / "skills" / name
        if builtin_path.exists():
            return self._load_skill(builtin_path)

        return None

    def list_all_skills(
        self,
        work_dir: Path | None = None,
    ) -> dict[str, list[SkillSource]]:
        """List all skills from all layers."""
        skills: dict[str, list[SkillSource]] = {}

        # 收集内置
        for skill in self._list_builtin_skills():
            skills.setdefault(skill.name, []).append(
                SkillSource(skill=skill, layer="builtin")
            )

        # 收集用户级
        for skill in self._list_user_skills():
            skills.setdefault(skill.name, []).append(
                SkillSource(skill=skill, layer="user")
            )

        # 收集项目级
        if work_dir:
            for skill in self._list_project_skills(work_dir):
                skills.setdefault(skill.name, []).append(
                    SkillSource(skill=skill, layer="project")
                )

        return skills
```

### MCP 工具集成

```python
# packages/kosong/src/kosong/tooling/mcp.py
from pydantic import BaseModel
from mcp import ClientSession, StdioServerParameters
from mcp.types import (
    TextContent,
    ImageContent,
    EmbeddedResource,
    CallToolResult,
)

class MCPToolAdapter:
    """Adapter for MCP (Model Context Protocol) tools."""

    def __init__(self, session: ClientSession):
        self.session = session

    async def list_tools(self) -> list[CallableTool]:
        """List all available MCP tools."""
        tools = await self.session.list_tools()
        return [self._convert_tool(t) for t in tools.tools]

    def _convert_tool(self, mcp_tool) -> CallableTool:
        """Convert MCP tool to CallableTool."""
        return CallableTool(
            name=mcp_tool.name,
            description=mcp_tool.description or "",
            parameters=mcp_tool.inputSchema,
            callable=self._create_callable(mcp_tool.name),
        )

    def _create_callable(self, tool_name: str):
        """Create callable wrapper for MCP tool."""
        async def call(**kwargs) -> ToolReturnValue:
            result: CallToolResult = await self.session.call_tool(
                tool_name,
                kwargs,
            )

            # 转换 MCP 结果格式
            content_parts = []
            for content in result.content:
                if isinstance(content, TextContent):
                    content_parts.append({"type": "text", "text": content.text})
                elif isinstance(content, ImageContent):
                    content_parts.append({
                        "type": "image",
                        "mime_type": content.mimeType,
                        "data": content.data,
                    })
                elif isinstance(content, EmbeddedResource):
                    content_parts.append({
                        "type": "resource",
                        "resource": content.resource,
                    })

            return ToolReturnValue(content=content_parts)

        return call
```

---

## openclaw 完整插件架构

### 整体架构

openclaw 拥有**最完整的插件系统**，支持工具、钩子、渠道、Provider、HTTP、CLI 等多种扩展点。

```
┌─────────────────────────────────────────────────────────────┐
│                    openclaw Plugin System                   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                    Plugin Loader                      │   │
│  │  - jiti (TS/JS loading)                               │   │
│  │  - npm packages                                       │   │
│  │  - Workspace extensions                               │   │
│  │  - Bundled plugins                                    │   │
│  └─────────────────────────────────────────────────────┘   │
│                           │                                 │
│                           ▼                                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                    Plugin Registry                    │   │
│  │  - ID-based registration                              │   │
│  │  - Provenance tracking                                │   │
│  │  - Allowlist enforcement                              │   │
│  └─────────────────────────────────────────────────────┘   │
│                           │                                 │
│           ┌───────────────┼───────────────┐                │
│           ▼               ▼               ▼                │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐       │
│  │    Tools     │ │    Hooks     │ │   Channels   │       │
│  │              │ │              │ │              │       │
│  │ - registerTool          │ │ - registerHook          │ │ - registerChannel        │       │
│  │ - optional/named        │ │ - event-driven          │ │ - messaging adapters     │       │
│  └──────────────┘ └──────────────┘ └──────────────┘       │
│                                                             │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐       │
│  │   Providers  │ │ HTTP Routes  │ │     CLI      │       │
│  │              │ │              │ │              │       │
│  │ - LLM providers│ │ - Custom endpoints    │ │ - Subcommands      │       │
│  └──────────────┘ └──────────────┘ └──────────────┘       │
└─────────────────────────────────────────────────────────────┘
```

### 插件加载

```typescript
// src/plugins/loader.ts
import { jiti } from "jiti";

export interface PluginLoadOptions {
  id: string;
  source: string;
  origin: "bundled" | "workspace" | "npm";
  path: string;
  config?: Record<string, unknown>;
}

export async function loadPlugin(
  options: PluginLoadOptions,
): Promise<LoadedPlugin> {
  const { id, source, origin, path: pluginPath, config } = options;

  // 1. 路径安全检查
  if (!isPathInside(pluginPath, getAllowedPaths())) {
    throw new PluginSecurityError(
      `Plugin path ${pluginPath} is outside allowed directories`,
    );
  }

  // 2. 使用 jiti 加载 TypeScript/JavaScript
  const loader = jiti(pluginPath, {
    interopDefault: true,
    esmResolve: true,
    // SDK 别名
    alias: {
      "openclaw/plugin-sdk": resolveSdkPath(),
      "openclaw/plugin-sdk/*": resolveSdkWildcard(),
    },
  });

  // 3. 加载模块
  const module = await loader(pluginPath);

  // 4. 提取插件导出
  const pluginExport = module.default || module;

  // 5. 验证插件结构
  if (typeof pluginExport !== "function") {
    throw new PluginValidationError(
      `Plugin ${id} must export a function as default`,
    );
  }

  // 6. 创建插件 API
  const api = createPluginApi(id, config);

  // 7. 初始化插件
  const result = await pluginExport(api);

  return {
    id,
    source,
    origin,
    exports: result,
    tools: api.getRegisteredTools(),
    hooks: api.getRegisteredHooks(),
  };
}

function isPathInside(childPath: string, parentPaths: string[]): boolean {
  const resolved = path.resolve(childPath);
  return parentPaths.some((p) => resolved.startsWith(path.resolve(p)));
}
```

### 插件注册表

```typescript
// src/plugins/registry.ts
export interface PluginRegistry {
  // 注册状态
  plugins: Map<string, PluginRecord>;

  // 注册方法
  registerTool: (tool: ToolDefinition, opts?: ToolOptions) => void;
  registerHook: (hook: HookRegistration) => void;
  registerChannel: (channel: ChannelRegistration) => void;
  registerProvider: (provider: ProviderDefinition) => void;
  registerHttpRoute: (route: HttpRouteDefinition) => void;
  registerCommand: (command: CommandDefinition) => void;
}

export interface PluginRecord {
  id: string;
  name: string;
  version?: string;
  description?: string;
  kind?: PluginKind;
  source: string;
  origin: PluginOrigin;
  enabled: boolean;
  status: "loaded" | "disabled" | "error";
  error?: string;

  // 注册的内容
  toolNames: string[];
  hookNames: string[];
  channelIds: string[];
  providerIds: string[];
  httpRoutes: string[];
  commands: string[];

  // 元数据
  manifest?: PluginManifest;
  config?: Record<string, unknown>;
}

// 创建插件 API
function createPluginApi(
  record: PluginRecord,
  registry: PluginRegistry,
): OpenClawPluginApi {
  return {
    // 基本信息
    id: record.id,
    name: record.name,
    config: record.config || {},
    logger: createPluginLogger(record.id),

    // 工具注册
    registerTool: (tool, opts) => {
      const toolId = `${record.id}:${tool.name}`;
      registry.registerTool(toolId, tool, opts);
      record.toolNames.push(toolId);
    },

    // 钩子注册
    registerHook: (event, handler, opts) => {
      const hookId = registry.registerHook(event, handler, opts);
      record.hookNames.push(hookId);
    },

    // 渠道注册
    registerChannel: (registration) => {
      const channelId = registry.registerChannel(record.id, registration);
      record.channelIds.push(channelId);
    },

    // Provider 注册
    registerProvider: (provider) => {
      const providerId = registry.registerProvider(record.id, provider);
      record.providerIds.push(providerId);
    },

    // HTTP 路由注册
    registerHttpRoute: (route) => {
      const routeId = registry.registerHttpRoute(record.id, route);
      record.httpRoutes.push(routeId);
    },

    // CLI 命令注册
    registerCommand: (command) => {
      const cmdId = registry.registerCommand(record.id, command);
      record.commands.push(cmdId);
    },

    // 路径解析
    resolvePath: (input: string) => resolveUserPath(input),

    // 钩子监听
    on: (hookName, handler, opts) => {
      return registerTypedHook(record, hookName, handler, opts);
    },
  };
}
```

### 安全与隔离

```typescript
// src/plugins/registry.ts
interface PluginSecurityPolicy {
  // 文件系统
  allowFileRead: boolean;
  allowFileWrite: boolean;
  allowedPaths: string[];
  blockedPaths: string[];

  // 网络
  allowNetwork: boolean;
  allowedHosts: string[];
  blockedHosts: string[];

  // 系统
  allowShell: boolean;
  allowProcessSpawn: boolean;

  // 提示词注入
  allowPromptInjection: boolean;
}

// 文件边界验证
export function openBoundaryFileSync(
  pluginId: string,
  filePath: string,
  options?: { encoding?: BufferEncoding; flag?: string },
): string {
  // 1. 验证路径是否在允许范围内
  if (!isPathInside(filePath, getPluginAllowedPaths(pluginId))) {
    throw new PluginSecurityError(
      `Access denied: ${filePath} is outside plugin boundaries`,
    );
  }

  // 2. 解析符号链接
  const resolved = fs.realpathSync(filePath);

  // 3. 再次验证解析后的路径
  if (!isPathInside(resolved, getPluginAllowedPaths(pluginId))) {
    throw new PluginSecurityError(
      `Path traversal detected: ${filePath} -> ${resolved}`,
    );
  }

  // 4. 拒绝硬链接（非捆绑插件）
  if (!isBundledPlugin(pluginId) && isHardLink(resolved)) {
    throw new PluginSecurityError(
      `Hard links are not allowed for non-bundled plugins`,
    );
  }

  // 5. 读取文件
  return fs.readFileSync(resolved, options);
}

// 提示词注入防护
function registerTypedHook<K extends PluginHookName>(
  record: PluginRecord,
  hookName: K,
  handler: PluginHookHandlerMap[K],
  opts?: { priority?: number },
  policy?: PluginTypedHookPolicy,
): string {
  // 检查策略
  if (
    hookName === "before_prompt_build" &&
    !policy?.allowPromptInjection
  ) {
    throw new PluginSecurityError(
      `Prompt injection hooks require explicit policy approval`,
    );
  }

  // 注册钩子
  return registry.registerHook(hookName, handler, opts);
}
```

### SDK 设计

```typescript
// src/plugin-sdk/index.ts
// 600+ 导出

// 核心类型
export type {
  OpenClawPluginApi,
  ToolDefinition,
  ToolOptions,
  HookRegistration,
  ChannelRegistration,
  ProviderDefinition,
  HttpRouteDefinition,
  CommandDefinition,
} from "../plugins/types";

// 渠道特定
export {
  // Discord
  createDiscordChannel,
  DiscordChannelConfig,
  DiscordMessageHandler,

  // Telegram
  createTelegramChannel,
  TelegramChannelConfig,
  TelegramMessageHandler,

  // Slack
  createSlackChannel,
  SlackChannelConfig,

  // ... 更多渠道
} from "./channels";

// 工具辅助
export {
  createTool,
  defineToolSchema,
  validateToolInput,
} from "./tools";

// 钩子辅助
export {
  createHook,
  HookPriority,
} from "./hooks";

// Provider 辅助
export {
  createLLMProvider,
  ProviderConfig,
} from "./providers";
```

---

## opencode Hooks 插件系统

### 整体架构

opencode 采用**基于 Hooks 的事件驱动插件系统**，支持多种生命周期钩子。

```
┌─────────────────────────────────────────────────────────────┐
│                    opencode Plugin System                   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                    Plugin Loader                      │   │
│  │  - Internal plugins (bundled)                         │   │
│  │  - External plugins (npm)                             │   │
│  │  - File-based plugins (file://)                       │   │
│  └─────────────────────────────────────────────────────┘   │
│                           │                                 │
│           ┌───────────────┼───────────────┐                │
│           ▼               ▼               ▼                │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐       │
│  │    event     │ │    config    │ │     tool     │       │
│  │              │ │              │ │              │       │
│  │ chat.message │ │  modify      │ │  register    │       │
│  │ chat.params  │ │  settings    │ │  custom      │       │
│  └──────────────┘ └──────────────┘ └──────────────┘       │
│                                                             │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐       │
│  │   auth       │ │  permission  │ │    shell     │       │
│  │              │ │              │ │              │       │
│  │  provider    │ │  ask         │ │  env         │       │
│  └──────────────┘ └──────────────┘ └──────────────┘       │
└─────────────────────────────────────────────────────────────┘
```

### 插件加载

```typescript
// packages/opencode/src/plugin/index.ts
export namespace Plugin {
  const state = Instance.state(async () => {
    const hooks: Hooks[] = [];
    const seen = new Set<PluginInstance>();

    const input: PluginInput = {
      client: Instance.client,
      project: Instance.project,
      worktree: Instance.worktree,
      directory: Instance.directory,
      serverUrl: Server.url ?? new URL("http://localhost:4096"),
      $: Bun.$,
    };

    // 1. 加载内置插件
    for (const plugin of INTERNAL_PLUGINS) {
      const init = await plugin(input).catch((err) => {
        console.error("Failed to load internal plugin:", err);
        return null;
      });
      if (init) hooks.push(init);
    }

    // 2. 加载外部插件
    const config = await Config.get();
    for (const pluginRef of config.plugins || []) {
      let pluginPath = pluginRef;

      // npm 包安装
      if (!pluginRef.startsWith("file://")) {
        const [pkg, version] = pluginRef.split("@");
        pluginPath = await BunProc.install(pkg, version).catch((err) => {
          console.error(`Failed to install plugin ${pluginRef}:`, err);
          return null;
        });
      }

      if (!pluginPath) continue;

      // 动态导入
      await import(pluginPath).then(async (mod) => {
        for (const [name, fn] of Object.entries<PluginInstance>(mod)) {
          if (seen.has(fn)) continue;
          seen.add(fn);

          const hook = await fn(input).catch((err) => {
            console.error(`Failed to initialize plugin ${name}:`, err);
            return null;
          });

          if (hook) hooks.push(hook);
        }
      });
    }

    return hooks;
  });
}

// 内置插件列表
const INTERNAL_PLUGINS: PluginInstance[] = [
  CodexAuthPlugin,
  CopilotAuthPlugin,
  GitlabAuthPlugin,
];

// 默认插件（从市场安装）
const BUILTIN_PLUGINS = [
  "opencode-anthropic-auth@0.0.13",
];
```

### Hooks 接口

```typescript
// packages/plugin/src/index.ts
export interface Hooks {
  // 事件钩子
  event?: (input: { event: Event }) => Promise<void>;

  // 配置钩子
  config?: (input: Config) => Promise<void>;

  // 工具钩子
  tool?: { [key: string]: ToolDefinition };

  // 认证钩子
  auth?: {
    provider: string;
    authenticate: (input: AuthInput) => Promise<AuthOutput>;
  };

  // 聊天消息钩子
  "chat.message"?: (
    input: { sessionID: string; message: Message },
    output: { message: Message },
  ) => Promise<void>;

  // 聊天参数钩子
  "chat.params"?: (
    input: { sessionID: string; params: ChatParams },
    output: { params: ChatParams },
  ) => Promise<void>;

  // 聊天请求头钩子
  "chat.headers"?: (
    input: { sessionID: string; headers: Record<string, string> },
    output: { headers: Record<string, string> },
  ) => Promise<void>;

  // 权限询问钩子
  "permission.ask"?: (
    input: { sessionID: string; permission: Permission },
    output: { approved: boolean },
  ) => Promise<void>;

  // 命令执行前钩子
  "command.execute.before"?: (
    input: { command: string; args: string[] },
    output: { skip?: boolean },
  ) => Promise<void>;

  // 工具执行前钩子
  "tool.execute.before"?: (
    input: { sessionID: string; tool: string; input: unknown },
    output: { skip?: boolean; modifiedInput?: unknown },
  ) => Promise<void>;

  // 工具执行后钩子
  "tool.execute.after"?: (
    input: { sessionID: string; tool: string; result: unknown },
    output: { modifiedResult?: unknown },
  ) => Promise<void>;

  // Shell 环境钩子
  "shell.env"?: (
    input: { cwd: string },
    output: { env: Record<string, string> },
  ) => Promise<void>;
}

// 插件函数类型
export type PluginInstance = (input: PluginInput) => Promise<Hooks | void>;

// 插件输入
export interface PluginInput {
  client: ReturnType<typeof createOpencodeClient>;
  project: Project;
  directory: string;
  worktree: string;
  serverUrl: URL;
  $: typeof Bun.$;
}
```

### 插件示例

```typescript
// packages/opencode-anthropic-auth/src/index.ts
export default async function AnthropicAuthPlugin(
  input: PluginInput,
): Promise<Hooks> {
  return {
    // 认证钩子
    auth: {
      provider: "anthropic",
      authenticate: async ({ apiKey }) => {
        // 验证 API key
        const response = await fetch("https://api.anthropic.com/v1/models", {
          headers: { "x-api-key": apiKey },
        });

        if (!response.ok) {
          throw new Error("Invalid Anthropic API key");
        }

        return {
          token: apiKey,
          expiresAt: null,
        };
      },
    },

    // 配置钩子
    config: async (config) => {
      // 添加 Anthropic 默认配置
      if (!config.providers?.anthropic) {
        config.providers = config.providers || {};
        config.providers.anthropic = {
          baseURL: "https://api.anthropic.com",
          models: ["claude-3-opus", "claude-3-sonnet"],
        };
      }
    },

    // 聊天参数钩子
    "chat.params": async (_input, output) => {
      // 添加默认参数
      output.params = {
        ...output.params,
        maxTokens: output.params.maxTokens || 4096,
      };
    },
  };
}
```

---

## 架构对比与推荐

### 四项目对比

| 特性 | CoPaw | kimi-cli | openclaw | opencode |
|------|-------|----------|----------|----------|
| **发现** | 文件扫描 | 分层目录 | jiti + npm | npm + file |
| **加载** | importlib | 动态导入 | jiti | Bun import |
| **热重载** | ❌ | ❌ | ❌ | ❌ |
| **隔离** | 路径验证 | ❌ | 文件边界 | ❌ |
| **扩展点** | Skills, Channels | Tools, Skills | 10+ 类型 | Hooks |
| **市场** | ClawHub | ❌ | npm | npm |
| **安全** | 目录沙箱 | 信任 | 来源追踪 | 信任 |
| **优先级** | ❌ | 分层覆盖 | Allowlist | ❌ |

### 推荐混合架构

```
┌─────────────────────────────────────────────────────────────┐
│                    Plugin Architecture                      │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                    Discovery (CoPaw + openclaw)       │   │
│  │  - Filesystem scan                                    │   │
│  │  - npm registry                                       │   │
│  │  - GitHub integration                                 │   │
│  └─────────────────────────────────────────────────────┘   │
│                           │                                 │
│                           ▼                                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                    Loading (openclaw jiti)            │   │
│  │  - TypeScript/JavaScript                              │   │
│  │  - SDK aliasing                                       │   │
│  │  - Path validation                                    │   │
│  └─────────────────────────────────────────────────────┘   │
│                           │                                 │
│           ┌───────────────┼───────────────┐                │
│           ▼               ▼               ▼                │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐       │
│  │   Lifecycle  │ │   Security   │ │   Registry   │       │
│  │              │ │              │ │              │       │
│  │ - install    │ │ - path check │ │ - ID-based   │       │
│  │ - enable     │ │ - provenance │ │ - allowlist  │       │
│  │ - disable    │ │ - sandbox    │ │ - versioning │       │
│  └──────────────┘ └──────────────┘ └──────────────┘       │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Extension Points (openclaw + opencode)   │   │
│  │                                                       │   │
│  │  Tools │ Hooks │ Channels │ Providers │ CLI          │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 关键设计建议

1. **发现与加载**
   - 分层目录（项目 > 用户 > 系统）
   - npm 包支持
   - jiti 动态加载 TypeScript

2. **安全与隔离**
   - 路径边界验证
   - 来源追踪（bundled/workspace/npm）
   - Allowlist 配置
   - 提示词注入防护

3. **生命周期**
   - install/enable/disable/uninstall
   - 依赖管理
   - 版本兼容检查

4. **扩展点**
   - Tools：自定义工具
   - Hooks：事件驱动扩展
   - Channels：消息渠道适配
   - Providers：LLM 提供商

---

## 附录：关键代码文件

| 项目 | 关键文件 | 说明 |
|------|----------|------|
| **CoPaw** | `agents/skills_manager.py` | Skills 生命周期 |
| **CoPaw** | `agents/skills_hub.py` | ClawHub 集成 |
| **CoPaw** | `app/channels/registry.py` | Channel 注册 |
| **kimi-cli** | `skill/__init__.py` | 分层技能解析 |
| **kimi-cli** | `tooling/mcp.py` | MCP 集成 |
| **openclaw** | `plugins/loader.ts` | 插件加载 |
| **openclaw** | `plugins/registry.ts` | 插件注册表 |
| **openclaw** | `plugin-sdk/index.ts` | SDK 导出 |
| **opencode** | `plugin/index.ts` | 插件管理 |
| **opencode** | `plugin/src/index.ts` | Hooks 定义 |

---

*报告生成时间: 2025-03-13*
*分析项目: CoPaw, kimi-cli, openclaw, opencode*
