import argparse
import random
import string
import time

import redis


def get_redis_client(host: str, port: int) -> redis.Redis:
    return redis.Redis(host=host, port=port, db=0, decode_responses=True)


def random_string(length: int = 8) -> str:
    return "".join(random.choices(string.ascii_lowercase + string.digits, k=length))


def generate_strings(r: redis.Redis, prefix: str, count: int):
    for i in range(count):
        key = f"{prefix}:{i}"
        value = random_string(16)
        r.set(key, value)
        print(f"SET {key} = {value}")


def generate_list(r: redis.Redis, key: str, count: int):
    for _ in range(count):
        value = random_string(12)
        r.rpush(key, value)
        print(f"RPUSH {key} {value}")


def generate_hashes(r: redis.Redis, prefix: str, count: int):
    for i in range(count):
        key = f"{prefix}:{i}"
        fields = {
            "id": str(i),
            "value": random_string(10),
            "created_at": str(time.time()),
        }
        r.hset(key, mapping=fields)
        print(f"HSET {key} {fields}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="redis", help="Redis host (use 'redis' in Docker)")
    parser.add_argument("--port", type=int, default=6379)
    parser.add_argument("--count", type=int, default=10)
    parser.add_argument("--prefix", default="lab:string")
    parser.add_argument("--list-key", default="lab:list")
    parser.add_argument("--hash-prefix", default="lab:hash")
    args = parser.parse_args()

    r = get_redis_client(args.host, args.port)

    print("Generating string keys...")
    generate_strings(r, args.prefix, args.count)

    print("\nGenerating list entries...")
    generate_list(r, args.list_key, args.count)

    print("\nGenerating hashes...")
    generate_hashes(r, args.hash_prefix, args.count)

    print("\nDone. Check Redis Commander to inspect the data.")


if __name__ == "__main__":
    main()


