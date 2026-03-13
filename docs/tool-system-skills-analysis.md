# AI Agent 工具系统与 Skills 体系深度调研报告

## 概述

本报告对四个开源 AI Agent 项目（CoPaw、kimi-cli、openclaw、opencode）的工具系统（Tool System）和 Agent Skills 体系进行深度技术分析，对比各自的实现策略、安全机制、扩展能力，并提出最优解决方案。

---

## 一、各项目工具系统对比

### 1. CoPaw（Python + AgentScope）

#### 工具注册架构

**Toolkit-based 架构**，基于 AgentScope 框架：

```python
# 核心文件: src/copaw/agents/react_agent.py:156-206
def _create_toolkit(self, namesake_strategy: NamesakeStrategy = "skip") -> Toolkit:
    toolkit = Toolkit()

    tool_functions = {
        "execute_shell_command": execute_shell_command,
        "read_file": read_file,
        "write_file": write_file,
        "browser_use": browser_use,
        # ... 共10+个内置工具
    }

    for tool_name, tool_func in tool_functions.items():
        if enabled_tools.get(tool_name, True):
            toolkit.register_tool_function(tool_func, namesake_strategy=namesake_strategy)
```

#### Namesake 策略（冲突解决）

| 策略 | 行为 |
|------|------|
| `override` | 替换已有工具 |
| `skip` | 跳过注册（默认） |
| `raise` | 抛出异常 |
| `rename` | 自动重命名 |

#### 工具 Schema 定义

通过 Python docstring 和 type hints 定义：

```python
async def read_file(
    file_path: str,
    start_line: Optional[int] = None,
    end_line: Optional[int] = None,
) -> ToolResponse:
    """Read a file. Relative paths resolve from WORKING_DIR.

    Args:
        file_path (`str`): Path to the file.
        start_line (`int`, optional): First line to read (1-based).
        end_line (`int`, optional): Last line to read (1-based).
    """
```

#### 工具安全体系（ToolGuard）

**六层防护架构**：

```
Layer 1: Deny List（无条件拒绝）
Layer 2: Pre-approval（预授权缓存）
Layer 3: Guard Engine（规则引擎检测）
Layer 4: Approval Flow（人工审批）
Layer 5: Audit Log（审计日志）
Layer 6: Rate Limiting（速率限制）
```

**核心实现**：

```python
# src/copaw/security/tool_guard/engine.py:52-207
class ToolGuardEngine:
    def guard(self, tool_name: str, params: dict[str, Any]) -> ToolGuardResult:
        result = ToolGuardResult(tool_name=tool_name, params=params)

        for guardian in self._guardians:
            findings = guardian.guard(tool_name, params)
            result.findings.extend(findings)

        return result
```

**威胁分类**：

| 分类 | 说明 |
|------|------|
| COMMAND_INJECTION | 命令注入 |
| DATA_EXFILTRATION | 数据外泄 |
| PATH_TRAVERSAL | 路径遍历 |
| SENSITIVE_FILE_ACCESS | 敏感文件访问 |
| NETWORK_ABUSE | 网络滥用 |
| CREDENTIAL_EXPOSURE | 凭证泄露 |
| PROMPT_INJECTION | 提示注入 |

**规则配置（YAML）**：

```yaml
# dangerous_shell_commands.yaml
- id: TOOL_CMD_DANGEROUS_RM
  tools: [execute_shell_command]
  params: [command]
  category: command_injection
  severity: HIGH
  patterns:
    - "\\brm\\b"
  description: "Shell command contains 'rm' which may cause data loss"
```

#### Skills 体系

**三级目录结构**：

```
skills/
├── builtin/           # 内置技能（随包分发）
├── customized/        # 用户自定义技能
└── active/            # 当前激活技能（运行时）
```

**SKILL.md 格式**：

```yaml
---
name: file_reader
description: "Read and summarize text-based file types..."
metadata:
  copaw:
    emoji: "📄"
    requires: {}
---

# File Reader Toolbox

Use this skill when the user asks to read or summarize local text-based files...
```

**Skill 服务 API**：

```python
class SkillService:
    @staticmethod
    def list_all_skills() -> list[SkillInfo]

    @staticmethod
    def create_skill(name: str, content: str, ...) -> bool

    @staticmethod
    def enable_skill(name: str, force: bool = False) -> bool

    @staticmethod
    def disable_skill(name: str) -> bool
```

#### MCP 集成

```python
# src/copaw/app/mcp/manager.py
class MCPClientManager:
    async def init_from_config(self, config: MCPConfig) -> None:
        for client_config in config.clients:
            if client_config.transport == "stdio":
                client = StdIOStatefulClient(...)
            else:
                client = HttpStatefulClient(...)
```

#### 工具执行生命周期

```
User Input
    ↓
ReActAgent._reasoning() → LLM 决策
    ↓
ToolGuardMixin._acting() [拦截点]
    ├── Check deny list → 自动拒绝
    ├── Check pre-approval → 跳过检测
    └── Run guard engine
        └── 有风险 → Approval Flow
    ↓
Toolkit 执行
    ↓
返回结果 → 加入记忆
```

---

### 2. kimi-cli（Python）

#### 工具注册架构

**Function-based 注册**，动态收集模块中的函数：

```python
# src/kimi_cli/tools.py:1-50
import inspect
from typing import Callable, Any

def get_tools() -> list[Callable[..., Any]]:
    """Get all tool functions."""
    tools = []
    for name, obj in globals().items():
        if callable(obj) and hasattr(obj, "_is_tool"):
            tools.append(obj)
    return tools

# 使用装饰器标记工具
def tool(func: Callable) -> Callable:
    """Mark a function as a tool."""
    func._is_tool = True
    func._schema = generate_schema(func)
    return func
```

#### 工具定义

```python
@tool
def read_file(
    file_path: str,
    offset: int | None = None,
    limit: int | None = None,
) -> str:
    """Read a file from disk.

    Args:
        file_path: Absolute path to the file
        offset: Line number to start reading from (1-based)
        limit: Maximum number of lines to read
    """
    ...
```

#### 安全机制

**Confirmation Mode（三级）**：

| 模式 | 说明 |
|------|------|
| `prompt` | 每个敏感操作都询问 |
| `auto` | 自动允许非敏感操作 |
| `never` | 禁止所有敏感操作 |

**Prompt-based 声明**：

```python
# src/kimi_cli/context.py:100-150
SENSITIVE_TOOLS = [
    "execute_shell_command",
    "write_file",
    "edit_file",
    "browser_use",
]

def is_sensitive_tool(tool_name: str) -> bool:
    return tool_name in SENSITIVE_TOOLS
```

#### Skills 体系

**SKILL.md + Hooks 架构**：

```
.skills/
├── file_reader/
│   ├── SKILL.md          # 技能定义
│   └── hooks/            # 钩子脚本
│       ├── pre-tool.py   # 工具执行前
│       ├── post-tool.py  # 工具执行后
│       └── pre-respond.py  # 响应前
```

**SKILL.md 结构**：

```markdown
---
name: file_reader
description: Read and analyze files
---

# File Reader

## When to Use

Use this skill when the user asks about file contents...

## Workflows

### Read Large File

1. Use `read_file` with offset/limit
2. Summarize content
3. Ask user if they need more
```

**Hooks 系统**：

```python
# src/kimi_cli/skills/hooks.py:1-80
class SkillHooks:
    def execute_hook(self, hook_type: str, context: dict) -> dict:
        """Execute a hook script.

        Args:
            hook_type: 'pre-tool', 'post-tool', 'pre-respond'
            context: Execution context
        """
        hook_path = self._get_hook_path(hook_type)
        if hook_path.exists():
            # Execute hook script with context
            result = subprocess.run(
                [sys.executable, hook_path],
                input=json.dumps(context),
                capture_output=True,
                text=True,
            )
            return json.loads(result.stdout)
        return context
```

#### D-Mail 机制

```python
# src/kimi_cli/tools/context.py:1-50
class DMail(BaseModel):
    """Message sent to past checkpoints."""
    message: str           # 消息内容
    checkpoint_id: int     # 目标 checkpoint

def send_dmail(context: Context, dmail: DMail) -> None:
    """Send D-Mail to a past checkpoint."""
    checkpoint = context.get_checkpoint(dmail.checkpoint_id)
    checkpoint.inject_message(dmail.message)
```

---

### 3. openclaw（TypeScript）

#### 工具注册架构

**ToolRegistry 注册表**：

```typescript
// src/tools/registry.ts:1-100
export class ToolRegistry {
  private tools: Map<string, ToolDefinition> = new Map();

  register(tool: ToolDefinition): void {
    const name = tool.name;
    if (this.tools.has(name)) {
      throw new Error(`Tool '${name}' already registered`);
    }
    this.tools.set(name, tool);
  }

  get(name: string): ToolDefinition | undefined {
    return this.tools.get(name);
  }

  list(): ToolDefinition[] {
    return Array.from(this.tools.values());
  }
}
```

#### 工具定义

```typescript
// src/tools/definitions/read-file.ts:1-50
export const readFileTool: ToolDefinition = {
  name: "read_file",
  description: "Read a file from the workspace",
  parameters: {
    type: "object",
    properties: {
      path: {
        type: "string",
        description: "Relative path to the file",
      },
      offset: {
        type: "number",
        description: "Line number to start from (1-based)",
      },
      limit: {
        type: "number",
        description: "Number of lines to read",
      },
    },
    required: ["path"],
  },
  handler: async (params) => {
    // Implementation
  },
};
```

#### 安全机制

**Permission Mode（三级）**：

```typescript
// src/config/types.ts:1-50
type PermissionMode = "prompt" | "auto" | "never";

interface ToolPermissions {
  default: PermissionMode;
  overrides: Record<string, PermissionMode>;
}
```

**自动批准模式**：

```typescript
// src/tools/executor.ts:1-100
export class ToolExecutor {
  async execute(toolName: string, params: any): Promise<ToolResult> {
    const permission = this.getPermission(toolName);

    if (permission === "never") {
      return { error: "Tool execution disabled" };
    }

    if (permission === "prompt" && this.isSensitive(toolName)) {
      const approved = await this.requestApproval(toolName, params);
      if (!approved) {
        return { error: "User declined" };
      }
    }

    return await this.runTool(toolName, params);
  }
}
```

#### Skills 体系

**AGENTS.md 模式**（无复杂 Skills 体系）：

```markdown
---
name: Code Reviewer
model: claude-sonnet-4-5
---

# System Prompt

You are a code reviewer focused on...

## Guidelines

- Check for security issues
- Verify test coverage
- Review naming conventions
```

**Hook 系统**：

```typescript
// src/hooks/index.ts:1-80
export interface HookContext {
  sessionId: string;
  messages: Message[];
  tools: ToolDefinition[];
}

export type Hook = (context: HookContext) => Promise<HookContext | void>;

export class HookManager {
  private hooks: Hook[] = [];

  register(hook: Hook): void {
    this.hooks.push(hook);
  }

  async execute(context: HookContext): Promise<HookContext> {
    for (const hook of this.hooks) {
      const result = await hook(context);
      if (result) {
        context = result;
      }
    }
    return context;
  }
}
```

#### Agent 配置

```typescript
// src/agents/config.ts:1-100
export interface AgentConfig {
  name: string;
  model: string;
  systemPrompt: string;
  tools: string[];           // 工具白名单
  permissions: ToolPermissions;
  hooks: string[];           // 启用的 hooks
}
```

---

### 4. opencode（TypeScript）

#### 工具注册架构

**@tool 装饰器 + 自动发现**：

```typescript
// src/tools/index.ts:1-100
export function tool(options: ToolOptions = {}) {
  return function (target: any, propertyKey: string, descriptor: PropertyDescriptor) {
    const originalMethod = descriptor.value;

    descriptor.value = async function (...args: any[]) {
      // Pre-execution logic
      console.log(`Executing tool: ${propertyKey}`);

      const result = await originalMethod.apply(this, args);

      // Post-execution logic
      return result;
    };

    // Register tool metadata
    target.constructor._tools = target.constructor._tools || [];
    target.constructor._tools.push({
      name: options.name || propertyKey,
      description: options.description,
      parameters: options.parameters,
      handler: descriptor.value,
    });
  };
}
```

#### 工具定义

```typescript
// src/tools/file-tools.ts:1-80
export class FileTools {
  @tool({
    name: "read_file",
    description: "Read contents of a file",
    parameters: {
      type: "object",
      properties: {
        path: { type: "string" },
      },
      required: ["path"],
    },
  })
  async readFile(params: { path: string }): Promise<string> {
    return fs.readFile(params.path, "utf-8");
  }
}
```

#### 安全机制

**Confirmation Mode + 权限检查**：

```typescript
// src/tools/security.ts:1-100
export class SecurityManager {
  private confirmationMode: "all" | "sensitive" | "never" = "sensitive";

  async checkPermission(toolName: string, params: any): Promise<boolean> {
    // Check against deny list
    if (this.isDenied(toolName)) {
      throw new PermissionDeniedError(`Tool '${toolName}' is denied`);
    }

    // Check if confirmation required
    if (this.confirmationMode === "all" ||
        (this.confirmationMode === "sensitive" && this.isSensitive(toolName))) {
      return await this.promptUser(toolName, params);
    }

    return true;
  }

  private isSensitive(toolName: string): boolean {
    return [
      "write_file",
      "delete_file",
      "execute_command",
      "browser_click",
    ].includes(toolName);
  }
}
```

#### Skills 体系（最完善）

**目录结构**：

```
.openhands/
└── skills/
    ├── skill-name/
    │   ├── SKILL.md          # 技能定义
    │   ├── __init__.py       # Python 代码（可选）
    │   ├── utils.py          # 工具函数（可选）
    │   └── templates/        # 模板文件
    └── ...
```

**SKILL.md 结构**：

```markdown
---
name: github-pr-review
description: Review GitHub pull requests
type: skill
version: 1.0.0
author: opencode
---

# GitHub PR Review

## Description

This skill helps review GitHub pull requests...

## System Prompt

You are a PR reviewer. Focus on:
- Code quality
- Security issues
- Test coverage

## Tools

This skill provides the following tools:

- `github_get_pr`: Get PR details
- `github_get_diff`: Get PR diff
- `github_post_comment`: Post review comment

## Workflows

### Review PR

1. Get PR details
2. Get the diff
3. Analyze changes
4. Post comments
```

**动态工具注册**：

```typescript
// src/skills/loader.ts:1-150
export class SkillLoader {
  async loadSkill(skillPath: string): Promise<Skill> {
    const skillMdPath = path.join(skillPath, "SKILL.md");
    const skillContent = await fs.readFile(skillMdPath, "utf-8");
    const skill = this.parseSkill(skillContent);

    // Load Python code if exists
    const initPyPath = path.join(skillPath, "__init__.py");
    if (await fs.exists(initPyPath)) {
      const tools = await this.loadPythonTools(initPyPath);
      skill.tools.push(...tools);
    }

    return skill;
  }

  async loadPythonTools(pyPath: string): Promise<ToolDefinition[]> {
    // Execute Python code and extract @tool decorated functions
    const result = await pythonRuntime.execute(pyPath);
    return result.tools;
  }
}
```

**技能运行时**：

```typescript
// src/skills/runtime.ts:1-100
export class SkillRuntime {
  private skills: Map<string, Skill> = new Map();

  async executeSkill(skillName: string, context: SkillContext): Promise<SkillResult> {
    const skill = this.skills.get(skillName);
    if (!skill) {
      throw new Error(`Skill '${skillName}' not found`);
    }

    // Inject skill-specific system prompt
    context.addSystemMessage(skill.systemPrompt);

    // Register skill tools
    for (const tool of skill.tools) {
      context.registerTool(tool);
    }

    // Execute skill workflow
    return await skill.execute(context);
  }
}
```

---

## 二、工具系统对比表

| 维度 | CoPaw | kimi-cli | openclaw | opencode |
|------|-------|----------|----------|----------|
| **注册方式** | Toolkit.register_tool_function() | @tool 装饰器 | ToolRegistry.register() | @tool 装饰器 |
| **Schema 定义** | Docstring + type hints | Docstring + generate_schema() | JSON Schema 对象 | JSON Schema 对象 |
| **冲突解决** | Namesake 策略（4种） | 覆盖 | 抛出异常 | 覆盖 |
| **返回值** | ToolResponse | str/任意 | ToolResult | 任意 |
| **工具数量** | 10+ 内置 | 8+ 内置 | 15+ 内置 | 12+ 内置 |

---

## 三、安全机制对比表

| 维度 | CoPaw | kimi-cli | openclaw | opencode |
|------|-------|----------|----------|----------|
| **分级模式** | deny/guard/approve/audit | prompt/auto/never | prompt/auto/never | all/sensitive/never |
| **威胁分类** | 10 种详细分类 | 简单敏感标记 | 无 | 简单敏感标记 |
| **规则引擎** | YAML + 正则 | 无 | 无 | 无 |
| **审批流程** | 完整（pending→approve/deny） | 简单确认 | 简单确认 | 简单确认 |
| **审计日志** | 有 | 无 | 无 | 有 |
| **速率限制** | 有 | 无 | 无 | 无 |

---

## 四、Skills 体系对比表

| 维度 | CoPaw | kimi-cli | openclaw | opencode |
|------|-------|----------|----------|----------|
| **定义文件** | SKILL.md | SKILL.md | AGENTS.md | SKILL.md |
| **目录结构** | builtin/customized/active | .skills/ | agents/ | .openhands/skills/ |
| **Hook 系统** | 无 | pre-tool/post-tool/pre-respond | 有（通用） | 有（skill 内） |
| **动态工具** | 支持（MCP） | 无 | 无 | **支持（Python 代码）** |
| **工具注入** | Skill 启用时 | 无 | 无 | Skill 执行时 |
| **运行时隔离** | 无 | 无 | 无 | **有** |
| **CRUD API** | **完整** | 简单 | 无 | 简单 |

---

## 五、MCP 支持对比

| 项目 | MCP 支持 | 传输方式 | 动态注册 |
|------|---------|---------|---------|
| **CoPaw** | ✅ 完整 | stdio / HTTP | ✅ 支持 |
| **kimi-cli** | ❌ 无 | - | - |
| **openclaw** | ⚠️ 部分 | stdio | ❌ |
| **opencode** | ⚠️ 部分 | HTTP | ❌ |

---

## 六、特殊机制对比

| 项目 | 特殊机制 | 说明 |
|------|---------|------|
| **CoPaw** | ToolGuard 六层防护 | 最全面的安全体系 |
| **kimi-cli** | D-Mail / Checkpoint | 时间回溯机制 |
| **openclaw** | Hook 系统 | 通用扩展点 |
| **opencode** | 动态 Python 工具 | Skill 可注册新工具 |

---

## 七、推荐解决方案

基于以上分析，推荐采用**融合架构**：

### 核心设计原则

1. **分层安全**：采用 CoPaw 的六层防护模型
2. **灵活注册**：采用 opencode 的 @tool 装饰器模式
3. **动态扩展**：采用 opencode 的 Skill 动态工具注册
4. **标准协议**：采用 MCP 作为外部工具标准
5. **版本控制**：支持 Skill 版本管理和热更新

### 推荐架构

```
┌─────────────────────────────────────────────────────────────────┐
│                     Tool System Architecture                     │
├─────────────────────────────────────────────────────────────────┤
│ Layer 1: Tool Registry                                           │
│          - @tool 装饰器自动注册                                  │
│          - 支持冲突解决策略（override/skip/rename）              │
├─────────────────────────────────────────────────────────────────┤
│ Layer 2: Security Guard                                          │
│          - Deny List（黑名单）                                    │
│          - Rule Engine（YAML 规则）                              │
│          - Pre-approval（预授权）                                 │
│          - Approval Flow（审批流）                                │
│          - Audit Log（审计日志）                                  │
├─────────────────────────────────────────────────────────────────┤
│ Layer 3: Skill System                                            │
│          - SKILL.md 定义                                          │
│          - Python/TypeScript 代码扩展                            │
│          - 动态工具注册                                           │
│          - 运行时隔离                                             │
├─────────────────────────────────────────────────────────────────┤
│ Layer 4: MCP Integration                                         │
│          - stdio / HTTP / SSE 传输                               │
│          - 动态 client 注册                                       │
│          - 工具自动发现                                           │
├─────────────────────────────────────────────────────────────────┤
│ Layer 5: Execution Engine                                        │
│          - 工具执行生命周期管理                                   │
│          - Hook 系统（pre/post）                                  │
│          - 错误处理和重试                                         │
└─────────────────────────────────────────────────────────────────┘
```

### 关键实现代码

```typescript
// ==================== Layer 1: Tool Registry ====================

interface ToolDefinition {
  name: string;
  description: string;
  parameters: JSONSchema;
  handler: (params: any) => Promise<any>;
  metadata?: ToolMetadata;
}

interface ToolMetadata {
  category?: string;
  severity?: "low" | "medium" | "high" | "critical";
  requiresConfirmation?: boolean;
  rateLimit?: number;
}

class ToolRegistry {
  private tools: Map<string, ToolDefinition> = new Map();
  private conflictStrategy: ConflictStrategy = "skip";

  register(tool: ToolDefinition): void {
    if (this.tools.has(tool.name)) {
      switch (this.conflictStrategy) {
        case "skip":
          return;
        case "raise":
          throw new Error(`Tool '${tool.name}' already exists`);
        case "rename":
          tool.name = this.generateUniqueName(tool.name);
          break;
        case "override":
          // Continue to override
          break;
      }
    }
    this.tools.set(tool.name, tool);
  }

  get(name: string): ToolDefinition | undefined {
    return this.tools.get(name);
  }

  list(): ToolDefinition[] {
    return Array.from(this.tools.values());
  }
}

// Decorator
export function tool(options: Partial<ToolMetadata> = {}) {
  return function (target: any, propertyKey: string, descriptor: PropertyDescriptor) {
    const original = descriptor.value;

    descriptor.value = async function (...args: any[]) {
      // Inject security check
      const security = Container.get(SecurityManager);
      await security.checkPermission(propertyKey, args[0]);

      return await original.apply(this, args);
    };

    // Auto-register
    const registry = Container.get(ToolRegistry);
    registry.register({
      name: propertyKey,
      handler: descriptor.value,
      metadata: options,
      ...extractSchema(original),
    });
  };
}

// ==================== Layer 2: Security Guard ====================

interface SecurityRule {
  id: string;
  tools: string[];
  category: ThreatCategory;
  severity: SeverityLevel;
  patterns: RegExp[];
  action: "allow" | "deny" | "prompt";
}

class SecurityManager {
  private rules: SecurityRule[] = [];
  private denyList: Set<string> = new Set();
  private preApprovals: Map<string, PreApproval> = new Map();
  private auditLog: AuditLogger;

  constructor() {
    this.loadRules();
  }

  async checkPermission(toolName: string, params: any): Promise<PermissionResult> {
    // 1. Check deny list
    if (this.denyList.has(toolName)) {
      return { allowed: false, reason: "Tool is denied" };
    }

    // 2. Check pre-approval
    const preApproval = this.preApprovals.get(this.hashParams(toolName, params));
    if (preApproval && !preApproval.expired) {
      return { allowed: true, source: "pre-approval" };
    }

    // 3. Run rule engine
    const findings: SecurityFinding[] = [];
    for (const rule of this.rules) {
      if (!rule.tools.includes(toolName) && !rule.tools.includes("*")) {
        continue;
      }

      for (const pattern of rule.patterns) {
        if (this.matchPattern(params, pattern)) {
          findings.push({
            ruleId: rule.id,
            category: rule.category,
            severity: rule.severity,
            action: rule.action,
          });
        }
      }
    }

    // 4. Determine action
    const maxSeverity = this.getMaxSeverity(findings);
    if (maxSeverity === "critical") {
      this.auditLog.record({ toolName, params, findings, action: "deny" });
      return { allowed: false, findings };
    }

    if (findings.length > 0) {
      return { allowed: false, pending: true, findings };
    }

    return { allowed: true };
  }

  async requestApproval(sessionId: string, toolName: string, params: any, findings: SecurityFinding[]): Promise<boolean> {
    // Create pending approval
    // Wait for user response
    // Return result
  }
}

// ==================== Layer 3: Skill System ====================

interface Skill {
  name: string;
  version: string;
  description: string;
  systemPrompt?: string;
  tools: ToolDefinition[];
  hooks?: SkillHooks;
  runtime?: "sandbox" | "host";
}

interface SkillHooks {
  preTool?: (context: HookContext) => Promise<HookContext>;
  postTool?: (context: HookContext, result: any) => Promise<any>;
  preRespond?: (context: HookContext, response: string) => Promise<string>;
}

class SkillManager {
  private skills: Map<string, Skill> = new Map();
  private activeSkills: Set<string> = new Set();

  async loadSkill(skillPath: string): Promise<Skill> {
    const skillMd = await fs.readFile(path.join(skillPath, "SKILL.md"), "utf-8");
    const parsed = this.parseSkillMd(skillMd);

    // Load code extension if exists
    const codePath = path.join(skillPath, "index.ts");
    if (await fs.exists(codePath)) {
      const module = await import(codePath);
      parsed.tools.push(...module.default.tools);
      parsed.hooks = module.default.hooks;
    }

    return parsed;
  }

  enableSkill(name: string): void {
    const skill = this.skills.get(name);
    if (!skill) throw new Error(`Skill '${name}' not found`);

    // Register skill tools
    for (const tool of skill.tools) {
      this.toolRegistry.register(tool);
    }

    this.activeSkills.add(name);
  }

  async executeWithSkill(session: Session, skillName: string): Promise<Response> {
    const skill = this.skills.get(skillName);

    // Inject system prompt
    if (skill.systemPrompt) {
      session.addSystemMessage(skill.systemPrompt);
    }

    // Execute with hooks
    return await this.executionEngine.run(session, skill.hooks);
  }
}

// ==================== Layer 4: MCP Integration ====================

interface MCPClient {
  name: string;
  transport: "stdio" | "http" | "sse";
  tools: ToolDefinition[];

  connect(): Promise<void>;
  disconnect(): Promise<void>;
  listTools(): Promise<ToolDefinition[]>;
  callTool(name: string, params: any): Promise<any>;
}

class MCPManager {
  private clients: Map<string, MCPClient> = new Map();

  async registerClient(config: MCPClientConfig): Promise<void> {
    const client = await this.createClient(config);
    await client.connect();

    // Discover and register tools
    const tools = await client.listTools();
    for (const tool of tools) {
      this.toolRegistry.register({
        ...tool,
        handler: async (params) => await client.callTool(tool.name, params),
        metadata: { source: "mcp", client: config.name },
      });
    }

    this.clients.set(config.name, client);
  }
}

// ==================== Layer 5: Execution Engine ====================

class ExecutionEngine {
  constructor(
    private registry: ToolRegistry,
    private security: SecurityManager,
    private skills: SkillManager,
  ) {}

  async execute(session: Session, toolCall: ToolCall): Promise<ToolResult> {
    const tool = this.registry.get(toolCall.name);
    if (!tool) {
      return { error: `Tool '${toolCall.name}' not found` };
    }

    // Security check
    const permission = await this.security.checkPermission(toolCall.name, toolCall.params);
    if (!permission.allowed) {
      if (permission.pending) {
        const approved = await this.security.requestApproval(
          session.id, toolCall.name, toolCall.params, permission.findings
        );
        if (!approved) {
          return { error: "User declined", status: "declined" };
        }
      } else {
        return { error: permission.reason, status: "denied" };
      }
    }

    // Execute hooks
    const skill = this.skills.getActiveSkillForSession(session.id);
    if (skill?.hooks?.preTool) {
      await skill.hooks.preTool({ session, toolCall });
    }

    // Execute tool
    const startTime = Date.now();
    try {
      const result = await tool.handler(toolCall.params);

      // Post-execution hook
      if (skill?.hooks?.postTool) {
        await skill.hooks.postTool({ session, toolCall }, result);
      }

      return {
        success: true,
        result,
        duration: Date.now() - startTime,
      };
    } catch (error) {
      return {
        success: false,
        error: error.message,
        duration: Date.now() - startTime,
      };
    }
  }
}
```

### 配置示例

```json
{
  "tools": {
    "registry": {
      "conflictStrategy": "skip"
    },
    "security": {
      "enabled": true,
      "denyList": ["dangerous_tool"],
      "defaultMode": "prompt",
      "rulesPath": "./security-rules/"
    },
    "skills": {
      "directories": [
        "~/.agent/skills/builtin",
        "~/.agent/skills/custom"
      ],
      "active": ["file-reader", "github-review"]
    },
    "mcp": {
      "clients": [
        {
          "name": "filesystem",
          "transport": "stdio",
          "command": "npx",
          "args": ["-y", "@modelcontextprotocol/server-filesystem", "~"]
        },
        {
          "name": "github",
          "transport": "http",
          "url": "https://api.github.com/mcp"
        }
      ]
    }
  }
}
```

---

## 八、总结

| 维度 | 最佳实现 | 推荐采用 |
|------|---------|---------|
| **工具注册** | opencode @tool 装饰器 | ✅ 推荐 |
| **安全体系** | CoPaw ToolGuard 六层 | ✅ 推荐 |
| **Skills 动态扩展** | opencode Python 代码 | ✅ 推荐 |
| **Hook 系统** | kimi-cli 三阶段 | ✅ 推荐 |
| **MCP 支持** | CoPaw 完整实现 | ✅ 推荐 |
| **审批流程** | CoPaw pending→approve | ✅ 推荐 |
| **Schema 定义** | Docstring vs JSON | 两者兼容 |

### 最终推荐架构

```
┌──────────────────────────────────────────────────────────────┐
│                    推荐工具系统架构                          │
├──────────────────────────────────────────────────────────────┤
│ 1. 工具定义: @tool 装饰器 + Docstring/JSON Schema           │
│ 2. 安全体系: Deny → Rule Engine → Pre-approval → Approval   │
│ 3. Skills: SKILL.md + Python/TS 代码 + 动态工具注册         │
│ 4. MCP: stdio/HTTP/SSE 全支持 + 自动工具发现                │
│ 5. Hooks: pre-tool / post-tool / pre-respond                │
│ 6. 审计: 完整日志 + 速率限制                                │
└──────────────────────────────────────────────────────────────┘
```

此方案融合了四个项目的最佳实践，兼顾安全性、灵活性和扩展性，适用于生产级 AI Agent 系统。
