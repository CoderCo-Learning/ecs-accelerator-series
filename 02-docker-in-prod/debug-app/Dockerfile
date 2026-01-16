FROM python:3.12-slim@sha256:2be8daddbb82756f7d1f2c7ece706aadcb284bf6ab6d769ea695cc3ed6016743

RUN groupadd -r app -g 1001 && \
    useradd -r -u 1001 -g app app

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY --chown=app:app app.py .
COPY --chown=app:app healthcheck.sh .
RUN chmod +x healthcheck.sh

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD ./healthcheck.sh

USER app
EXPOSE 8080

ENV FLASK_ENV=production \
    LOG_LEVEL=INFO \
    PYTHONUNBUFFERED=1

ENTRYPOINT ["python", "app.py"]