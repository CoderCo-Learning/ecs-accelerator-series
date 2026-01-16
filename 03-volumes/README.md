# Docker Volumes Workshop

This workshop introduces container storage fundamentals using Docker, then maps those concepts to storage in Amazon ECS.

## 1. Why Containers Need Volumes

- Containers have ephemeral filesystems.
- When a container restarts or is removed, all internal data is lost.

- Use volumes to store data outside the container.

## 2. Sample Application

- The demo application writes notes to:

- `/data/notes.txt`

- We will use this file path to demonstrate persistence behaviour.

## 3. Running Without Volumes

Start the container:

`docker run -p 3000:3000 --name demo1 volume-demo`

Add notes via the API, then remove the container:

`docker rm -f demo1`

- Re-run the container and observe that data is lost.

## 4. Bind Mounts

A bind mount maps a folder from the host into the container.

```bash
mkdir data
docker run \
  -p 3000:3000 \
  -v $(pwd)/data:/data \
  --name demo2 \
  volume-demo
```

- Data now persists after container deletion.

Pros:

- Simple
- Good for development
- Easy to inspect files

Cons:

- Depends on host path
- Not portable
- Permissions issues are common

## 5. Named Volumes

Named volumes are managed entirely by Docker.

```bash
docker volume create notesvol
docker run \
  -p 3000:3000 \
  -v notesvol:/data \
  --name demo3 \
  volume-demo
```

- Destroy the container and re-run.
- Data persists.

Inspect the volume:

`docker volume inspect notesvol`

## 6. Common Volume Issues

- Incorrect mount path
- Application cannot find expected files.

Permission issues

- Host directory permissions can prevent writes.

Check logs:

`docker logs <container>`

## 7. Storage in ECS

- Docker volumes are local.
- ECS tasks run on multiple machines and require persistent, shared storage.

AWS provides two primary storage options:

### Fargate Ephemeral Storage

Every Fargate task has ephemeral disk storage:
- Default: 20GB per task
- Configurable: up to 200GB
- Lifespan: Lives and dies with the task
- Use case: Temporary files, build artifacts, unzip operations

```json
"ephemeralStorage": {
"sizeInGiB": 50
}
```
**Not suitable for persistence** – disappears when task stops.


### EBS (Elastic Block Store)

Block storage attached to a single EC2 instance.

**Characteristics:**
- High performance, low latency
- Cannot be shared across multiple instances
- Only works with ECS on EC2 (not Fargate)

**Use case:** High-performance storage for single-instance workloads on EC2.

**Limitation:** If ECS moves your task to another instance, EBS doesn't follow.

### EFS (Elastic File System)

Network file system shared across multiple ECS tasks.

**Characteristics:**
- Shared access – multiple tasks read/write simultaneously
- Multi-AZ – data replicated across availability zones
- Works with both Fargate and EC2
- Elastic capacity – scales automatically

**Use cases:**
- User uploads (images, documents, media)
- Shared configuration files
- Application logs
- ML model files accessed by multiple containers

**Recommendation:** For ECS applications requiring persistent storage, use EFS 99% of the time.

## 8. ECS Task Definition Example

```json
{
  "volumes": [
    {
      "name": "efs-data",
      "efsVolumeConfiguration": {
        "fileSystemId": "fs-12345",
        "rootDirectory": "/data",
        "transitEncryption": "ENABLED"
      }
    }
  ],
  "containerDefinitions": [
    {
      "name": "app",
      "mountPoints": [
        {
          "sourceVolume": "efs-data",
          "containerPath": "/data"
        }
      ]
    }
  ]
}
```

## ECS Fargate equivalents

| Docker            | ECS Fargate                   |
| ----------------- | ----------------------------- |
| Docker volume     | EFS filesystem                |
| Local mount       | EFS access point              |
| `-v volume:/path` | Task definition `mountPoints` |
| Host persistence  | Network persistence           |

## ECS Fargate + EFS architecture

High level flow:

- Create EFS filesystem

- Create EFS access point (optional but best practice)

- Allow NFS (2049) in SGs

- Reference EFS in ECS task definition

- Mount inside container

## 9. When to Use What

| Use Case | Storage Type |
|----------|--------------|
| Local development | Bind mount |
| Local persistence | Named volume |
| High-performance per-instance storage | EBS |
| Shared storage for ECS tasks | EFS |


################################################################################

################################################################################


# EFS with ECS Fargate

## Overview

This demo shows how to attach Amazon EFS (Elastic File System) to ECS Fargate tasks for persistent, shared storage across containers.


Architecture
┌─────────────────────────────────────────────────┐
│                    VPC                          │
│                                                 │
│  ┌──────────────┐         ┌──────────────┐    │
│  │  Subnet A    │         │  Subnet B    │    │
│  │              │         │              │    │
│  │ ┌──────────┐ │         │ ┌──────────┐ │    │
│  │ │ECS Task  │ │         │ │ECS Task  │ │    │
│  │ │          │ │         │ │          │ │    │
│  │ │/mnt/efs ─┼─┼─┐   ┌───┼─┼─/mnt/efs│ │    │
│  │ └──────────┘ │ │   │   │ └──────────┘ │    │
│  │              │ │   │   │              │    │
│  │ ┌──────────┐ │ │   │   │ ┌──────────┐ │    │
│  │ │Mount     │ │ │   │   │ │Mount     │ │    │
│  │ │Target    │◄┼─┘   └───┼►│Target    │ │    │
│  │ └──────────┘ │         │ └──────────┘ │    │
│  └──────────────┘         └──────────────┘    │
│         │                        │             │
│         └────────┬───────────────┘             │
│                  │                             │
│           ┌──────▼──────┐                      │
│           │     EFS     │                      │
│           │ File System │                      │
│           └─────────────┘                      │
└─────────────────────────────────────────────────┘

## Key Components

1. EFS File System

- Encrypted at rest
- Auto-transitions files to Infrequent Access (IA) storage after 30 days for cost savings
- Multi-AZ by default for high availability

2. Mount Targets

- Network interfaces that allow ECS tasks to access EFS
- Required in each subnet where tasks run
- Uses NFS protocol (port 2049)

3. Security Groups

- EFS security group allows inbound NFS (2049) from ECS task security group
- ECS task security group allows outbound to EFS security group

4. VPC DNS Configuration

- enableDnsHostnames – required for EFS DNS resolution
- enableDnsSupport – required for DNS functionality
- Without these, containers can't resolve fs-*.efs.amazonaws.com

Why EFS with Fargate?

## Problem: Containers are Ephemeral

- When an ECS task stops, all data inside the container is lost
- No access to host filesystem in Fargate (AWS manages the infrastructure)
- Need persistent storage that survives container restarts and failures

Solution: EFS Provides

- Persistent storage – data survives task restarts, redeployments, and host failures
- Shared access – multiple tasks can read/write the same files simultaneously
- Multi-AZ durability – data replicated across Availability Zones
- Elastic scaling – storage grows automatically as you write data

## How It Works: Boot Sequence

1. ECS schedules task in subnet A
2. Task reads task definition, sees EFS volume configuration
3. Resolves `fs-12345.efs.us-east-1.amazonaws.com` via VPC DNS
4. Connects to mount target in subnet A on port 2049
5. Security groups validate traffic
6. EFS mounted at `/mnt/efs` inside container
7. Application writes to `/mnt/efs/uploads/file.jpg` – data persists on EFS
8. Task stops and restarts – new task mounts same EFS, sees same files


## Common Use Cases

### Shared Application State

- Configuration files shared across containers
- Session data for multi-instance applications
- Feature flags or A/B test configurations


### User-Generated Content

- File uploads (images, documents, media)
- CMS content storage (WordPress, Ghost)
- User profiles and avatars


### Logs and Metrics

- Centralised logging from all containers
- Application metrics and debugging data
- Audit trails that persist beyond container lifetime


### ML/Data Science

- Shared model files across inference containers
- Training datasets accessible to multiple jobs
- Experiment results and artifacts


## When NOT to Use EFS

- ❌ High-IOPS databases (use RDS/DynamoDB instead)
- ❌ Temporary scratch space (use container ephemeral storage)
- ❌ Object storage/backups (use S3 instead)
- ❌ Single-task persistent storage on EC2 (use EBS instead)

## Performance Characteristics

| Aspect | EFS Performance |
|--------|----------------|
| Throughput | Scales with file system size (bursting mode) or provisioned |
| Latency | ~1-3ms for standard, ~10-50ms for IA |
| IOPS | 7,000+ per file system (for reads) |
| Concurrent connections | Thousands of tasks can mount simultaneously |

## Docker Volume Comparison

### Traditional Docker Volumes (Local)

```bash
docker run -v /host/path:/container/path myapp
```

| Aspect | Traditional Docker Volumes (Local) | EFS Volumes (Network) |
|--------|------------------------------------|------------------------|
| Fast | ✅ | ❌ |
| Simple setup | ✅ | ✅ |
| Lost when host fails | ❌ | ✅ |
| Can't share across hosts | ❌ | ✅ |
| Not available in Fargate | ❌ | ✅ |

### EFS Volumes (Network)
```terraform
terraformvolume {
  name = "efs-storage"
  efs_volume_configuration {
    file_system_id = "fs-abc123"
  }
}
```

✅ Survives host failures
✅ Shared across tasks/hosts
✅ Works in Fargate
❌ Slower (network overhead)
❌ More expensive

### Best Practices

- Always encrypt EFS (encrypted = true)
- Enable transit encryption when mounting from containers
- Use lifecycle policies to reduce costs (transition to IA storage)
- Monitor CloudWatch metrics for usage patterns and performance
- Implement backup strategy using AWS Backup or snapshots
- Use EFS access points for better isolation in multi-tenant scenarios
- Set appropriate POSIX permissions on mounted directories
- Test disaster recovery by simulating AZ failures

### Limitations

- Fargate ephemeral storage: 20GB max (beyond this, must use EFS)
- EFS IOPS: Limited by file system size in bursting mode
- Concurrent mounts: No hard limit but monitor performance
- File size: Max 52TB per file
- Path length: Max 255 characters per component

## Summary

**Docker Volumes (Local Development):**
- Bind mounts for simple local dev
- Named volumes for cleaner local persistence
- Cannot work in cloud environments like Fargate

**ECS Storage (Production):**
- Ephemeral storage for temporary files
- EBS for single-instance high-performance workloads (EC2 only)
- EFS for shared, persistent storage across multiple tasks

**Key Principle:** Separate compute (containers) from storage (EFS). Containers are disposable, data is not.

**The mental model:**
- Docker volume = "storage on this machine"
- EFS = "storage accessible from any machine in the VPC"

This is fundamental to running stateful workloads in container orchestration platforms.