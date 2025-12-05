#!/bin/sh

# Check if Flask is responding
response=$(wget --timeout=2 --tries=1 -q -O - http://localhost:5000/health)
exit_code=$?

if [ $exit_code -ne 0 ]; then
    echo "Health check failed - Flask not responding"
    exit 1
fi

# Check if response contains "healthy"
if echo "$response" | grep -q '"status": "healthy"'; then
    exit 0
else
    echo "Health check failed - unhealthy status"
    exit 1
fi