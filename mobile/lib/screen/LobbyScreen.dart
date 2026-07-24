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

  // Theme colors
  static const Color primaryDark = Color(0xFF3E2723);
  static const Color primary = Color(0xFF6D4C41);
  static const Color accent = Color(0xFFD7A86E);
  static const Color bgTop = Color(0xFFFFF8F0);

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
              _buildStatusChip(isWaiting),
              const SizedBox(height: 20),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: bgTop,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                      _buildNameField(isWaiting),
                      const SizedBox(height: 16),
                      _buildJoinButton(isWaiting),
                      const SizedBox(height: 16),
                      const Divider(height: 1, thickness: 1),
                      Expanded(child: _buildMessageList()),
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

  Widget _buildStatusChip(bool isWaiting) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isWaiting)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            )
          else
            const Icon(Icons.circle, size: 10, color: Colors.greenAccent),
          const SizedBox(width: 10),
          Text(
            isWaiting ? "Waiting for opponent…" : "Idle",
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNameField(bool isWaiting) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: TextField(
        controller: nameController,
        enabled: !isWaiting,
        decoration: InputDecoration(
          labelText: "Your Name",
          prefixIcon: const Icon(Icons.person_outline, color: primary),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.brown.shade100),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: primary, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildJoinButton(bool isWaiting) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: status == "idle" ? connectLobby : null,
          icon: Icon(isWaiting ? Icons.hourglass_top : Icons.play_arrow),
          label: Text(
            isWaiting ? "Waiting for opponent…" : "Join Game",
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: primary.withOpacity(0.5),
            disabledForegroundColor: Colors.white70,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 2,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    if (messages.isEmpty) {
      return const Center(
        child: Text(
          "No activity yet",
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      reverse: true,
      itemCount: messages.length,
      itemBuilder: (_, i) => Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.brown.shade100),
        ),
        child: Text(
          messages[i],
          style: const TextStyle(fontSize: 13, color: Colors.black87),
        ),
      ),
    );
  }
}