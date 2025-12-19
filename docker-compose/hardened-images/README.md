# Docker Hardened Images/ DHI

What they are:

- Distroless-style images
- Built on Alpine / Debian foundations
- No shell
- No package manager
- Non-root user by default
- Signed attestations (SBOM + provenance)
- Around 90–95% smaller than upstream equivalents

## Signed attestations (SBOM + provenance) – simple explanation

This means the image comes with proof of two things:

- SBOM – a list of everything inside the image (all packages and libraries)
- Provenance – proof of who built the image and how it was built

Both are cryptographically signed, so they can’t be changed or faked.

In simple terms:

- You can see what’s inside the image and you can trust where it came from.

This helps prevent:

- Running unknown or tampered images
- Supply-chain attacks
- Accidental use of untrusted containers

That’s it — security through visibility and verification, not trust.

They are designed to:

- Reduce attack surface
- Improve supply-chain security
- Enforce secure defaults

They are intentionally less convenient than standard images.

## Prerequisites

```bash
docker login dhi.io  # Free – just needs Docker Hub account
```

## Lab 1: Compare Attack Surface

```bash
# Pull both images
docker pull dhi.io/nginx:1.27
docker pull nginx:1.27
```

```bash
# Size comparison
docker images | grep -E 'nginx.*1.27'

# CVE comparison (requires Docker Scout)
docker scout compare dhi.io/nginx:1.27 --to nginx:1.27 --platform linux/amd64 --ignore-unchanged

docker scout compare dhi.io/nginx:1.27 --to nginx:1.27 --platform linux/amd64 --ignore-unchanged 2>&1 | grep -A 50 "## Overview" ### this worked
```

Expected: DHI nginx ~15MB vs ~190MB upstream, zero or near-zero CVEs vs dozens.

## Lab 2: Distroless Behaviour

```bash
# Try to shell into DHI image – fails (no shell)
docker run --rm -it dhi.io/nginx:1.27 /bin/sh
# Error: executable file not found

# Upstream works fine
docker run --rm -it nginx:1.27 /bin/sh -c "whoami && cat /etc/passwd | wc -l"

# DHI runs as non-root by default
docker run --rm dhi.io/nginx:1.27 id
# uid=65532(nonroot) gid=65532(nonroot)
```

## Lab 3: Verify Supply Chain Attestations

```bash
# View SBOM attestation
docker buildx imagetools inspect dhi.io/nginx:1.27 --format '{{ json .SBOM }}'

# Verify signature with cosign (if installed)
cosign verify --certificate-oidc-issuer https://accounts.google.com \
  --certificate-identity-regexp '.*@docker.com' dhi.io/nginx:1.27
```

## Lab 4: Build on DHI Base

```bash
mkdir dhi-test && cd dhi-test

```python
cat > app.py << 'EOF'
from http.server import HTTPServer, BaseHTTPRequestHandler
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"Running on DHI\n")
    HTTPServer(("", 8080), Handler).serve_forever()
EOF
```

```Dockerfile
cat > Dockerfile << 'EOF'

FROM dhi.io/python:3.13

WORKDIR /app
COPY app.py .
EXPOSE 8080
CMD ["python", "app.py"]
EOF
```

```bash
docker build -t my-dhi-app .
docker run --rm -p 8080:8080 my-dhi-app &
curl localhost:8080
docker stop $(docker ps -q --filter ancestor=my-dhi-app)
```

## Lab 5: Debugging Without Shell

```bash
# Since there's no shell, you need docker debug (Docker Desktop) or ephemeral containers:
# Docker Desktop method
docker debug dhi.io/nginx:1.27

# Or attach debug container to running workload
docker run -d --name dhi-nginx dhi.io/nginx:1.27
docker run --rm -it --pid=container:dhi-nginx --net=container:dhi-nginx \
  alpine sh -c "apk add curl && curl localhost:80"
docker rm -f dhi-nginx
```

## Production Gotchas

- No apt/apk at runtime – all dependencies must be baked in at build time using multi-stage builds with -dev variants
- No shell for entrypoint scripts – use compiled binaries or switch to exec form CMD ["binary"]
- Read-only root filesystem compatible – works well with readOnlyRootFilesystem: true in K8s
- Logging – stdout/stderr only, no syslog daemon

## Real-World Migration Pattern

```Dockerfile
# Build stage – uses -dev variant with shell/tools
FROM dhi.io/python:3.13-dev AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --target=/app/deps -r requirements.txt

# Runtime stage – distroless, no shell
FROM dhi.io/python:3.13
COPY --from=builder /app/deps /app/deps
COPY . /app
ENV PYTHONPATH=/app/deps
CMD ["python", "/app/main.py"]
```

Trade-offs: debugging is harder without shell access, existing shell-based health checks need rewriting, some scanning tools struggle with distroless images. Worth it for supply chain security posture and compliance requirements.
