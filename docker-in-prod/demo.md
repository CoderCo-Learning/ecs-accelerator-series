# Docker Debugging Demo

A Flask app designed to demonstrate Docker debugging techniques.

## Quick Start

```bash
docker build -t debug-demo:latest ./debug-app
docker run -d --name debug-demo -p 8080:8080 debug-demo:latest

## on new term, run sim.sh
sh sim.sh
```

## Manual Debugging Commands

### 1. Build with Full Logs

```bash
# See every build step clearly
docker build --progress=plain -t debug-demo:latest .

# Build without cache (force rebuild)... in case we change something and want to quickly rebuild ineh.
docker build --no-cache -t debug-demo:latest .
```

### 2. Run Container

```bash
docker run -d --name debug-demo -p 5000:5000 debug-demo:latest
```

### 3. List Running Containers

```bash
docker ps

# show all containers (including stopped)
docker ps -a

# show last created container
docker ps -l
```

### 4. View Logs

```bash
# all logs
docker logs debug-demo

# follow logs in real-time
docker logs -f debug-demo

# last 50 lines
docker logs --tail 50 debug-demo

# logs with timestamps
docker logs -t debug-demo

# logs since specific time
docker logs --since 2024-01-01T10:00:00 debug-demo

# filter logs
docker logs debug-demo 2>&1 | grep ERROR
docker logs debug-demo 2>&1 | grep -i "health"
```

### 5. Enter Container Shell

```bash
# interactive shell
docker exec -it debug-demo sh

# run single command
docker exec debug-demo whoami
docker exec debug-demo ps aux
docker exec debug-demo ls -la /app
docker exec debug-demo env
docker exec debug-demo cat /app/app.py

# as root user (if needed for debugging)
docker exec -u root -it debug-demo sh
whoami # check if we are root now...
```

### 6. Inspect Container Metadata

```bash
# full JSON output
docker inspect debug-demo

# with jq for filtering
docker inspect debug-demo | jq '.[0].Config.Env'
docker inspect debug-demo | jq '.[0].Config.Entrypoint'
docker inspect debug-demo | jq '.[0].NetworkSettings.IPAddress'
docker inspect debug-demo | jq '.[0].Mounts'
docker inspect debug-demo | jq '.[0].State'

# specific field with --format
docker inspect --format='{{.State.Status}}' debug-demo
docker inspect --format='{{.NetworkSettings.IPAddress}}' debug-demo
docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' debug-demo
```

### 7. Debug Broken/Stopped Container

```bash
# Run with shell instead of app
docker run --rm -it --entrypoint sh debug-demo:latest

# once inside:
ls -la /app
cat /app/app.py
python --version
pip list
env
whoami
id
```

### 8. Resource Monitoring

```bash
# Real-time stats
docker stats debug-demo

# One-time stats
docker stats --no-stream debug-demo

# All containers
docker stats
```

### 9. Port Mappings

```bash
docker port debug-demo
```

### 10. File Changes

```bash
# Show files changed since container started
docker diff debug-demo
```

### 11. Process List

```bash
docker top debug-demo

# With custom ps options
docker top debug-demo aux
```

### 12. Health Check Status

```bash
# In inspect output
docker inspect debug-demo | jq '.[0].State.Health'

# Watch health status
watch -n 5 'docker inspect debug-demo | jq ".[0].State.Health.Status"'
```

### 13. Copy Files To/From Container

```bash
# Copy from container
docker cp debug-demo:/app/app.py ./local-app.py

# Copy to container
docker cp local-file.txt debug-demo:/tmp/
```

### 14. Export Container Filesystem

```bash
# Export to tar
docker export debug-demo > container.tar
## if you want to export the container as a new image, you can do:
docker commit debug-demo debug-demo:latest

# Or pipe directly
docker export debug-demo | tar tv | grep app
```

### 15. Check Networks

```bash
# List networks
docker network ls

# Inspect network
docker network inspect bridge

# Find container IP
docker inspect debug-demo | jq -r '.[0].NetworkSettings.IPAddress'
```

## App Endpoints for Testing

```bash
# Home - generates normal logs
curl http://localhost:8080/

# Health check - sometimes fails after 60s
curl http://localhost:8080/health

# Crash - generates error logs
curl http://localhost:8080/crash

# Slow - tests timeouts
curl http://localhost:8080/slow?delay=10

# Environment vars
curl http://localhost:8080/env

# List files
curl http://localhost:8080/files
```

## Common Debugging Scenarios

### App Won't Start

```bash
# Check if container is running
docker ps -a

# Check logs for errors
docker logs debug-demo

# Check with full output
docker logs debug-demo 2>&1

# Try running with shell
docker run --rm -it --entrypoint sh debug-demo:latest
```

### Health Check Failing

```bash
# Check health status
docker inspect debug-demo | jq '.[0].State.Health'

# Check logs
docker logs debug-demo | grep -i health

# Manually test health endpoint
curl http://localhost:5000/health

# From inside container
docker exec debug-demo wget -O- http://localhost:5000/health
```

### High Memory/CPU Usage

```bash
# Check resource usage
docker stats --no-stream debug-demo

# Check processes
docker top debug-demo

# Enter and investigate
docker exec -it debug-demo sh
# Then: top, ps aux, etc.
```

### Permission Issues

```bash
# Check user
docker exec debug-demo whoami
docker exec debug-demo id

# Check file permissions
docker exec debug-demo ls -la /app

# Enter as root
docker exec -u root -it debug-demo sh
```

### Network troubleshooting

```bash
# Check IP address
docker inspect debug-demo | jq -r '.[0].NetworkSettings.IPAddress'

# Check port mappings
docker port debug-demo

# Test from inside
docker exec debug-demo wget -O- http://localhost:5000

# Test DNS
docker exec debug-demo nslookup google.com
```

### Attach to Container

```bash
# Attach to main process (see stdout)
docker attach debug-demo

# Detach without stopping: Ctrl+P, Ctrl+Q
```

### Events Stream

```bash
# Watch Docker events
docker events

# Filter for specific container
docker events --filter container=debug-demo
```

### System Diagnostics

```bash
# disk usage
docker system df

# detailed disk usage
docker system df -v

# prune unused resources
docker system prune

docker system prune -a --volumes -f
## I love using this command to clean up my system and free up space.
### Deletes everything Docker isn’t using
## - stopped containers
## - unused images
## - unused networks
## - build cache

## -a > also remove all unused images, not just dangling ones

# --volumes > remove unused volumes (can delete data!)

# -f > run without asking for confirmation

```

## Cleanup

```bash
# Stop container
docker stop debug-demo

# Remove container
docker rm debug-demo

# Remove image
docker rmi debug-demo:latest

# Nuclear option (careful!)
docker system prune -a --volumes
```

## Debugging Checklist

When container fails:

1. Check if running: `docker ps -a`
2. Check logs: `docker logs <container>`
3. Check health: `docker inspect <container> | jq '.[0].State.Health'`
4. Test with shell: `docker run --rm -it --entrypoint sh <image>`
5. Check resources: `docker stats --no-stream <container>`
6. Inspect metadata: `docker inspect <container> | jq`
7. Check processes: `docker top <container>`
8. Rebuild clean: `docker build --no-cache -t <image> .`
