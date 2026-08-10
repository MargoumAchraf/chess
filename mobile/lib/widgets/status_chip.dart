import 'package:flutter/material.dart';

class StatusChip extends StatelessWidget {
  static const Color accent = Color(0xFFD7A86E);

  final bool isWaiting;
  final String username;

  const StatusChip({
    super.key,
    required this.isWaiting,
    required this.username,
  });

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
            isWaiting
                ? (username.isNotEmpty
                    ? "Waiting for opponent, $username…"
                    : "Waiting for opponent…")
                : "Idle",
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