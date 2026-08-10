import 'package:flutter/material.dart';

/// A small bordered chip for a player's name with a dot + border color
/// indicating whether that player is white or black.
class PlayerChip extends StatelessWidget {
  final String name;
  final bool isWhite;

  const PlayerChip({
    super.key,
    required this.name,
    required this.isWhite,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isWhite
              ? Colors.white.withOpacity(0.85)
              : Colors.black.withOpacity(0.55),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isWhite ? Icons.circle : Icons.circle_outlined,
            size: 10,
            color: isWhite ? Colors.white : Colors.white70,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              name,
              style: TextStyle(
                color: isWhite ? Colors.white : const Color(0xFF1A1A1A),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}