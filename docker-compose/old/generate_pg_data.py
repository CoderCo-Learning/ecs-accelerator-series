import argparse
import random
import string

import psycopg2


def get_pg_connection(
    host: str = "db",
    port: int = 5432,
    database: str = "postgres",
    user: str = "postgres",
    password: str = "postgres",
):
    return psycopg2.connect(
        host=host,
        port=port,
        database=database,
        user=user,
        password=password,
    )


def random_string(length: int = 16) -> str:
    alphabet = string.ascii_lowercase + string.digits
    return "".join(random.choice(alphabet) for _ in range(length))


def ensure_schema(conn):
    cur = conn.cursor()
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS inputs (
            id SERIAL PRIMARY KEY,
            value TEXT NOT NULL
        )
        """
    )
    cur.execute(
        """
        ALTER TABLE inputs
        ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        """
    )
    conn.commit()


def generate_inputs(conn, count: int, prefix: str):
    cur = conn.cursor()
    for i in range(count):
        value = f"{prefix}-{i}-{random_string(8)}"
        cur.execute("INSERT INTO inputs (value) VALUES (%s)", (value,))
        print(f"INSERT INTO inputs (value) VALUES ('{value}')")
    conn.commit()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="db")
    parser.add_argument("--port", type=int, default=5432)
    parser.add_argument("--database", default="postgres")
    parser.add_argument("--user", default="postgres")
    parser.add_argument("--password", default="postgres")
    parser.add_argument("--count", type=int, default=20)
    parser.add_argument("--prefix", default="lab-message")
    args = parser.parse_args()

    conn = get_pg_connection(
        host=args.host,
        port=args.port,
        database=args.database,
        user=args.user,
        password=args.password,
    )

    ensure_schema(conn)
    generate_inputs(conn, args.count, args.prefix)

    conn.close()
    print("Done. Check Adminer or psql to see the new rows in inputs.")


if __name__ == "__main__":
    main()


