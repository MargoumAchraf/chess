import 'package:flutter/material.dart';
import 'package:mobile/screen/handleGame.dart';
import 'package:mobile/widgets/join_button.dart';
import 'package:mobile/widgets/message_list.dart';
import 'package:mobile/widgets/name_field.dart';
import 'package:mobile/widgets/restart_button.dart';
import 'package:mobile/widgets/status_chip.dart';
import 'package:mobile/widgets/welcome_text.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  static const Color primaryDark = Color(0xFF3E2723);
  static const Color primary = Color(0xFF6D4C41);
  static const Color bgTop = Color(0xFFFFF8F0);

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

    setState(() => username = name);

    lobbyChannel = IOWebSocketChannel.connect(
      Uri.parse(
        "wss://crusader-arming-riverboat.ngrok-free.dev/rooms?name=$username",
      ),
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
  // RESTART
  // ======================================================

  void restartLobby() {
    // Tear down any existing connection.
    lobbyChannel?.sink.close();
    lobbyChannel = null;

    setState(() {
      userId = "";
      status = "idle";
      messages.clear();
    });

    addMessage("🔄 Restarted. Ready to join again.");
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
    final bool isWaiting = status == "waiting";

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          "Chess Multiplayer",
          style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [primaryDark, primary],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.35],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 70),
              StatusChip(isWaiting: isWaiting, username: username),
              const SizedBox(height: 20),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: bgTop,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(28)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 12,
                        offset: Offset(0, -4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 24),
                      if (username.isNotEmpty) WelcomeText(username: username),
                      NameField(
                          controller: nameController, isWaiting: isWaiting),
                      const SizedBox(height: 16),
                      JoinButton(status: status, onPressed: connectLobby),
                      if (isWaiting) ...[
                        const SizedBox(height: 12),
                        RestartButton(onPressed: restartLobby),
                      ],
                      const SizedBox(height: 16),
                      const Divider(height: 1, thickness: 1),
                      Expanded(child: MessageList(messages: messages)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
