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






// D/DecorView[]( 2127): onWindowFocusChanged hasWindowFocus false
// I/ForceDarkHelperStubImpl( 2127): setViewRootImplForceDark: false for com.example.mobile.MainActivity@c541ec5, reason: AppDarkModeEnable
// D/VRI[MainActivity]( 2127): vri.reportNextDraw android.view.ViewRootImpl.performTraversals:4013 android.view.ViewRootImpl.doTraversal:2725 android.view.ViewRootImpl$TraversalRunnable.run:9812 android.view.Choreographer$CallbackRecord.run:1505 android.view.Choreographer$CallbackRecord.run:1513 
// D/SurfaceView( 2127): UPDATE Surface(name=SurfaceView[com.example.mobile/com.example.mobile.MainActivity])/@0x6f286eb, mIsProjectionMode = false
// D/VRI[MainActivity]( 2127): vri.Setup new sync id=1 syncSeqId=0
// D/VRI[MainActivity]( 2127): vri.reportDrawFinished syncSeqId=0 android.view.ViewRootImpl.lambda$createSyncIfNeeded$4$android-view-ViewRootImpl:4081 android.view.ViewRootImpl$$ExternalSyntheticLambda2.run:6 android.os.Handler.handleCallback:942 android.os.Handler.dispatchMessage:99 android.os.Looper.loopOnce:211 
// D/DecorView[]( 2127): onWindowFocusChanged hasWindowFocus true
// I/HandWritingStubImpl( 2127): refreshLastKeyboardType: 1
// I/HandWritingStubImpl( 2127): getCurrentKeyboardType: 1
