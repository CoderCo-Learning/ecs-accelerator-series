# Containers from First Principles

## 1. Basics. Where does it start from? 

You're a DevOps engineer. A developer hands you a folder and says: "Hey can you containerise this and deploy it to ECS or Kubernetes?"

This is real. Happens every day.

---

## 2. First Question: How Do I Run This App Normally?

Before Docker. Before containers. Before cloud. Before base images.

We MUST know how the app runs on a normal computer.

**THE RULE:**
- If you don't know how to run it normally
- You will never know how to run it inside a container

Goal: Identify the app's entrypoint command.

### Examples

**Python**
```bash
python app.py
```

**Node**
```bash
node index.js
```

**Go**
```bash
go run app.go
```

**Java**
```bash
mvn package
java -jar target/app.jar
```

**C#**
```bash
dotnet run
```

**PHP**
```bash
php -S localhost:8000
```

**Static site**
Just open it in a browser.

**Key insight:** Every app already has an "entrypoint command". Docker does NOT invent anything new – it just runs the same command inside the container.

---

## 3. How does it link to Docker ENTRYPOINT/CMD

Docker has a special thing called the ENTRYPOINT or CMD. What does it do? It just runs the SAME command you used locally, but inside the container.

### Examples

```dockerfile
CMD ["python", "app.py"]
CMD ["node", "index.js"]
CMD ["/server"]
CMD ["java", "-jar", "app.jar"]
```

**Remember:** Docker runs the same command the developer uses locally.


---
## 4.What is a Container?

A container is just a tiny computer inside your big computer. 

So:

- It has **its own filesystem** (its own little folder world)
- It has **its own network** (its own little IP inside your machine)
- It runs **one app** really well
- It’s like sending someone a **zip file that contains the exact app + exact environment**
    
So it will run the same everywhere
    

So when we run apps in the cloud (ECS, Kubernetes etc), they ALL run inside containers.

So Docker = the tool that builds these containers.

---

## 5. Choosing the Base Image (The Analogy)

What environment does this app need?

A Docker image is basically giving your app its own apartment.

Before it moves in, it needs:

- walls
- electricity
- plumbing
- a kitchen
- a bathroom

You cannot just throw the app into an empty concrete shell.

The base image is the fully built apartment shell.
You then bring in the furniture (files), install software (dependencies), and finally let the app live there (CMD).

### Simple Mappings

- Python app → `python:3.12-slim`
- Node app → `node:20-alpine`
- Go app → `golang:1.22` or `scratch` (for pros)
- Java app → `openjdk:17-jdk`
- PHP app → `php:apache`
- Static site → `nginx:alpine`

**Rule:** You choose your base image depending on the language the app needs. That's it.

---

## 6. What Files Does the App Need Inside Its Room?

The app needs its own files inside the container. When you COPY things into the image, think: "What does my app need in its new apartment?" Tools? Clothes? Blankets? aka which files are essential for the app to function/run?

In apps:
- source code
- requirements.txt
- package.json
- templates
- static files
- configs
- binary builds

### Examples

**Python app:**
```dockerfile
COPY requirements.txt .
COPY app.py .
COPY templates/ templates/
```

**Node app:**
```dockerfile
COPY package*.json .
COPY index.js .
```

**Go app:**
```dockerfile
COPY . .
```

**Key insight:** Everything the app needs MUST go into the container. If you forget something, the container will cry (errors).

---

## 7. Dependencies = The App's Tools & Room Essentials

After giving the app its apartment and copying its belongings, we now need to give it its "apartment essentials" – its dependencies.

### Examples

**Python:**
```dockerfile
RUN pip install -r requirements.txt
```

**Node:**
```dockerfile
RUN npm install
```

**Go:**
```dockerfile
RUN go build
```

**Java:**
```dockerfile
RUN mvn package
```

**C#:**
```dockerfile
RUN dotnet publish
```

**Rule:** Every app needs food. Dependencies are the food. You must feed the app inside its container.


---

## 8. How Does the App Start? (EntryPoint Command)

Now your app has:
- an apartment (base image)
- toys (files)
- food (dependencies)

Now we must TEACH the app how to live in its new apartment. That's CMD or ENTRYPOINT.

### Examples

**Python:**
```dockerfile
CMD ["python", "app.py"]
```

**Node:**
```dockerfile
CMD ["node", "index.js"]
```

**Go:**
```dockerfile
CMD ["/server"]
```

**Java:**
```dockerfile
CMD ["java", "-jar", "app.jar"]
```

**Key insight:** This is exactly the SAME command you ran locally. Docker does not do magic – it just runs the same thing.

---

## 9. Put It All Together (THE TEMPLATE)

The universal Dockerfile, works for ALL apps:

```dockerfile
# 1. Base Image
FROM <language>:<version>

# 2. Working directory
WORKDIR /app

# 3. Copy dependency files first
COPY <deps> .

# 4. Install dependencies
RUN <install command>

# 5. Copy the rest
COPY . .

# 6. Expose (optional)
EXPOSE <port>

# 7. Run the app
CMD ["<runtime>", "<main file>"]
```

# The Universal Dockerfile Template

| Step | Directive | Purpose | Checklist Question |
|------|-----------|---------|-------------------|
| 1. Environment | FROM | Choose the language runtime (Base Image). | What language/runtime? |
| 2. Location | WORKDIR | Set the directory where the app will live. | Where inside the container? |
| 3. Files (Deps) | COPY | Copy files needed to install dependencies. | What files does it need? |
| 4. Dependencies | RUN | Install the required dependencies. | What dependencies/food? |
| 5. Files (Source) | COPY | Copy the remaining application source code. | What files does it need? |
| 6. Port (Optional) | EXPOSE | Inform which port the app will listen on. | What port does it listen on? |
| 7. Execution | CMD | Run the same command as done locally. | How do I run it locally? |


**The APEX Docker insight:**
- If you know the local entrypoint, you ALWAYS know what CMD should be
- If you know the language, you ALWAYS know the base image

---

## 9. Example: Python App

Developer says: "Hey Mo, run my app with `python app.py`."

So the Dockerfile becomes:

```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
CMD ["python", "app.py"]
```

Breakdown:
- Base image = Python
- COPY files in
- Install deps
- Run exactly the same command locally

Done. You containerised Python.

---

## 10. Example: Go App (Multi-stage Build)

Developer says: "Run my app using `go run app.go` or compile with `go build` and run `./server`."

So Dockerfile becomes:

```dockerfile
FROM golang:1.22 AS builder
WORKDIR /app
COPY . .
RUN go build -o server .

FROM alpine
COPY --from=builder /app/server /server
CMD ["/server"]
```

Differences:
- Go compiles
- So we use a multi-stage build
- Final image has ONLY the binary

---

## 11. Mo's Dockerflow (The Final Mental Checklist)

EVERY TIME you get a new app, ask:

### 1. How do I run it locally?
This becomes CMD.

### 2. What language does it use?
This becomes base image.

### 3. What files does it need?
This becomes COPY.

### 4. What dependencies does it need?
This becomes RUN.

### 5. Where should the app live inside the container?
This becomes WORKDIR.

### 6. What port does it listen on?
This is EXPOSE.

If you follow this, you can containerise ANYTHING.