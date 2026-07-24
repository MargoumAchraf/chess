import 'package:flutter/material.dart';
import 'package:flutter/painting.dart' as painting;
import 'package:mobile/screen/LobbyScreen.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_chess_board/flutter_chess_board.dart' hide Color;

class GameScreen extends StatefulWidget {
  final WebSocketChannel gameChannel;
  final String userId;
  final String username;

  const GameScreen({
    super.key,
    required this.gameChannel,
    required this.userId,
    required this.username,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final ChessBoardController boardController = ChessBoardController();

  String color = "";
  String status = "playing"; // playing (kept for the turn banner)
  bool myTurn = false;
  bool _isApplyingOpponentMove = false;
  int _lastHistoryLength = 0;

  String? _selectedSquare;
  List<String> _validMoveSquares = [];

  // ── Game-over overlay state ──────────────────────────────────────────────
  bool _showGameOverOverlay = false;
  String _gameOverResult = ""; // "1-0" | "0-1" | "1/2-1/2"
  String _gameOverMethod = ""; // "Checkmate" | "Stalemate" | ...
  // ────────────────────────────────────────────────────────────────────────

  final List<String> messages = [];

  // ── Theme (matches LobbyScreen) ──────────────────────────────────────────
  static const Color primaryDark = Color(0xFF3E2723);
  static const Color primary = Color(0xFF6D4C41);
  static const Color accent = Color(0xFFD7A86E);
  static const Color bgTop = Color(0xFFFFF8F0);
  static const Color winGreen = Color(0xFF2E7D32);
  static const Color loseRed = Color(0xFFC62828);
  static const Color drawAmber = Color(0xFFB8860B);
  // ────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    addMessage("Joined room: ${widget.userId}");
    widget.gameChannel.stream.listen((msg) {
      handleGame(msg.toString());
    });
  }

  // ======================================================
  // GAME LOGIC
  // ======================================================

  void handleGame(String msg) {
    addMessage(msg);
    final plain = msg.trim();

    // 1. Color assignment
    if (plain == "white" || plain == "black") {
      setState(() {
        color = plain;
        myTurn = color == "white";
      });
      return;
    }

    // 2. Invalid move
    if (plain == "invalid_move") {
      setState(() => myTurn = true);
      addMessage("⚠️ Invalid move, try again");
      return;
    }

    // 3. Opponent move — LongAlgebraicNotation
    if (RegExp(
      r'^(O-O-O|O-O|[NBRQK]?[a-h][1-8]x?[a-h][1-8][qrbnQRBN]?)$',
    ).hasMatch(plain)) {
      _applyOpponentMove(plain);
      return;
    }

    // 4. Game over result
    if (plain == "1-0" || plain == "0-1" || plain == "1/2-1/2") {
      addMessage("🏁 Game Over: $plain");
      _triggerGameOver(plain);
      return;
    }

    // 5. Game method — store it for the overlay
    if (plain == "Checkmate" ||
        plain == "Stalemate" ||
        plain == "DrawOffer" ||
        plain == "ThreefoldRepetition" ||
        plain == "FivefoldRepetition" ||
        plain == "FiftyMoveRule" ||
        plain == "SeventyFiveMoveRule" ||
        plain == "InsufficientMaterial") {
      addMessage("📋 Method: $plain");
      setState(() => _gameOverMethod = plain);
      return;
    }

    // 6. Fallback
    addMessage("⚠️ Server: $plain");
  }

  // ======================================================
  // GAME OVER
  // ======================================================

  void _triggerGameOver(String result) {
    boardController.resetBoard();
    setState(() {
      _gameOverResult = result;
      _showGameOverOverlay = true;
      myTurn = false;
    });
  }

  void _dismissGameOver() {
    widget.gameChannel.sink.close();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LobbyScreen()),
    );
  }

  /// Returns (emoji, headline, subline, overlayColor)
  (String, String, String, painting.Color) _gameOverInfo() {
    final isWhite = color == "white";
    final method = _gameOverMethod.isNotEmpty ? _gameOverMethod : "";

    if (_gameOverResult == "1/2-1/2") {
      return (
        "🤝",
        "Draw!",
        method.isNotEmpty ? method : "Game drawn",
        drawAmber
      );
    }

    final iWon = (_gameOverResult == "1-0" && isWhite) ||
        (_gameOverResult == "0-1" && !isWhite);

    if (iWon) {
      return (
        "🏆",
        "You Won!",
        method.isNotEmpty ? method : "Congratulations",
        winGreen
      );
    } else {
      return (
        "😔",
        "You Lost",
        method.isNotEmpty ? method : "Better luck next time",
        loseRed
      );
    }
  }

  // ======================================================
  // SEND MOVE
  // ======================================================

  void sendMove() {
    if (_isApplyingOpponentMove) return;
    if (!myTurn) return;

    final history = boardController.game.history;
    if (history.length <= _lastHistoryLength) return;

    _lastHistoryLength = history.length;

    final move = history.last.move;
    final from = move.fromAlgebraic;
    final to = move.toAlgebraic;

    final isKingSideCastle = (move.flags & Chess.BITS_KSIDE_CASTLE) != 0;
    final isQueenSideCastle = (move.flags & Chess.BITS_QSIDE_CASTLE) != 0;

    String lan;

    if (isKingSideCastle) {
      lan = 'O-O';
    } else if (isQueenSideCastle) {
      lan = 'O-O-O';
    } else {
      final isCapture = (move.flags & Chess.BITS_CAPTURE) != 0 ||
          (move.flags & Chess.BITS_EP_CAPTURE) != 0;

      String promotion = '';
      if (move.promotion != null) {
        promotion = move.promotion!.name.toLowerCase()[0];
      }

      String piecePrefix = '';
      final piece = boardController.game.get(to);
      if (piece != null && move.promotion == null) {
        switch (piece.type) {
          case PieceType.KNIGHT:
            piecePrefix = 'N';
            break;
          case PieceType.BISHOP:
            piecePrefix = 'B';
            break;
          case PieceType.ROOK:
            piecePrefix = 'R';
            break;
          case PieceType.QUEEN:
            piecePrefix = 'Q';
            break;
          case PieceType.KING:
            piecePrefix = 'K';
            break;
          default:
            piecePrefix = '';
        }
      }

      if (promotion.isNotEmpty) {
        lan = '$from$to$promotion';
      } else if (isCapture) {
        lan = '$piecePrefix${from}x$to';
      } else {
        lan = '$piecePrefix$from$to';
      }
      if (promotion.isEmpty && boardController.game.in_checkmate) {
        lan = '$lan#';
      }
    }

    widget.gameChannel.sink.add(lan);

    setState(() {
      myTurn = false;
      _selectedSquare = null;
      _validMoveSquares = [];
    });

    addMessage("You: $lan");
  }

  // ======================================================
  // APPLY OPPONENT MOVE
  // ======================================================

  void _applyOpponentMove(String lan) {
    String from, to;
    String promotion = 'q';

    if (lan == 'O-O') {
      final isWhite = boardController.game.turn.name == 'WHITE';
      from = isWhite ? 'e1' : 'e8';
      to = isWhite ? 'g1' : 'g8';
    } else if (lan == 'O-O-O') {
      final isWhite = boardController.game.turn.name == 'WHITE';
      from = isWhite ? 'e1' : 'e8';
      to = isWhite ? 'c1' : 'c8';
    } else {
      String clean = lan;
      if (clean.isNotEmpty && RegExp(r'^[NBRQK]').hasMatch(clean)) {
        clean = clean.substring(1);
      }
      clean = clean.replaceAll('x', '');
      if (clean.length < 4) return;
      from = clean.substring(0, 2);
      to = clean.substring(2, 4);
      promotion = clean.length > 4 ? clean.substring(4, 5).toLowerCase() : 'q';
    }

    _isApplyingOpponentMove = true;
    boardController.makeMoveWithPromotion(
      from: from,
      to: to,
      pieceToPromoteTo: promotion,
    );
    _isApplyingOpponentMove = false;

    _lastHistoryLength = boardController.game.history.length;

    setState(() {
      myTurn = true;
      _selectedSquare = null;
      _validMoveSquares = [];
    });
  }

  // ======================================================
  // HIGHLIGHT
  // ======================================================

  void _onSquareTapped(String square) {
    if (!myTurn || _isApplyingOpponentMove) return;

    final game = boardController.game;

    if (_selectedSquare != null && _validMoveSquares.contains(square)) {
      final piece = game.get(_selectedSquare!);
      final isPromotion = piece != null &&
          piece.type == PieceType.PAWN &&
          (square[1] == '8' || square[1] == '1');

      if (isPromotion) {
        _showPromotionDialog(_selectedSquare!, square);
      } else {
        boardController.makeMove(from: _selectedSquare!, to: square);
        setState(() {
          _selectedSquare = null;
          _validMoveSquares = [];
        });
        sendMove();
      }
      return;
    }

    final piece = game.get(square);
    if (piece == null) {
      setState(() {
        _selectedSquare = null;
        _validMoveSquares = [];
      });
      return;
    }

    final isMyPiece = (color == 'white' && piece.color.name == 'WHITE') ||
        (color == 'black' && piece.color.name == 'BLACK');

    if (!isMyPiece) {
      setState(() {
        _selectedSquare = null;
        _validMoveSquares = [];
      });
      return;
    }

    final moves =
        game.moves({'square': square, 'verbose': true}) as List<dynamic>;
    final targets = moves.map((m) => (m as Map)['to'] as String).toList();

    setState(() {
      _selectedSquare = square;
      _validMoveSquares = targets;
    });
  }

  // ======================================================
  // PROMOTION DIALOG
  // ======================================================

  Future<void> _showPromotionDialog(String from, String to) async {
    final promoted = await showDialog<String>(
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
            _promotionButton('q', '♛'),
            _promotionButton('r', '♜'),
            _promotionButton('b', '♝'),
            _promotionButton('n', '♞'),
          ],
        ),
      ),
    );

    if (promoted == null) return;

    boardController.makeMoveWithPromotion(
      from: from,
      to: to,
      pieceToPromoteTo: promoted.toLowerCase(),
    );

    setState(() {
      _selectedSquare = null;
      _validMoveSquares = [];
    });

    sendMove();
  }

  Widget _promotionButton(String piece, String symbol) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(piece),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: bgTop,
          shape: BoxShape.circle,
          border: Border.all(color: accent, width: 1.5),
        ),
        child: Text(symbol, style: const TextStyle(fontSize: 34, color: primaryDark)),
      ),
    );
  }

  // ======================================================
  // OVERLAY BUILDER
  // ======================================================

  Widget _buildMoveOverlay(double boardSize) {
    return GestureDetector(
      onTapDown: (details) {
        final squareSize = boardSize / 8;
        final col = (details.localPosition.dx / squareSize).floor();
        final row = (details.localPosition.dy / squareSize).floor();
        if (col < 0 || col > 7 || row < 0 || row > 7) return;

        const files = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
        final ranks = color == 'black'
            ? ['1', '2', '3', '4', '5', '6', '7', '8']
            : ['8', '7', '6', '5', '4', '3', '2', '1'];
        final filesOrdered =
            color == 'black' ? ['h', 'g', 'f', 'e', 'd', 'c', 'b', 'a'] : files;

        _onSquareTapped('${filesOrdered[col]}${ranks[row]}');
      },
      child: CustomPaint(
        size: Size(boardSize, boardSize),
        painter: _MoveHighlightPainter(
          selectedSquare: _selectedSquare,
          validSquares: _validMoveSquares,
          isBlack: color == 'black',
        ),
      ),
    );
  }

  // ======================================================
  // GAME OVER OVERLAY
  // ======================================================

  Widget _buildGameOverOverlay(double boardSize) {
    final (emoji, headline, subline, accentColor) = _gameOverInfo();

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
              border: Border.all(color: accentColor.withOpacity(0.25), width: 1.5),
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
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _gameOverResult,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: accentColor,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _dismissGameOver,
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
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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

  // ======================================================
  // HELPERS
  // ======================================================

  void addMessage(String m) {
    setState(() => messages.insert(0, m));
  }

  @override
  void dispose() {
    widget.gameChannel.sink.close();
    super.dispose();
  }

  // ======================================================
  // UI
  // ======================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          "Chess Multiplayer",
          style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [primaryDark, primary],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.3],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 70),
              _buildStatusChip(),
              const SizedBox(height: 10),
              _buildTurnChip(),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: bgTop,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 12,
                        offset: Offset(0, -4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final boardSize = constraints.maxWidth;
                            return Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: primaryDark.withOpacity(0.15),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Stack(
                                  children: [
                                    ChessBoard(
                                      controller: boardController,
                                      enableUserMoves:
                                          myTurn && !_showGameOverOverlay,
                                      boardOrientation: color == "black"
                                          ? PlayerColor.black
                                          : PlayerColor.white,
                                      onMove: () => sendMove(),
                                    ),
                                    if (myTurn && !_showGameOverOverlay)
                                      Positioned.fill(
                                        child: _buildMoveOverlay(boardSize),
                                      ),
                                    if (_showGameOverOverlay)
                                      _buildGameOverOverlay(boardSize),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Divider(height: 1, thickness: 1),
                      Expanded(child: _buildMessageList()),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip() {
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
            color.isNotEmpty ? "Playing as ${color[0].toUpperCase()}${color.substring(1)}" : "Connecting…",
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

  Widget _buildTurnChip() {
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

  Widget _buildMessageList() {
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

// ======================================================
// CUSTOM PAINTER
// ======================================================

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