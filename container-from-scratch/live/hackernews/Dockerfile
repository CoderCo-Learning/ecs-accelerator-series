# Base image - Python runtime
FROM python:3.12-slim

# Why python:3.12-slim?
# - python:3.12 = Latest stable Python version
# - slim = Debian-based but removes unnecessary packages (~150MB vs ~900MB for full)
# - Not alpine because some Python packages need glibc (alpine uses musl)
# - Good balance between size and compatibility

WORKDIR /app

# Why WORKDIR /app?
# - Sets working directory for all subsequent commands
# - Keeps container filesystem organized
# - All our app files will live in /app

COPY requirements.txt .

# Why copy requirements.txt first?
# - Docker layer caching optimization
# - If requirements.txt hasn't changed, pip install won't re-run
# - Dependencies change less frequently than code
# - Speeds up rebuilds when only app.py changes

RUN pip install --no-cache-dir -r requirements.txt

# Why these flags?
# - pip install = Install Python packages
# - --no-cache-dir = Don't save pip cache (saves ~50MB in image)
# - -r requirements.txt = Install from requirements file
# - This layer gets cached if requirements.txt doesn't change

COPY . .

# Why copy everything now?
# - We've already cached the pip install layer
# - Only copies source code (app.py)
# - Changes to app.py won't invalidate pip install cache
# - Efficient layer reuse

EXPOSE 5000

# Why EXPOSE 5000?
# - Documents that the app listens on port 5000
# - Flask default port
# - Doesn't actually publish the port (that's -p flag in docker run)
# - Good practice for documentation

ENV FLASK_APP=app.py
ENV FLASK_ENV=production

# Why set environment variables?
# - FLASK_APP tells Flask which file to run
# - FLASK_ENV=production disables debug mode and auto-reload
# - ENV persists in the container
# - Best practice: never run debug=True in production

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "4", "app:app"]

# Why gunicorn instead of python app.py?
# - Flask dev server (app.run) is NOT production-ready
# - gunicorn = Production-grade WSGI server
# - --bind 0.0.0.0:5000 = Listen on all interfaces, port 5000
# - --workers 4 = Run 4 worker processes (handles concurrent requests)
# - app:app = module_name:application_variable (app.py contains app = Flask())
# - CMD can be overridden at runtime if needed




################################################################################
################################################################################

# # Build stage - install dependencies
# FROM python:3.12-slim AS builder

# # Why builder stage?
# # - Separates build tools from runtime
# # - Can install build dependencies without bloating final image
# # - Common pattern for compiled Python packages (e.g., numpy, pandas)

# WORKDIR /app

# RUN pip install --user --no-cache-dir flask==3.0.0 requests==2.31.0 gunicorn==21.2.0

# # Why --user?
# # - Installs packages to ~/.local instead of system-wide
# # - Makes it easy to copy just installed packages to next stage
# # - Cleaner separation

# # Runtime stage - minimal
# FROM python:3.12-slim

# # Why new FROM?
# # - Fresh base image without build artifacts
# # - Final image doesn't include pip cache or build tools
# # - Smaller and more secure

# WORKDIR /app

# # Copy installed packages from builder
# COPY --from=builder /root/.local /root/.local

# # Why COPY from builder?
# # - Takes only installed packages, not pip cache or intermediate files
# # - Multi-stage build magic - keep build tools out of final image

# # Add packages to PATH
# ENV PATH=/root/.local/bin:$PATH

# # Why update PATH?
# # - gunicorn installed in /root/.local/bin
# # - Need to tell shell where to find it

# COPY app.py .

# # Why only copy app.py?
# # - We don't need requirements.txt in runtime
# # - Smaller image, less attack surface
# # - Only production code

# EXPOSE 5000

# ENV FLASK_ENV=production

# CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "4", "app:app"]