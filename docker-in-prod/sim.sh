#!/bin/bash
# generate-traffic.sh - Simulate realistic container activity

set -e

CONTAINER_NAME="debug-demo"
PORT="8080"

echo "========================================="
echo "Traffic Generator for Docker Debug Demo"
echo "========================================="
echo ""

# Colours for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Colour

# Check if container is running
if ! docker ps | grep -q $CONTAINER_NAME; then
    echo -e "${RED}Error: Container $CONTAINER_NAME is not running${NC}"
    echo "Start it with: docker run -d --name $CONTAINER_NAME -p $PORT:$PORT debug-demo:latest"
    exit 1
fi

echo -e "${GREEN}Container is running. Starting traffic generation...${NC}"
echo ""

# Function to make request and show result
make_request() {
    local endpoint=$1
    local method=${2:-GET}
    local expected_code=${3:-200}
    
    echo -n "→ $method $endpoint ... "
    response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT$endpoint)
    
    if [ "$response" -eq "$expected_code" ]; then
        echo -e "${GREEN}$response OK${NC}"
    else
        echo -e "${RED}$response (expected $expected_code)${NC}"
    fi
}

# Simulate realistic user traffic patterns
echo "========================================="
echo "Phase 1: Normal User Traffic"
echo "========================================="
echo ""

for i in {1..5}; do
    make_request "/" 200
    sleep 0.5
done

echo ""
make_request "/health"
echo ""

echo "========================================="
echo "Phase 2: API Requests"
echo "========================================="
echo ""

make_request "/env"
make_request "/files"
sleep 1

echo ""
echo "========================================="
echo "Phase 3: Slow Requests (Timeout Testing)"
echo "========================================="
echo ""

make_request "/slow?delay=2"
sleep 2
make_request "/slow?delay=3"
sleep 3

echo ""
echo "========================================="
echo "Phase 4: Error Generation"
echo "========================================="
echo ""

echo -e "${YELLOW}Triggering crash endpoint (will generate errors)...${NC}"
for i in {1..3}; do
    make_request "/crash" GET 500
    sleep 1
done

echo ""
echo "========================================="
echo "Phase 5: High Load Burst"
echo "========================================="
echo ""

echo "Generating 20 rapid requests..."
for i in {1..20}; do
    curl -s http://localhost:$PORT/ > /dev/null &
done
wait
echo -e "${GREEN}Burst complete${NC}"

sleep 2

echo ""
echo "========================================="
echo "Phase 6: Health Check Monitoring"
echo "========================================="
echo ""

for i in {1..5}; do
    make_request "/health"
    sleep 2
done

echo ""
echo "========================================="
echo "Phase 7: Mixed Traffic"
echo "========================================="
echo ""

# Simulate realistic mixed traffic
endpoints=("/" "/health" "/env" "/files" "/slow?delay=1")
for i in {1..10}; do
    endpoint=${endpoints[$RANDOM % ${#endpoints[@]}]}
    make_request "$endpoint"
    sleep $(awk -v min=0.5 -v max=2 'BEGIN{srand(); print min+rand()*(max-min)}')
done

echo ""
echo "========================================="
echo "Traffic Generation Complete!"
echo "========================================="
echo ""
echo "Now check the logs and container state:"
echo ""
echo -e "${GREEN}# View all logs:${NC}"
echo "docker logs $CONTAINER_NAME"
echo ""
echo -e "${GREEN}# Follow live logs:${NC}"
echo "docker logs -f $CONTAINER_NAME"
echo ""
echo -e "${GREEN}# Filter for errors:${NC}"
echo "docker logs $CONTAINER_NAME 2>&1 | grep ERROR"
echo ""
echo -e "${GREEN}# Check container stats:${NC}"
echo "docker stats --no-stream $CONTAINER_NAME"
echo ""
echo -e "${GREEN}# Enter container:${NC}"
echo "docker exec -it $CONTAINER_NAME sh"
echo ""