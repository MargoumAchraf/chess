import 'package:flutter/material.dart';

/// Shows the pawn-promotion piece picker and returns the chosen piece
/// letter ("q", "r", "b", or "n"), or null if dismissed.
class PromotionDialog {
  static const Color primaryDark = Color(0xFF3E2723);
  static const Color accent = Color(0xFFD7A86E);
  static const Color bgTop = Color(0xFFFFF8F0);

  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          "Promote pawn",
          style: TextStyle(fontWeight: FontWeight.w600, color: primaryDark),
        ),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _button(context, 'q', '♛'),
            _button(context, 'r', '♜'),
            _button(context, 'b', '♝'),
            _button(context, 'n', '♞'),
          ],
        ),
      ),
    );
  }

  static Widget _button(BuildContext context, String piece, String symbol) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(piece),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: bgTop,
          shape: BoxShape.circle,
          border: Border.all(color: accent, width: 1.5),
        ),
        child: Text(
          symbol,
          style: const TextStyle(fontSize: 34, color: primaryDark),
        ),
      ),
    );
  }
}