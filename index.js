const WebSocket = require("ws");

const ws = new WebSocket("wss://crusader-arming-riverboat.ngrok-free.dev/rooms");

ws.on("message", (msg) => console.log(msg.toString()));

ws.on("open", () => {
  console.log("connected");
});