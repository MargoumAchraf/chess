const WebSocket = require("ws");

const ws = new WebSocket("ws://10.1.4.5:8080/rooms");

ws.on("message", (msg) => console.log(msg.toString()));

ws.on("open", () => {
  console.log("connected");
});