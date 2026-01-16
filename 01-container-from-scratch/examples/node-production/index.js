const express = require("express");
const app = express();

app.get("/", (req, res) => res.send("Hello from node-production!"));
app.listen(3000);
