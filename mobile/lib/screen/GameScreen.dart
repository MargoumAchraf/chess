import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
class GameScreen extends StatelessWidget {
  final String userId;
  final String name;

  const GameScreen({
    super.key,
    required this.userId,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Player: $name"),
      ),
      body: Center(
        child: Text("Game started for $name"),
      ),
    );
  }
}