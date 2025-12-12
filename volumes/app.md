# Build app

```bash
docker build -t volume-demo .
```

## Demo 1 - No Volumes

```bash
docker run -p 3000:3000 --name demo1 volume-demo

curl -X POST localhost:3000/add -H "Content-Type: application/json" \
  -d '{"text":"hello world"}'
curl localhost:3000

docker rm -f demo1

## Run again

docker run -p 3000:3000 --name demo1 volume-demo
curl localhost:3000

## All notes are gone → container filesystems are ephemeral.

# This sets up the WHY for volumes.
```

## Demo 2 - Bind Mounts (local dir)

```bash
mkdir data

docker run \
  -p 3000:3000 \
  -v $(pwd)/data:/data \
  --name demo2 \
  volume-demo

curl -X POST localhost:3000/add -H "Content-Type: application/json" \
  -d '{"text":"persist me"}'

cat data/notes.txt

##Kill + restart:

docker rm -f demo2
docker run \
  -p 3000:3000 \
  -v $(pwd)/data:/data \
  --name demo2 \
  volume-demo

curl localhost:3000

## Data survives container destruction → bind mounts are your dev best friend.
```

## Demo 3 - Named volumes (production-ish)

```bash
docker volume create notesvol

docker run \
  -p 3000:3000 \
  -v notesvol:/data \
  --name demo3 \
  volume-demo

##Add a note → kill container → re-run → data still exists.

curl -X POST localhost:3000/add -H "Content-Type: application/json" \
  -d '{"text":"persist me"}'

cat data/notes.txt

##Kill + restart:

docker rm -f demo3
docker run \
  -p 3000:3000 \
  -v notesvol:/data \
  --name demo3 \
  volume-demo

curl localhost:3000

## Data survives container destruction → named volumes are your production best friend.

### Inspect the volume:
docker volume inspect notesvol
```