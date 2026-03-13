# pyproject.toml.md

Template for the Standard/Python tier scaffold.

## Generated File: `pyproject.toml`

```toml
[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[project]
name = "{{PROJECT_NAME_SLUG}}"
version = "0.1.0"
description = "{{PROJECT_DESCRIPTION}}"
readme = "README.md"
license = "MIT"
requires-python = ">=3.11"
authors = [
    { name = "{{AUTHOR_NAME}}", email = "{{AUTHOR_EMAIL}}" },
]
keywords = ["ai", "agent", "assistant"]
classifiers = [
    "Development Status :: 3 - Alpha",
    "Programming Language :: Python :: 3",
    "Programming Language :: Python :: 3.11",
    "Programming Language :: Python :: 3.12",
    "Typing :: Typed",
]

dependencies = [
    "httpx>=0.27,<1",
    "pydantic>=2.6,<3",
    "pydantic-settings>=2.2,<3",
    "python-dotenv>=1.0,<2",
]

[project.optional-dependencies]
dev = [
    "pytest>=8.0,<9",
    "pytest-asyncio>=0.23,<1",
    "ruff>=0.3,<1",
    "mypy>=1.9,<2",
]

[project.scripts]
{{CLI_COMMAND}} = "{{PACKAGE_NAME}}.__main__:main"

[project.urls]
Homepage = "{{PROJECT_URL}}"
Repository = "{{REPOSITORY_URL}}"

# ---------------------------------------------------------------------------
# Tool configuration
# ---------------------------------------------------------------------------

[tool.ruff]
target-version = "py311"
line-length = 99

[tool.ruff.lint]
select = ["E", "F", "I", "N", "UP", "B", "A", "SIM", "TCH"]
ignore = ["E501"]

[tool.ruff.lint.isort]
known-first-party = ["{{PACKAGE_NAME}}"]

[tool.mypy]
python_version = "3.11"
strict = true
warn_return_any = true
warn_unused_configs = true

[tool.pytest.ini_options]
testpaths = ["tests"]
asyncio_mode = "auto"
```

## Placeholders

| Placeholder | Description |
|-------------|-------------|
| `{{PROJECT_NAME_SLUG}}` | PyPI-compatible project name, lowercase with hyphens (e.g. `my-assistant`) |
| `{{PROJECT_DESCRIPTION}}` | One-line project description |
| `{{AUTHOR_NAME}}` | Author full name |
| `{{AUTHOR_EMAIL}}` | Author email address |
| `{{CLI_COMMAND}}` | CLI entry-point command name (e.g. `my-assistant`) |
| `{{PACKAGE_NAME}}` | Python package name used in imports (e.g. `my_assistant`) |
| `{{PROJECT_URL}}` | Project homepage URL |
| `{{REPOSITORY_URL}}` | Source repository URL |
