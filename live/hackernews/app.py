from flask import Flask, jsonify
import requests

app = Flask(__name__)

@app.route('/')
def home():
    return jsonify({"message": "HN API Wrapper", "endpoints": ["/top", "/latest"]})

@app.route('/top')
def top_stories():
    url = "https://hacker-news.firebaseio.com/v0/topstories.json"
    response = requests.get(url)
    story_ids = response.json()[:10]  # Get top 10
    return jsonify({"top_stories": story_ids})

@app.route('/latest')
def latest_stories():
    url = "https://hacker-news.firebaseio.com/v0/newstories.json"
    response = requests.get(url)
    story_ids = response.json()[:10]
    return jsonify({"latest_stories": story_ids})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)