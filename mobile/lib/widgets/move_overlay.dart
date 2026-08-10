import 'package:flutter/material.dart';

/// Transparent tap-catcher + highlight painter drawn on top of the chess
/// board while it's the local player's turn. Reports taps back as algebraic
/// squares (e.g. "e4"), accounting for board orientation.
class MoveOverlay extends StatelessWidget {
  final double boardSize;
  final String? selectedSquare;
  final List<String> validSquares;
  final bool isBlack;
  final ValueChanged<String> onSquareTapped;

  const MoveOverlay({
    super.key,
    required this.boardSize,
    required this.selectedSquare,
    required this.validSquares,
    required this.isBlack,
    required this.onSquareTapped,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (details) {
        final squareSize = boardSize / 8;
        final col = (details.localPosition.dx / squareSize).floor();
        final row = (details.localPosition.dy / squareSize).floor();
        if (col < 0 || col > 7 || row < 0 || row > 7) return;

        const files = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
        final ranks = isBlack
            ? ['1', '2', '3', '4', '5', '6', '7', '8']
            : ['8', '7', '6', '5', '4', '3', '2', '1'];
        final filesOrdered =
            isBlack ? ['h', 'g', 'f', 'e', 'd', 'c', 'b', 'a'] : files;

        onSquareTapped('${filesOrdered[col]}${ranks[row]}');
      },
      child: CustomPaint(
        size: Size(boardSize, boardSize),
        painter: _MoveHighlightPainter(
          selectedSquare: selectedSquare,
          validSquares: validSquares,
          isBlack: isBlack,
        ),
      ),
    );
  }
}

class _MoveHighlightPainter extends CustomPainter {
  final String? selectedSquare;
  final List<String> validSquares;
  final bool isBlack;

  const _MoveHighlightPainter({
    required this.selectedSquare,
    required this.validSquares,
    required this.isBlack,
  });

  Offset _squareToOffset(String sq, double squareSize) {
    final files = isBlack
        ? ['h', 'g', 'f', 'e', 'd', 'c', 'b', 'a']
        : ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
    final ranks = isBlack
        ? ['1', '2', '3', '4', '5', '6', '7', '8']
        : ['8', '7', '6', '5', '4', '3', '2', '1'];

    final col = files.indexOf(sq[0]);
    final row = ranks.indexOf(sq[1]);
    return Offset(col * squareSize, row * squareSize);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final squareSize = size.width / 8;

    if (selectedSquare != null) {
      final offset = _squareToOffset(selectedSquare!, squareSize);
      canvas.drawRect(
        Rect.fromLTWH(offset.dx, offset.dy, squareSize, squareSize),
        Paint()..color = const Color(0xFFD7A86E).withOpacity(0.55),
      );
    }

    final dotPaint = Paint()..color = const Color(0xFF2E7D32).withOpacity(0.55);
    for (final sq in validSquares) {
      final offset = _squareToOffset(sq, squareSize);
      final center = Offset(
        offset.dx + squareSize / 2,
        offset.dy + squareSize / 2,
      );
      canvas.drawCircle(center, squareSize * 0.18, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_MoveHighlightPainter old) =>
      old.selectedSquare != selectedSquare ||
      old.validSquares != validSquares ||
      old.isBlack != isBlack;
}