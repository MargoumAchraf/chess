import 'package:flutter/material.dart';
import 'package:mobile/screen/handleGame.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';


class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  WebSocketChannel? lobbyChannel;

  String userId = "";
  String username = "";
  String status = "idle"; // idle | waiting

  final TextEditingController nameController = TextEditingController();
  final List<String> messages = [];

  // ======================================================
  // LOBBY
  // ======================================================

  void connectLobby() {
    final name = nameController.text.trim();
    if (name.isEmpty) {
      addMessage("⚠️ Enter name first");
      return;
    }

    username = name;

    lobbyChannel = IOWebSocketChannel.connect(
      Uri.parse("wss://crusader-arming-riverboat.ngrok-free.dev/rooms"),
    );

    setState(() => status = "waiting");

    lobbyChannel!.stream.listen((msg) {
      handleLobby(msg.toString());
    });
  }

  void handleLobby(String msg) {
    addMessage("Lobby: $msg");
    if (userId.isEmpty) {
      userId = msg.trim();
      connectGame(userId);
    }
  }

  // ======================================================
  // HAND OFF TO GAME SCREEN
  // ======================================================

  void connectGame(String clientId) {
    final gameChannel = IOWebSocketChannel.connect(
      Uri.parse(
        "wss://crusader-arming-riverboat.ngrok-free.dev/rooms/$clientId",
      ),
    );

    addMessage("Joined room: $clientId");

    // The lobby socket has served its purpose; the game socket takes over.
    lobbyChannel?.sink.close();

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => GameScreen(
          gameChannel: gameChannel,
          userId: clientId,
          username: username,
        ),
      ),
    );
  }

  // ======================================================
  // HELPERS
  // ======================================================

  void addMessage(String m) {
    setState(() => messages.insert(0, m));
  }

  @override
  void dispose() {
    lobbyChannel?.sink.close();
    nameController.dispose();
    super.dispose();
  }

  // ======================================================
  // UI
  // ======================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Chess Multiplayer"),
        backgroundColor: Colors.brown,
      ),
      body: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.brown.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              "Status: $status",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: "Your Name",
                border: OutlineInputBorder(),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: status == "idle" ? connectLobby : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.brown,
              foregroundColor: Colors.white,
            ),
            child: Text(
              status == "waiting" ? "Waiting for opponent…" : "Join Game",
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: messages.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Text(
                  messages[i],
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}