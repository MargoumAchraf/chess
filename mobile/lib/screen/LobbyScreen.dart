import 'package:flutter/material.dart';
import 'package:mobile/screen/handleGame.dart';
import 'package:mobile/widgets/message_list.dart';
import 'package:mobile/widgets/name_field.dart';
import 'package:mobile/widgets/restart_button.dart';
import 'package:mobile/widgets/status_chip.dart';
import 'package:mobile/widgets/welcome_text.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum LobbyMode { random, create, join }

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  static const Color primaryDark = Color(0xFF3E2723);
  static const Color primary = Color(0xFF6D4C41);
  static const Color bgTop = Color(0xFFFFF8F0);
  static const String baseUrl = "wss://crusader-arming-riverboat.ngrok-free.dev";

  WebSocketChannel? lobbyChannel;

  String userId = "";
  String username = "";
  String status = "idle"; // idle | waiting | hosting

  LobbyMode mode = LobbyMode.random;
  String? roomCode; // set once the server hands us a code to share

  final TextEditingController nameController = TextEditingController();
  final TextEditingController codeController = TextEditingController();
  final List<String> messages = [];

  bool get isBusy => status == "waiting" || status == "hosting";

  // ======================================================
  // CONNECT (dispatches based on selected mode)
  // ======================================================

  void connect() {
    final name = nameController.text.trim();
    if (name.isEmpty) {
      addMessage("⚠️ Enter name first");
      return;
    }

    setState(() {
      username = name;
      roomCode = null;
    });

    switch (mode) {
      case LobbyMode.random:
        _open("$baseUrl/rooms?name=$username", "waiting");
        break;
      case LobbyMode.create:
        _open("$baseUrl/rooms/create?name=$username", "hosting");
        break;
      case LobbyMode.join:
        final code = codeController.text.trim().toUpperCase();
        if (code.isEmpty) {
          addMessage("⚠️ Enter a room code first");
          return;
        }
        _open("$baseUrl/rooms/join/$code?name=$username", "waiting");
        break;
    }
  }

  void _open(String url, String newStatus) {
    print("Connecting to $url");
    lobbyChannel = IOWebSocketChannel.connect(Uri.parse(url));
    setState(() => status = newStatus);
    lobbyChannel!.stream.listen((msg) {
      print("Received message: $msg");
      handleLobby(msg.toString());
    });
  }

  // ======================================================
  // SHARED LOBBY MESSAGE HANDLING
  // ======================================================

  void handleLobby(String msg) {
    if (msg.startsWith("code:")) {
      final code = msg.substring("code:".length).trim();
      setState(() => roomCode = code);
      addMessage("🔑 Room code: $code — share it with your friend");
      return;
    }

    if (msg.startsWith("error:")) {
      addMessage("⚠️ ${msg.substring("error:".length).trim()}");
      restartLobby();
      return;
    }

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
      Uri.parse("$baseUrl/rooms/$clientId"),
    );

    addMessage("Joined room: $clientId");

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
    lobbyChannel?.sink.close();
    lobbyChannel = null;

    setState(() {
      userId = "";
      status = "idle";
      roomCode = null;
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

  String get connectLabel {
    switch (mode) {
      case LobbyMode.random:
        return "Join Random";
      case LobbyMode.create:
        return "Create Room";
      case LobbyMode.join:
        return "Join with Code";
    }
  }

  @override
  void dispose() {
    lobbyChannel?.sink.close();
    nameController.dispose();
    codeController.dispose();
    super.dispose();
  }

  // ======================================================
  // UI
  // ======================================================

  @override
  Widget build(BuildContext context) {
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
              StatusChip(isWaiting: isBusy, username: username),
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
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 24),
                        if (username.isNotEmpty)
                          WelcomeText(username: username),
                        NameField(
                            controller: nameController, isWaiting: isBusy),
                        const SizedBox(height: 20),

                        // ---- Mode selector (3 buttons) ----
                        if (!isBusy)
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            child: SegmentedButton<LobbyMode>(
                              segments: const [
                                ButtonSegment(
                                  value: LobbyMode.random,
                                  label: Text("Random"),
                                  icon: Icon(Icons.shuffle),
                                ),
                                ButtonSegment(
                                  value: LobbyMode.create,
                                  label: Text("Create"),
                                  icon: Icon(Icons.add_circle_outline),
                                ),
                                ButtonSegment(
                                  value: LobbyMode.join,
                                  label: Text("Join Code"),
                                  icon: Icon(Icons.key),
                                ),
                              ],
                              selected: {mode},
                              onSelectionChanged: (s) {
                                setState(() => mode = s.first);
                              },
                            ),
                          ),

                        // ---- Code input, only in Join mode ----
                        if (!isBusy && mode == LobbyMode.join) ...[
                          const SizedBox(height: 16),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 24),
                            child: TextField(
                              controller: codeController,
                              textCapitalization:
                                  TextCapitalization.characters,
                              maxLength: 4,
                              decoration: const InputDecoration(
                                labelText: "Enter room code",
                                counterText: "",
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 16),

                        // ---- Single action button, label depends on mode ----
                        if (!isBusy)
                          ElevatedButton(
                            onPressed: connect,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 32, vertical: 14),
                            ),
                            child: Text(connectLabel),
                          ),

                        // ---- Show generated code once hosting ----
                        if (roomCode != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 24),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            decoration: BoxDecoration(
                              color: primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: primary),
                            ),
                            child: Column(
                              children: [
                                const Text(
                                  "Share this code",
                                  style: TextStyle(color: Colors.black54),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  roomCode!,
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 4,
                                    color: primaryDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        if (isBusy) ...[
                          const SizedBox(height: 12),
                          RestartButton(onPressed: restartLobby),
                        ],

                        const SizedBox(height: 16),
                        const Divider(height: 1, thickness: 1),
                        SizedBox(
                          height: 200,
                          child: MessageList(messages: messages),
                        ),
                      ],
                    ),
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