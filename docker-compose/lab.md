# Docker Compose Lab – ECS Accelerator

## Purpose of this lab

This lab introduces Docker Compose and explains how it is used to run multiple containers together on a single machine.

You will:

- Run a multi-container application locally
- Understand how containers communicate
- See how environment variables and volumes work
- Learn why Docker Compose is not used in production on ECS

## What you will build

A simple application made of:

- A Python web app (Flask)
- A PostgreSQL database
- Docker Compose to run both together

Prerequisites

- You must have Docker Desktop installed. 

## How to run the lab

From the root of the project:

`docker compose up`


Docker Compose will:

- Build the application image
- Start the database
- Create a network
- Start the application
- Verify the application

Open your browser:

App homepage
http://localhost:8000

Database connectivity check
http://localhost:8000/db

If both load successfully, Docker Compose is working correctly.

## Useful commands

Check running services:

`docker compose ps`


View logs:

`docker compose logs -f`


Stop everything:

`docker compose down`


Remove volumes as well:

`docker compose down -v`

## Key concepts you should understand after this lab

- What a service is in Docker Compose
- How containers communicate using service names
- Why localhost does not work between containers
- How environment variables are injected
- How volumes persist data
- Why Docker Compose is a local development tool

## Important clarification

Docker Compose is not a production orchestration tool.

It is designed for:

- Local development
- Learning
- Testing
- Simple demos

In production and in the real world, AWS ECS uses task definitions, IAM, VPC networking and load balancers, which Docker Compose does not manage.

## Cleanup

When finished:

`docker compose down -v`
