# Container Building From Scratch

This repo contains **14+ production-quality container examples**  
for every major language, runtime, and scenario.

This is used in the **CoderCo ECS Accelerator Series** 

- Docker fundamentals from first principles
- Multi-stage builds
- Distroless images
- Scratch images
- Security best practices
- Layer caching
- Real open-source containerisation

---

# 📁 Examples Included

| Example | Language | Technique(s) shown |
|--------|----------|--------------------|
| go-basic | Go | multi-stage, alpine |
| go-scratch | Go | scratch images, static binaries |
| go-distroless | Go | distroless, static builds |
| node-basic | Node.js | beginner Dockerfile |
| node-production | Node.js | layer caching, multi-stage |
| python-basic | Python | simple builds |
| python-slim | Python | slim images, OS deps |
| python-distroless | Python | distroless python |
| static-nginx | HTML | NGINX serving |
| bash-script | Bash | tiniest possible container |
| java-basic | Java | multi-stage build (Maven) |
| csharp-basic | .NET | build vs runtime |
| php-apache | PHP | legacy container |
| flask-todo | Python | real OSS app |
| go-chi-api | Go | real OSS microservice |

---

# How to Use This Repo

Install Docker:
```
docker --version
```

Clone this repo:
```
git clone https://github.com/CoderCo-Learning/ecs-accelerator-containers
cd ecs-accelerator-containers
```

Use the Makefile to build ANY example:
```
make build-go-basic
make run-go-basic
```

---

# Build & Run — All Commands

**ALL commands** for every example.

## Go Basic
```
make build-go-basic
make run-go-basic
curl localhost:8080
```

## Go Scratch
```
make build-go-scratch
make run-go-scratch
curl localhost:8081
```

## Go Distroless
```
make build-go-distroless
make run-go-distroless
curl localhost:8082
```

## Node Basic
```
make build-node-basic
make run-node-basic
curl localhost:3000
```

## Node Production
```
make build-node-prod
make run-node-prod
curl localhost:3001
```

## Python Basic
```
make build-python-basic
make run-python-basic
curl localhost:9000
```

## Python Slim
```
make build-python-slim
make run-python-slim
curl localhost:5001
```

## Python Distroless
```
make build-python-distroless
make run-python-distroless
curl localhost:5002
```

## NGINX Static Site
```
make build-static
make run-static
curl localhost:8083
```

## Bash Script
```
make build-bash
make run-bash
```

## Java
```
make build-java
make run-java
curl localhost:8084
```

<!-- ## C# .NET
```
make build-csharp
make run-csharp
```

## PHP Apache
```
make build-php
make run-php
``` -->

## Flask ToDo App (Open Source)
```
make build-flask-todo
make run-flask-todo
```

## Go-Chi API (Open Source)

```
make build-go-chi
make run-go-chi
```

---

# Security Tools

## Scan image for CVEs

```
grype <image>
```

## Generate SBOM

```
syft <image>
```

## Run container as non-root

```
USER app
```

## Read-only root filesystem (ECS)

```
readonlyRootFilesystem: true
```

---
