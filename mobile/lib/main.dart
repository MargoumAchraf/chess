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
  late WebSocketChannel lobbyChannel;
  late WebSocketChannel gameChannel;

  bool connected = false;
  String userId = "";

  List<String> messages = [];

  // 1) CONNECT TO LOBBY
  void connectLobby() {
    lobbyChannel = IOWebSocketChannel.connect(
      Uri.parse("ws://10.1.4.5:8080/rooms"),
    );

    lobbyChannel.stream.listen((message) {
      setState(() {
        userId = message.toString();
        messages.add("USER ID: $userId");
      });

      // بعد ما يوصلك ID → دخل للgame
      connectGame(userId);
    }, onError: (e) {
      print("Lobby error: $e");
    });

    setState(() {
      connected = true;
    });
  }

  // 2) CONNECT TO GAME SOCKET
  void connectGame(String id) {
    gameChannel = IOWebSocketChannel.connect(
      Uri.parse("wss://crusader-arming-riverboat.ngrok-free.dev/rooms"),
    );

    gameChannel.stream.listen((message) {
      setState(() {
        messages.add("GAME: $message");
      });
    }, onError: (e) {
      print("Game error: $e");
    }, onDone: () {
      print("Game closed");
    });
  }

  @override
  void dispose() {
    if (connected) {
      lobbyChannel.sink.close();
      gameChannel.sink.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Chess Lobby"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: connectLobby,
              child: const Text("Connect to Lobby"),
            ),

            const SizedBox(height: 20),

            if (userId.isNotEmpty)
              Text(
                "Your ID: $userId",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),

            const SizedBox(height: 20),

            Expanded(
              child: ListView.builder(
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  return Text(messages[index]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}