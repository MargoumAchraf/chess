import 'package:flutter/material.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LobbyScreen(),
    );
  }
}

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  WebSocketChannel? lobbyChannel;
  WebSocketChannel? gameChannel;

  String userId = "";
  String color = "";
  String status = "idle";
  List<String> messages = [];

  final TextEditingController moveController = TextEditingController();
  final TextEditingController nameController = TextEditingController(); // ← زيدها

  void connectLobby() {
    final name = nameController.text.trim();
    if (name.isEmpty) {
      setState(() => messages.add("⚠️ دخل سميتك أولا!"));
      return;
    }

    lobbyChannel = IOWebSocketChannel.connect(
      Uri.parse("wss://crusader-arming-riverboat.ngrok-free.dev/rooms"),
    );

    setState(() => status = "waiting");

    // ← سيفط الاسم أول حاجة
    lobbyChannel!.sink.add(name);

    lobbyChannel!.stream.listen((message) {
      final msg = message.toString();

      if (userId.isEmpty) {
        setState(() {
          userId = msg;
          messages.add("✅ USER ID: $userId");
        });
        connectGame(userId);
      }
    }, onError: (e) {
      setState(() => messages.add("❌ Lobby error: $e"));
    });
  }

  void connectGame(String id) {
    gameChannel = IOWebSocketChannel.connect(
      Uri.parse("wss://crusader-arming-riverboat.ngrok-free.dev/rooms/$id"),
    );

    gameChannel!.stream.listen((message) {
      final msg = message.toString();

      if (color.isEmpty) {
        setState(() {
          color = msg;
          status = "playing";
          messages.add("🎨 Color: $color");
        });
        return;
      }

      if (msg == "1-0" || msg == "0-1" || msg == "1/2-1/2") {
        setState(() {
          messages.add("🏁 Outcome: $msg");
          status = "idle";
        });
        return;
      }

      setState(() => messages.add("♟️ Opponent move: $msg"));
    }, onError: (e) {
      setState(() => messages.add("❌ Game error: $e"));
    }, onDone: () {
      setState(() {
        messages.add("🔌 Game closed");
        status = "idle";
      });
    });
  }

  void sendMove() {
    final move = moveController.text.trim();
    if (move.isEmpty || gameChannel == null) return;

    gameChannel!.sink.add(move);
    setState(() {
      messages.add("➡️ You played: $move");
      moveController.clear();
    });
  }

  @override
  void dispose() {
    lobbyChannel?.sink.close();
    gameChannel?.sink.close();
    moveController.dispose();
    nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Chess Lobby"),
        backgroundColor: Colors.brown,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              "Status: $status ${color.isNotEmpty ? '| $color' : ''}",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            // ← input ديال الاسم
            if (status == "idle") ...[
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  hintText: "دخل سميتك...",
                  border: OutlineInputBorder(),
                  labelText: "الاسم",
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: connectLobby,
                child: const Text("Connect to Lobby"),
              ),
            ],

            const SizedBox(height: 10),

            if (status == "playing") ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: moveController,
                      decoration: const InputDecoration(
                        hintText: "e.g. e2e4",
                        border: OutlineInputBorder(),
                        labelText: "Your Move",
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: sendMove,
                    child: const Text("Send"),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],

            Expanded(
              child: ListView.builder(
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(messages[index]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}