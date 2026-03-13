# dockerfile.md

Template for the Pico/Go tier scaffold. Multi-stage build producing a minimal
static binary in a scratch-like Alpine container.

## Generated File: `Dockerfile`

```dockerfile
# ---------------------------------------------------------------------------
# Stage 1: Build
# ---------------------------------------------------------------------------
FROM golang:1.22-alpine AS builder

RUN apk add --no-cache ca-certificates tzdata

WORKDIR /src

# Cache module downloads
COPY go.mod ./
RUN go mod download

# Copy source and build a fully static binary
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -ldflags="-s -w" -o /app/{{PROJECT_NAME}} .

# ---------------------------------------------------------------------------
# Stage 2: Runtime
# ---------------------------------------------------------------------------
FROM alpine:3.19

RUN apk add --no-cache ca-certificates tzdata \
    && adduser -D -u 1000 appuser

COPY --from=builder /app/{{PROJECT_NAME}} /usr/local/bin/{{PROJECT_NAME}}

USER appuser
WORKDIR /home/appuser

ENV PORT=8080
EXPOSE 8080

ENTRYPOINT ["{{PROJECT_NAME}}"]
```

## Placeholders

| Placeholder | Description |
|-------------|-------------|
| `{{PROJECT_NAME}}` | Name of the compiled binary (matches the Go module name) |
