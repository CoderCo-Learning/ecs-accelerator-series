import logging
import os
from datetime import datetime

import psycopg2
import redis
from flask import Flask, jsonify, request


def get_pg_connection():
    """
    Connect to Postgres running in Docker Compose.
    Hostname matches the service name in docker-compose.yml.
    """
    return psycopg2.connect(
        host="db",
        port=5432,
        database="postgres",
        user="postgres",
        password="postgres",
    )


def get_redis_client():
    """
    Connect to Redis running in Docker Compose.
    Hostname matches the service name in docker-compose.yml.
    """
    return redis.Redis(host="redis", port=6379, db=0, decode_responses=True)


def write_to_db(user_input: str) -> str:
    conn = get_pg_connection()
    cursor = conn.cursor()

    # Ensure table exists (initial lab run)
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS inputs (
            id SERIAL PRIMARY KEY,
            value TEXT NOT NULL
        )
        """
    )

    # Simple "auto-migration" for the lab: add created_at if it isn't there yet
    cursor.execute(
        """
        ALTER TABLE inputs
        ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        """
    )

    cursor.execute("INSERT INTO inputs (value) VALUES (%s)", (user_input,))
    conn.commit()
    conn.close()
    logging.getLogger("app").info(
        "Inserted message into Postgres", extra={"value": user_input}
    )
    return "Input written to Postgres"


def read_from_db(limit: int = 10):
    conn = get_pg_connection()
    cursor = conn.cursor()
    cursor.execute(
        "SELECT id, value, created_at FROM inputs ORDER BY id DESC LIMIT %s", (limit,)
    )
    result = cursor.fetchall()
    conn.close()
    return result


def write_to_redis(user_input: str) -> str:
    r = get_redis_client()
    # Store last input and bump a counter so students can see Redis state
    r.set("last_input", user_input)
    r.incr("input_count")
    r.lpush("jobs", user_input)
    logging.getLogger("app").info(
        "Pushed job to Redis list", extra={"value": user_input}
    )
    return "Input written to Redis"


def read_from_redis():
    r = get_redis_client()
    last = r.get("last_input")
    count = r.get("input_count")
    return {"last_input": last, "input_count": int(count) if count else 0}


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger("app")


app = Flask(__name__)


def run_migrations():
    """
    Simple migration function used by both the app and the one-shot migrate service.
    """
    conn = get_pg_connection()
    cursor = conn.cursor()

    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS inputs (
            id SERIAL PRIMARY KEY,
            value TEXT NOT NULL
        )
        """
    )

    cursor.execute(
        """
        ALTER TABLE inputs
        ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        """
    )

    conn.commit()
    conn.close()
    logger.info("Migrations applied to inputs table")


@app.route("/")
def index():
    """
    Simple landing page explaining what this lab does.
    """
    return (
        "<h1>Docker Compose Lab: App + Postgres + Redis</h1>"
        "<p>This app is running in the <code>app</code> service.</p>"
        "<ul>"
        "<li>POST a message to <code>/api/messages</code></li>"
        "<li>View recent messages at <code>/api/messages</code> (GET)</li>"
        "<li>Check health at <code>/api/health</code></li>"
        "</ul>"
    )


@app.route("/api/messages", methods=["POST"])
def create_message():
    data = request.get_json(silent=True) or {}
    text = data.get("text") or os.getenv("APP_INPUT", "hello from docker compose")

    pg_msg = write_to_db(text)
    redis_msg = write_to_redis(text)

    return jsonify(
        {
            "text": text,
            "postgres": pg_msg,
            "redis": redis_msg,
        }
    )


@app.route("/api/messages", methods=["GET"])
def list_messages():
    limit_param = request.args.get("limit", "10")
    try:
        limit = max(1, min(int(limit_param), 100))
    except ValueError:
        limit = 10

    rows = read_from_db(limit=limit)
    items = [
        {
            "id": row[0],
            "value": row[1],
            "created_at": row[2].isoformat()
            if isinstance(row[2], datetime)
            else str(row[2]),
        }
        for row in rows
    ]
    redis_state = read_from_redis()

    return jsonify({"messages": items, "redis": redis_state})


@app.route("/api/health", methods=["GET"])
def health():
    try:
        # Simple checks to show both services are reachable
        conn = get_pg_connection()
        conn.cursor().execute("SELECT 1")
        conn.close()

        r = get_redis_client()
        r.ping()

        status = "ok"
    except Exception as exc:  # pragma: no cover - demo only
        status = f"error: {exc}"

    return jsonify({"status": status})


if __name__ == "__main__":
    import sys

    mode = sys.argv[1] if len(sys.argv) > 1 else "web"

    if mode == "migrate":
        logger.info("Running migrations in one-shot mode")
        run_migrations()
    else:
        # Bind to 0.0.0.0 so Docker can expose port 8000
        logger.info("Starting Flask web server", extra={"mode": mode})
        app.run(host="0.0.0.0", port=8000)