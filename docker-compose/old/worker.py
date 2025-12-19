import logging
import time

import psycopg2
import redis


def get_pg_connection():
    return psycopg2.connect(
        host="db",
        port=5432,
        database="postgres",
        user="postgres",
        password="postgres",
    )


def get_redis_client():
    return redis.Redis(host="redis", port=6379, db=0, decode_responses=True)


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger("worker")


def main():
    r = get_redis_client()
    logger.info("Worker started, waiting for jobs on 'jobs' list")

    while True:
        try:
            _, payload = r.brpop("jobs")
            logger.info("Worker received job", extra={"payload": payload})

            # Optional: record that the job was processed in Postgres
            conn = get_pg_connection()
            cur = conn.cursor()
            cur.execute(
                """
                CREATE TABLE IF NOT EXISTS processed_jobs (
                    id SERIAL PRIMARY KEY,
                    payload TEXT NOT NULL,
                    processed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
                )
                """
            )
            cur.execute(
                "INSERT INTO processed_jobs (payload) VALUES (%s)",
                (payload,),
            )
            conn.commit()
            conn.close()

            logger.info("Worker stored processed job in Postgres")
        except Exception as exc:
            logger.error("Worker loop error", exc_info=exc)
            time.sleep(1)


if __name__ == "__main__":
    main()


