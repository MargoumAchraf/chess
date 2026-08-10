import 'package:flutter/material.dart';

class TurnChip extends StatelessWidget {
  static const Color winGreen = Color(0xFF2E7D32);
  static const Color accent = Color(0xFFD7A86E);

  final bool myTurn;

  const TurnChip({super.key, required this.myTurn});

  @override
  Widget build(BuildContext context) {
    final label = myTurn ? "♟ Your turn" : "⏳ Opponent's turn";
    final chipColor = myTurn ? winGreen : accent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: chipColor.withOpacity(0.85),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }
}