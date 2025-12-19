# Docker Compose – Concepts & Theory

## What Docker Compose is

Docker Compose is a tool that allows you to define and run multiple Docker containers together using a single configuration file.

Instead of starting containers one by one, Docker Compose lets you describe the entire application in one place.

## Why Docker Compose exists

Modern applications rarely use one container.

A typical application might include:

- An API
- A database
- A cache
- A background worker

Docker Compose solves the problem of running all of these together in a predictable way.

## The Docker Compose mental model

Docker Compose:

- Uses Docker underneath
- Runs on a single machine
- Coordinates multiple containers
- Creates networking automatically

When you run:

`docker compose up`

Docker Compose:

1. Reads the configuration file
2. Creates a network
3. Starts containers
4. Injects configuration
5. Connects services together

## The docker-compose.yml file

This file describes the application.

It uses YAML, a human-readable configuration format.

The most important top-level key is:

services:

Each service represents one container.

## Services

A service defines:

- Which image to run
- Which ports to expose
- Which environment variables to use
- Which volumes to mount
Which other services it depends on

Service names are important because:

- They become network hostnames
- Containers use them to talk to each other

## Networking in Docker Compose

Docker Compose creates a private virtual network.

Containers:

- Can talk to each other
- Use service names instead of IP addresses
- Do not use localhost to communicate

Example:

- The app connects to the database using db
- Not 127.0.0.1
- Not localhost

## Ports

Ports are used to expose a container to your machine.

Format:

`"host_port:container_port"`


Ports are:

- For humans and browsers
- Not required for container-to-container communication

## Environment variables

Environment variables are used to pass configuration into containers.

Common uses:

- Database credentials
- Hostnames
- Feature flags

Docker Compose can load environment variables from a .env file.

## Volumes

Containers are ephemeral.

When a container stops:

- Its internal data is lost

Volumes exist to persist data beyond container restarts.

In this lab:

- PostgreSQL data is stored in a volume
- Restarting containers does not delete the database

## Startup order and health checks

Docker Compose can control startup order using depends_on.

This ensures:

- One service starts before another

Health checks allow Docker to verify when a service is actually ready.

Startup order does not replace proper application error handling.

## YAML basics

YAML is indentation-based.

Important rules:

- Indentation matters
- Spaces are used, not tabs
- Structure defines meaning

Lists are written with dashes:

```yaml
ports:
  - "8000:8000"
```

## YAML anchors

YAML supports anchors to avoid repetition.

Anchors allow you to:

- Define a block once
- Reuse it elsewhere

This is a YAML feature, not specific to Docker Compose. So we can use it CI/CD pipelines and other YAML tools too.

## Why Docker Compose does not run on ECS

Docker Compose is designed for:

- Local machines
- Single Docker hosts
- Development workflows

ECS is designed for:

- Multiple machines
- Cloud infrastructure
- Production workloads

ECS requires:

- VPC networking
- IAM roles
- Load balancers
- Auto scaling
- Managed storage
  
Docker Compose does not manage these concepts.

## Correct mental model

Docker Compose is a local orchestration tool.

It helps you:

- Learn containers
- Develop applications
Reproduce issues locally

ECS is a cloud orchestration platform.

They solve different problems at different layers.

## When to use Docker Compose

Use Docker Compose for:

- Local development
- Learning Docker
- Testing
- CI pipelines
- Simple demos

Do not use Docker Compose for:

- Production systems
- High availability workloads
- Internet-facing services