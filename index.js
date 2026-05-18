// const WebSocket = require("ws");

// const ws = new WebSocket("wss://crusader-arming-riverboat.ngrok-free.dev/rooms/2f848f72-6b21-474f-b107-ef3db0894727");

// ws.on("message", (msg) => console.log(msg.toString()));

// ws.on("open", () => {
//   console.log("connected");
// });


const WebSocket = require("ws");

const ws = new WebSocket("wss://crusader-arming-riverboat.ngrok-free.dev/rooms/6f221196-97da-4253-9f48-23de757881cb");

ws.on("open", () => {
  console.log("connected");
  // ws.send("Hassan"); // ← زيد هادي
});

ws.on("message", (msg) => console.log(msg.toString()));