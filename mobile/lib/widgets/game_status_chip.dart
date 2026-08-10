import 'package:flutter/material.dart';

/// Shows the local player's assigned color, or "Connecting…" before it's known.
class GameStatusChip extends StatelessWidget {
  final String color; // "white" | "black" | ""

  const GameStatusChip({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
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
          Icon(
            color == 'white' ? Icons.circle : Icons.circle_outlined,
            size: 12,
            color: color == 'white' ? Colors.white : Colors.white70,
          ),
          const SizedBox(width: 10),
          Text(
            color.isNotEmpty
                ? "Playing as ${color[0].toUpperCase()}${color.substring(1)}"
                : "Connecting…",
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
}