from flask import Flask, render_template_string, request, redirect

app = Flask(__name__)
tasks = []

@app.get("/")
def home():
    return render_template_string("""
        <h2>Todo List</h2>
        <form method='POST'>
            <input name='task'> <button>Add</button>
        </form>
        <ul>
        {% for t in tasks %}
            <li>{{ t }}</li>
        {% endfor %}
        </ul>
    """)

@app.post("/")
def add():
    tasks.append(request.form['task'])
    return redirect("/")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
