import 'package:flutter/material.dart';

class GameOverOverlay extends StatelessWidget {
  static const Color primaryDark = Color(0xFF3E2723);
  static const Color primary = Color(0xFF6D4C41);
  static const Color bgTop = Color(0xFFFFF8F0);

  final double boardSize;
  final String emoji;
  final String headline;
  final String subline;
  final Color accentColor;
  final VoidCallback onPlayAgain;

  const GameOverOverlay({
    super.key,
    required this.boardSize,
    required this.emoji,
    required this.headline,
    required this.subline,
    required this.accentColor,
    required this.onPlayAgain,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.72),
        child: Center(
          child: Container(
            width: boardSize * 0.82,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            decoration: BoxDecoration(
              color: bgTop,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: accentColor.withOpacity(0.25),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 32,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 56)),
                const SizedBox(height: 12),
                Text(
                  headline,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: accentColor,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subline,
                  style: TextStyle(
                    fontSize: 15,
                    color: primaryDark.withOpacity(0.65),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onPlayAgain,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: const Text(
                      "Play Again",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}