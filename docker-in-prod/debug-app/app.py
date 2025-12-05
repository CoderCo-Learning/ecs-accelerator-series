# app.py
import logging
import os
import sys
import time
import random
from flask import Flask, jsonify, request

app = Flask(__name__)

# Configure logging to stdout
logging.basicConfig(
    level=os.getenv('LOG_LEVEL', 'INFO'),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger(__name__)

# Simulated state
start_time = time.time()
request_count = 0
error_count = 0

@app.route('/')
def home():
    global request_count
    request_count += 1
    logger.info(f"Home endpoint hit - Request #{request_count}")
    return jsonify({
        "message": "Demo Docker Debugging App",
        "uptime": f"{int(time.time() - start_time)}s",
        "requests": request_count,
        "errors": error_count
    })

@app.route('/health')
def health():
    """Health check that randomly fails"""
    uptime = time.time() - start_time
    
    # Fail health check after 60 seconds randomly
    if uptime > 60 and random.random() < 0.3:
        logger.error("Health check failed - simulated unhealthy state")
        return jsonify({"status": "unhealthy", "uptime": uptime}), 503
    
    logger.debug("Health check passed")
    return jsonify({"status": "healthy", "uptime": uptime}), 200

@app.route('/crash')
def crash():
    """Endpoint that causes a crash"""
    global error_count
    error_count += 1
    logger.error("Crash endpoint triggered - about to raise exception")
    raise Exception("Intentional crash for debugging demo")

@app.route('/slow')
def slow():
    """Slow endpoint"""
    delay = int(request.args.get('delay', 5))
    logger.warning(f"Slow endpoint - sleeping for {delay}s")
    time.sleep(delay)
    logger.info("Slow endpoint completed")
    return jsonify({"message": f"Slept for {delay}s"})

@app.route('/env')
def show_env():
    """Show environment variables"""
    logger.info("Environment variables requested")
    # Filter sensitive vars
    safe_env = {k: v for k, v in os.environ.items() 
                if not any(secret in k.lower() for secret in ['password', 'secret', 'key', 'token'])}
    return jsonify(safe_env)

@app.route('/files')
def list_files():
    """List files in /app directory"""
    logger.info("File listing requested")
    try:
        files = os.listdir('/app')
        return jsonify({"files": files, "cwd": os.getcwd()})
    except Exception as e:
        logger.error(f"Failed to list files: {e}")
        return jsonify({"error": str(e)}), 500

@app.before_request
def log_request():
    logger.info(f"Request: {request.method} {request.path} from {request.remote_addr}")

if __name__ == '__main__':
    logger.info("Starting Flask app on 0.0.0.0:5000")
    logger.info(f"Environment: {os.getenv('FLASK_ENV', 'production')}")
    logger.info(f"Log level: {os.getenv('LOG_LEVEL', 'INFO')}")
    
    app.run(host='0.0.0.0', port=5000, debug=False)