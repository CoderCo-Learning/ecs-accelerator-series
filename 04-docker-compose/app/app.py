import os
import time
import psycopg2
from flask import Flask

app = Flask(__name__)

DB_HOST = os.getenv("DB_HOST")
DB_PORT = os.getenv("DB_PORT")
DB_NAME = os.getenv("DB_NAME")
DB_USER = os.getenv("DB_USER")
DB_PASSWORD = os.getenv("DB_PASSWORD")


def get_db_connection():
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
    )


@app.route("/")
def index():
    return "Docker Compose is working 🚀"


@app.route("/db")
def db_check():
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("SELECT NOW();")
        result = cur.fetchone()
        cur.close()
        conn.close()
        return f"Database connected. Time: {result[0]}"
    except Exception as e:
        return f"Database connection failed: {e}", 500


if __name__ == "__main__":
    print("Starting app...")
    print(f"Connecting to DB at {DB_HOST}:{DB_PORT}")

    # naive retry loop – great teaching moment
    for i in range(5):
        try:
            conn = get_db_connection()
            conn.close()
            print("Database connection successful")
            break
        except Exception as e:
            print(f"DB not ready yet ({i+1}/5): {e}")
            time.sleep(3)

    app.run(host="0.0.0.0", port=8000)
