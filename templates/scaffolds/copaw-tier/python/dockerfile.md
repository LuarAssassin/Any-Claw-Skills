# dockerfile.md

Template for the Standard/Python tier scaffold.

## Generated File: `Dockerfile`

```dockerfile
# ---------------------------------------------------------------------------
# {{PROJECT_NAME}} - production container
# ---------------------------------------------------------------------------
# Multi-stage build: install dependencies in a builder stage, then copy only
# the installed packages into a slim runtime image.
# ---------------------------------------------------------------------------

# -- builder ------------------------------------------------------------------
FROM python:3.12-slim AS builder

WORKDIR /build

# Install build tools (kept out of the final image)
RUN pip install --no-cache-dir --upgrade pip setuptools wheel

# Copy only dependency metadata first for better layer caching
COPY pyproject.toml README.md ./
COPY {{PACKAGE_NAME}}/__init__.py {{PACKAGE_NAME}}/__init__.py

# Install project + dependencies into a virtual-env we will copy later
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --no-cache-dir .

# Copy the full source and reinstall so the package code is present
COPY . .
RUN pip install --no-cache-dir .

# -- runtime ------------------------------------------------------------------
FROM python:3.12-slim AS runtime

LABEL maintainer="{{AUTHOR_EMAIL}}"
LABEL description="{{PROJECT_DESCRIPTION}}"

# Create a non-root user
RUN groupadd --gid 1000 app && \
    useradd --uid 1000 --gid app --create-home app

WORKDIR /home/app

# Copy the virtual-env from the builder
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

USER app

# Health-check (override if the project exposes an HTTP endpoint)
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD python -c "import {{PACKAGE_NAME}}; print('ok')" || exit 1

EXPOSE {{PORT}}

CMD ["python", "-m", "{{PACKAGE_NAME}}"]
```

## Placeholders

| Placeholder | Description |
|-------------|-------------|
| `{{PROJECT_NAME}}` | Human-readable project name shown in labels |
| `{{PACKAGE_NAME}}` | Python package name (e.g. `my_assistant`) |
| `{{AUTHOR_EMAIL}}` | Maintainer email for the Docker label |
| `{{PROJECT_DESCRIPTION}}` | One-line description for the Docker label |
| `{{PORT}}` | Port the application listens on (e.g. `8000`) |
