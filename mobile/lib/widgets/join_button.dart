
import 'package:flutter/material.dart';

class JoinButton extends StatelessWidget {
  static const Color primary = Color(0xFF6D4C41);

  final String status; // idle | waiting
  final VoidCallback onPressed;

  const JoinButton({
    super.key,
    required this.status,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final bool isWaiting = status == "waiting";

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: status == "idle" ? onPressed : null,
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
}