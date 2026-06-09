import 'package:flutter/material.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_chess_board/flutter_chess_board.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LobbyScreen(),
    );
  }
}

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  WebSocketChannel? lobbyChannel;
  WebSocketChannel? gameChannel;

  final ChessBoardController boardController = ChessBoardController();

  String userId = "";
  String username = "";
  String color = "";
  String status = "idle";
  bool myTurn = false;
  bool _isApplyingOpponentMove = false;
  int _lastHistoryLength = 0;

  String? _selectedSquare;
  List<String> _validMoveSquares = [];

  List<String> messages = [];
  final TextEditingController nameController = TextEditingController();

  // ======================================================
  // LOBBY
  // ======================================================

  void connectLobby() {
    final name = nameController.text.trim();
    if (name.isEmpty) {
      addMessage("⚠️ Enter name first");
      return;
    }

    username = name;

    lobbyChannel = IOWebSocketChannel.connect(
      Uri.parse("wss://crusader-arming-riverboat.ngrok-free.dev/rooms"),
    );

    setState(() => status = "waiting");

    lobbyChannel!.stream.listen((msg) {
      handleLobby(msg.toString());
    });
  }

  void handleLobby(String msg) {
    addMessage("Lobby: $msg");
    if (userId.isEmpty) {
      userId = msg.trim();
      connectGame(userId);
    }
  }

  // ======================================================
  // GAME SOCKET
  // ======================================================

  void connectGame(String clientId) {
    gameChannel = IOWebSocketChannel.connect(
      Uri.parse(
        "wss://crusader-arming-riverboat.ngrok-free.dev/rooms/$clientId",
      ),
    );

    gameChannel!.stream.listen((msg) {
      handleGame(msg.toString());
    });

    addMessage("Joined room: $clientId");
  }

  // ======================================================
  // GAME LOGIC
  // ======================================================

  void handleGame(String msg) {
    addMessage(msg);
    print("Received from game socket: $msg");
    final plain = msg.trim();

    // 1. Color assignment
    if (plain == "white" || plain == "black") {
      setState(() {
        color = plain;
        status = "playing";
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
      boardController.resetBoard();
      setState(() {
        status = "idle";
        myTurn = false;
        color = "";
        userId = "";
        _lastHistoryLength = 0;
        _selectedSquare = null;
        _validMoveSquares = [];
      });
      return;
    }

    // 5. Game method
    if (plain == "Checkmate" ||
        plain == "Stalemate" ||
        plain == "DrawOffer" ||
        plain == "ThreefoldRepetition" ||
        plain == "FivefoldRepetition" ||
        plain == "FiftyMoveRule" ||
        plain == "SeventyFiveMoveRule" ||
        plain == "InsufficientMaterial") {
      addMessage("📋 Method: $plain");
      return;
    }

    // 6. Fallback
    addMessage("⚠️ Server: $plain");
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

    // ================= CASTLING =================
    if (isKingSideCastle) {
      lan = 'O-O';
    } else if (isQueenSideCastle) {
      lan = 'O-O-O';
    }

    // ================= NORMAL MOVES =================
    else {
      final isCapture = (move.flags & Chess.BITS_CAPTURE) != 0 ||
          (move.flags & Chess.BITS_EP_CAPTURE) != 0;

      // ✅ ONLY promotion if it really exists
      String promotion = '';
      if (move.promotion != null) {
        promotion = move.promotion!.name.toLowerCase()[0];
      }
      if (promotion.isNotEmpty) {
        print(
            "Promotion detected in sendMove: $from → $to, promote to $promotion");
      }
      String promotionmove = promotion.toLowerCase();
      print("Promotion move variable: $promotionmove");
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

      // ================= FORMAT =================
      if (promotion.isNotEmpty) {
        // pawn promotion (NO x handling needed in UCI)
        print("Promotion move detected: $from → $to, promote to $promotion");
        lan = '$from$to$promotion';
      } else if (isCapture) {
        lan = '$piecePrefix${from}x$to';
      } else {
        lan = '$piecePrefix$from$to';
      }
    }

    print("📤 Sending: $lan");
    gameChannel?.sink.add(lan);

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
    print("♟ Raw received: '$lan'");
    print(
        "♟ Current turn: ${boardController.game.turn == Chess.WHITE ? 'WHITE' : 'BLACK'}");

    String from, to;
    String promotion = 'q';

    if (lan == 'O-O') {
      final isWhite = boardController.game.turn == Chess.WHITE;
      print("♟ Kingside castle for: ${isWhite ? 'WHITE' : 'BLACK'}");
      from = isWhite ? 'e1' : 'e8';
      to = isWhite ? 'g1' : 'g8';
    } else if (lan == 'O-O-O') {
      final isWhite = boardController.game.turn == Chess.WHITE;
      print("♟ Queenside castle for: ${isWhite ? 'WHITE' : 'BLACK'}");
      from = isWhite ? 'e1' : 'e8';
      to = isWhite ? 'c1' : 'c8';
    } else {
      String clean = lan;

      // Strip piece prefix: "Nf3g5" → "f3g5"
      if (clean.isNotEmpty && RegExp(r'^[NBRQK]').hasMatch(clean)) {
        clean = clean.substring(1);
      }

      // Strip capture 'x': "f4xd5" → "f4d5"
      clean = clean.replaceAll('x', '');

      if (clean.length < 4) return;

      from = clean.substring(0, 2);
      to = clean.substring(2, 4);

      // Extract promotion if exists (5th character)
      promotion = clean.length > 4 ? clean.substring(4, 5).toLowerCase() : 'q';
    }

    _isApplyingOpponentMove = true;
    final result = boardController.makeMoveWithPromotion(
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
      // Check if this is a promotion move
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

    final isMyPiece = (color == 'white' && piece.color == Color.WHITE) ||
        (color == 'black' && piece.color == Color.BLACK);

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
  // PROMOTION DIALOG  ← FIXED
  // ======================================================

  Future<void> _showPromotionDialog(String from, String to) async {
    final promoted = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("Promote pawn"),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // ✅ Use lowercase letters to match flutter_chess_board PieceType
            _promotionButton('q', '♛'),
            _promotionButton('r', '♜'),
            _promotionButton('b', '♝'),
            _promotionButton('n', '♞'),
          ],
        ),
      ),
    );

    if (promoted == null) return;

    print("Promoting to: $promoted");
    String promotionmove = promoted.toLowerCase();
    // ✅ Pass the chosen piece — was missing in the original
    boardController.makeMoveWithPromotion(
      from: from,
      to: to,
      pieceToPromoteTo: promotionmove,
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
      child: Text(symbol, style: const TextStyle(fontSize: 40)),
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
  // HELPERS
  // ======================================================

  void addMessage(String m) {
    setState(() => messages.insert(0, m));
  }

  @override
  void dispose() {
    lobbyChannel?.sink.close();
    gameChannel?.sink.close();
    nameController.dispose();
    super.dispose();
  }

  // ======================================================
  // UI
  // ======================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Chess Multiplayer"),
        backgroundColor: Colors.brown,
      ),
      body: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.brown.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              "Status: $status${color.isNotEmpty ? ' | Playing as $color' : ''}",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          if (status == "idle" || status == "waiting") ...[
            Padding(
              padding: const EdgeInsets.all(10),
              child: TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: "Your Name",
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            ElevatedButton(
              onPressed: status == "idle" ? connectLobby : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.brown,
                foregroundColor: Colors.white,
              ),
              child: Text(
                status == "waiting" ? "Waiting for opponent…" : "Join Game",
              ),
            ),
          ],
          if (status == "playing") ...[
            Text(
              myTurn ? "♟ Your turn" : "⏳ Opponent's turn",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: myTurn ? Colors.green : Colors.orange,
              ),
            ),
            const SizedBox(height: 4),
            LayoutBuilder(
              builder: (context, constraints) {
                final boardSize = constraints.maxWidth;
                return Stack(
                  children: [
                    ChessBoard(
                      controller: boardController,
                      enableUserMoves: myTurn,
                      boardOrientation: color == "black"
                          ? PlayerColor.black
                          : PlayerColor.white,
                      onMove: () => sendMove(),
                    ),
                    if (myTurn)
                      Positioned.fill(
                        child: _buildMoveOverlay(boardSize),
                      ),
                  ],
                );
              },
            ),
          ],
          const Divider(),
          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: messages.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Text(
                  messages[i],
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
        ],
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
        Paint()..color = Colors.yellow.withOpacity(0.45),
      );
    }

    final dotPaint = Paint()..color = Colors.green.withOpacity(0.55);
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
