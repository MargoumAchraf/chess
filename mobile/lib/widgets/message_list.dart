import 'package:flutter/material.dart';

class MessageList extends StatelessWidget {
  final List<String> messages;

  const MessageList({super.key, required this.messages});

  @override
  Widget build(BuildContext context) {
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