# Docker in the Real World (Production Edition)

This week focuses on writing production-grade Dockerfiles, understanding why best practices exist, and learning how to debug containers like a real DevOps engineer.

## 1. Before We Optimise - we learn how to debug

Before teaching “good Dockerfiles”, we need to learn how to look inside a container.

✔️ Running containers
`docker ps`


Shows all active containers.

✔️ Viewing logs
`docker logs <container>`


Useful when:

- app crashes

- app fails to start

- healthchecks fail

✔️ Entering a container
`docker exec -it <container> sh`


Allows inspecting:

- filesystem

- installed deps

- processes

- config

- permissions

✔️ Inspecting full container metadata
`docker inspect <container> | jq`


Shows:

- env vars

- entrypoint

- mounts

- IP address

- networks

✔️ Debugging build failures
`docker build --progress=plain .`


Shows full build logs.

✔️ Running a “broken” image with a shell
`docker run --rm -it --entrypoint sh myimage`


Ignores CMD/ENTRYPOINT → gives you access to debug.

- MINI DEMO!

## 2. What makes a good production-like Dockerfile?

These are my 3 core principles for writing production-like Dockerfiles:

- Small: minimize image size
  - faster builds
  - faster pulls
  - faster ECS cold starts
  - fewer CVEs

- Secure: minimize attack surface
  - non-root user
  - minimal OS
  - no package managers in final image
  - limited attack sur

- Predictable: build consistently
  - pinned versions
  - pinned image tags
  - stable layers
  - deterministic builds

If these aren't met, you cannot call it a production-like Dockerfile.

## 3. Bad vs Good Dockerfiles

### Bad Example

```dockerfile
FROM node:latest
WORKDIR /app
COPY . .
RUN npm install
EXPOSE 3000
CMD ["node", "index.js"]
```

- What are the issues with this?


### Good Example (Production)

```dockerfile
FROM node:20-alpine:SHA256.hash.... AS base

WORKDIR /app

COPY package*.json .
RUN npm ci --only=production

COPY . .

RUN addgroup -S app && adduser -S app -G app
USER app

EXPOSE 3000
CMD ["node", "index.js"]
```

What are the improvements with this?

## 4. Multi-Stage Builds (Deep Overview)

### Why multi-stage?

Your build environment is often huge (e.g. Node, Go, Java, .NET).

Your runtime environment should be tiny.

### Example (Go)

```dockerfile
FROM golang:1.22 AS builder
WORKDIR /app
COPY . .
RUN CGO_ENABLED=0 go build -o server .

FROM gcr.io/distroless/static-debian12
COPY --from=builder /app/server /server
CMD ["/server"]
```

### What are the benefits of this?

Base Images — When to Use Which?

Image Type | Pros | Cons | Use cases
|----------|------|------|------------
| Full | Popular, mature, stable | Larger, less secure | Full-stack applications, dev/testing
| Distroless | Tiny, secure, no package manager | Limited functionality | Microservices, CLI tools
| Alpine | Small, fast, secure | Limited ecosystem | Web servers, APIs, Go/Node
| Slim | Small, fast, secure | Limited ecosystem | Web servers, APIs
| Scratch | Tiny, secure, no package manager | Limited functionality | Microservices, CLI tools, go static binaries

## Production Dockerfile Best Practices

1. Base image must be pinned

```dockerfile
FROM python:3.12.3-slim
```

2. Base images must be pinned with a SHA256 hash

```dockerfile
FROM python:3.12.3-slim@sha256:1234567890
```

3. Dependency files first (caching)

```dockerfile
COPY package*.json .
RUN npm ci
COPY . .
```

4. Layer Optimisation

```dockerfile
# Combine RUN commands to reduce layers
RUN apt-get update && apt-get install -y \
    curl \
    git \
 && rm -rf /var/lib/apt/lists/*

# Order by change frequency (least > most)
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
```

5. Use .dockerignore aggressively

```dockerfile
## create a .dockerignore file and add the following:
# .git, node_modules, *.md, .env, test/, docs/
```

5. Use multi-stage builds

```dockerfile
# Builder stage
FROM golang:1.22@sha256:... AS builder
WORKDIR /build
COPY go.* ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o app

# Runtime stage
FROM gcr.io/distroless/static-debian12
COPY --from=builder /build/app /app
ENTRYPOINT ["/app"]
```

Needed for:

- Go
- Java
- .NET
- React/Vue/Angular

5. Security best practices

```dockerfile
# Create non-root user (Alpine syntax)
RUN addgroup -g 1001 app && \
    adduser -D -u 1001 -G app app

# Debian/Ubuntu syntax
RUN groupadd -r app -g 1001 && \
    useradd -r -u 1001 -g app app

# Switch early
USER app

# Read-only root filesystem (when possible)
# Set in Docker Compose or K8s, not Dockerfile

# Drop capabilities (runtime flag)
# --cap-drop=ALL --cap-add=NET_BIND_SERVICE

# No secrets in layers
# Use BuildKit secrets or multi-stage
RUN --mount=type=secret,id=npmrc,target=/root/.npmrc \
    npm ci

# Scan for vulnerabilities in CI
# trivy image myimage:latest --severity HIGH,CRITICAL
```

6. Prefer slim/distroless in production

```dockerfile
FROM gcr.io/distroless/static-debian12
```

7. Use HEALTHCHECK

```dockerfile
HEALTHCHECK CMD curl -f http://localhost:3000/health || exit 1
```

8. Use --no-cache techniques

```dockerfile
pip install --no-cache-dir
```

9. Don’t install build tools in your final image

10. Log to stdout (never to files)

11. Add OCI labels

```dockerfile
# Add OCI annotations
LABEL org.opencontainers.image.created="2025-12-05T10:30:00Z" \
      org.opencontainers.image.authors="mo@coderco.io" \
      org.opencontainers.image.url="https://github.com/coderco/ecs-accelerator-series" \
      org.opencontainers.image.version="1.0.0" \
      org.opencontainers.image.revision="1234567890" \
      org.opencontainers.image.licenses="MIT"
```

12. Health, Monitoring, Docs

```dockerfile
# HTTP health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

# TCP health check (no curl)
HEALTHCHECK CMD nc -z localhost 8080 || exit 1

# Custom script
HEALTHCHECK CMD /app/healthcheck.sh || exit 1

# Expose ports (documentation only)
EXPOSE 8080
```

13. Anti-patterns

```dockerfile
# ❌ Don't use latest
FROM python:latest

# ❌ Don't run apt-get upgrade (non-deterministic)
RUN apt-get upgrade -y

# ❌ Don't install unnecessary packages
RUN apt-get install -y vim nano

# ❌ Don't use ADD for remote URLs (use curl/wget in RUN)
ADD https://example.com/file.tar.gz /tmp/

# ❌ Don't use shell form for ENTRYPOINT/CMD
ENTRYPOINT ./app.sh

# ❌ Don't ignore .dockerignore
# Always create one

# ❌ Don't hardcode secrets
ENV API_KEY=secret123

# ❌ Don't create files then delete in separate layers
RUN echo "temp" > /tmp/file
RUN rm /tmp/file  # Still in previous layer!

# ❌ Don't run multiple processes (use separate containers)
CMD service nginx start && service app start
```

14. Production Dockerfile Checklist

Production Checklist

- [X] Base image pinned with SHA256
- [X] Multi-stage build used (if applicable)
- [X] Non-root user configured
- [X] Minimal image (distroless/alpine/slim)
- [X] No secrets in layers
- [X] Dependencies pinned with lock files
- [X] HEALTHCHECK defined
- [X] OCI labels added
- [X] .dockerignore optimised
- [X] Vulnerability scan passed
- [X] exec form for ENTRYPOINT/CMD
- [X] No sudo/setuid binaries (if distroless)
- [X] Read-only root filesystem compatible
- [X] Signals handled correctly
- [X] Logs to stdout only
- [X] Build reproducible (pinned deps)
- [X] Image size < 500MB (ideally < 100MB)
- [X] Layer count < 20
- [X] BuildKit features leveraged

## 7. Dockerfile Sections (Clear Breakdown)

### Base Image

“Which environment does the app need?”

### WORKDIR

“Where inside the container will we work?”

### COPY

“What files does the app need to run?”

### RUN

“Install dependencies or build the app.”

### CMD / ENTRYPOINT

“How does the container start?”

### USER

“Run safely as non-root.”

### HEALTHCHECK

“Let ECS/Compute know if the app dies.”

## 8. Debugging Broken Dockerfiles

Common issues to demonstrate:

### Missing dependencies

Fix requirements.txt or package.json.

### Wrong COPY order (slow builds)

Show caching differences.

### Using Alpine for Python numpy

Immediate build failures.

### Incorrect CMD

Container exits instantly.

### Wrong port exposed

App runs but stays unreachable.

### Running as root

Security issue.

### How to debug

```bash
docker exec -it <container> sh
docker logs <container>
docker inspect <container>
```
