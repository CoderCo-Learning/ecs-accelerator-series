const fs = require('fs');
const express = require('express');
const app = express();

const FILE = "/data/notes.txt"; // this will live inside a volume

app.use(express.json());

app.get("/", (req, res) => {
  const notes = fs.existsSync(FILE) ? fs.readFileSync(FILE, "utf8") : "";
  res.send(`Current Notes:\n${notes}`);
});

app.post("/add", (req, res) => {
  const { text } = req.body;
  fs.appendFileSync(FILE, text + "\n");
  res.send("Note added!");
});

app.listen(3000, () => console.log("App running on 3000"));
