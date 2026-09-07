import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/painting.dart' as painting;
import 'package:mobile/screen/LobbyScreen.dart';
import 'package:mobile/widgets/game_over_overlay.dart';
import 'package:mobile/widgets/game_status_chip.dart';
import 'package:mobile/widgets/move_overlay.dart';
import 'package:mobile/widgets/player_chip.dart';
import 'package:mobile/widgets/promotion_dialog.dart';
import 'package:mobile/widgets/turn_chip.dart';
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
  String status = "playing";
  bool myTurn = false;
  bool _isApplyingOpponentMove = false;
  int _lastHistoryLength = 0;

  String? _selectedSquare;
  List<String> _validMoveSquares = [];

  String opponentName = "";

  bool _showGameOverOverlay = false;
  String _gameOverResult = "";
  String _gameOverMethod = "";
  bool? _localWin;

  final List<String> messages = [];

  static const Color primaryDark = Color(0xFF3E2723);
  static const Color primary = Color(0xFF6D4C41);
  static const Color bgTop = Color(0xFFFFF8F0);
  static const Color winGreen = Color(0xFF2E7D32);
  static const Color loseRed = Color(0xFFC62828);
  static const Color drawAmber = Color(0xFFB8860B);
  @override
  void initState() {
    super.initState();
    addMessage("Joined room: ${widget.userId}");
    widget.gameChannel.stream.listen(
      (msg) => handleGame(msg.toString()),
      onDone: _handleDisconnected,
      onError: (_) => _handleDisconnected(),
      cancelOnError: true,
    );
  }

  void handleGame(String msg) {
    addMessage(msg);
    final plain = msg.trim();
    print("Received: $plain");
    if (plain == "white" || plain == "black") {
      setState(() {
        color = plain;
        myTurn = color == "white";
      });
      return;
    }

    if (plain == "invalid_move") {
      setState(() => myTurn = true);
      addMessage("⚠️ Invalid move, try again");
      return;
    }

    if (RegExp(
      r'^(O-O-O|O-O|[NBRQK]?[a-h][1-8]x?[a-h][1-8][qrbnQRBN]?)$',
    ).hasMatch(plain)) {
      _applyOpponentMove(plain);
      return;
    }

    if (plain.startsWith("You won")) {
      addMessage("You won message received");
      addMessage("🏁 Game Over: $plain");
      _triggerLocalGameOver(won: true, method: "Resignation");
      return;
    }
    if (plain == "1-0" || plain == "0-1" || plain == "1/2-1/2") {
      addMessage("🏁 Game Over: $plain");
      _triggerGameOver(plain);
      return;
    }

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

    if (plain.startsWith("opponent: ")) {
      final name = plain.substring("opponent: ".length).trim();
      setState(() => opponentName = name);
      addMessage("Opponent name is $name");
      return;
    }

    addMessage("⚠️ Server: $plain");
  }

  Future<void> _resign() async {
    if (_showGameOverOverlay) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          "Resign game?",
          style: TextStyle(fontWeight: FontWeight.w600, color: primaryDark),
        ),
        content: const Text("This will end the game as a loss for you."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Resign", style: TextStyle(color: loseRed)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    _notifyLeftAndCloseSocket();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LobbyScreen()),
    );
  }

  bool _isQuitting = false;

  Future<void> _quitGame() async {
    if (_isQuitting) return;
    _isQuitting = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          "Quit game?",
          style: TextStyle(fontWeight: FontWeight.w600, color: primaryDark),
        ),
        content: const Text(
          "You'll leave the game right away and return to the lobby.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Quit", style: TextStyle(color: loseRed)),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      _isQuitting = false;
      return;
    }
    print("1111111111111111111111111111111111111");
    await _notifyLeftAndCloseSocket();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LobbyScreen()),
    );
  }

  Future<void> _notifyLeftAndCloseSocket() async {
    try {
      widget.gameChannel.sink.add("quit");
      print("Sent quit message to server");
    } catch (e) {
      print("Socket already closed, skipping quit message: $e");
    }

  
    widget.gameChannel.sink.close();
    try {} catch (_) {}
  }

  void _handleDisconnected() {
    print("WebSocket disconnected");
    if (!mounted || _showGameOverOverlay) return;
    addMessage("⚠️ Connection closed");
    _triggerLocalGameOver(won: false, method: "Opponent Disconnected");
  }

  void _triggerGameOver(String result) {
    print("Triggering game over: result=$result");
    boardController.resetBoard();
    setState(() {
      _gameOverResult = result;
      _localWin = null;
      _showGameOverOverlay = true;
      myTurn = false;
    });
  }

  void _triggerLocalGameOver({required bool won, required String method}) {
    print("Triggering local game over: won=$won, method=$method");
    if (!mounted) return;
    setState(() {
      _gameOverResult = "";
      _gameOverMethod = method;
      _localWin = won;
      _showGameOverOverlay = true;
      myTurn = true;
    });
  }

  void _dismissGameOver() {
    widget.gameChannel.sink.close();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LobbyScreen()),
    );
  }

  (String, String, String, painting.Color) _gameOverInfo() {
    final method = _gameOverMethod.isNotEmpty ? _gameOverMethod : "";

    if (_localWin != null) {
      if (_localWin!) {
        return (
          "🏆",
          "You Won!",
          method.isNotEmpty ? method : "Opponent left",
          winGreen
        );
      } else {
        return (
          "😔",
          "You Lost",
          method.isNotEmpty ? method : "You resigned",
          loseRed
        );
      }
    }

    final isWhite = color == "white";

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

  Future<void> _showPromotionDialog(String from, String to) async {
    final promoted = await PromotionDialog.show(context);

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

  void addMessage(String m) {
    setState(() => messages.insert(0, m));
  }

  @override
  void dispose() {
    widget.gameChannel.sink.close().catchError((_) {});
    super.dispose();
  }

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
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            tooltip: "Quit",
            onPressed: _quitGame,
          ),
        ],
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
              GameStatusChip(color: color),
              const SizedBox(height: 10),
              _buildOpponentChip(),
              const SizedBox(height: 10),
              TurnChip(myTurn: myTurn),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: bgTop,
                    borderRadius: BorderRadius.all(
                      Radius.circular(28),
                    ),
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
                                        child: MoveOverlay(
                                          boardSize: boardSize,
                                          selectedSquare: _selectedSquare,
                                          validSquares: _validMoveSquares,
                                          isBlack: color == 'black',
                                          onSquareTapped: _onSquareTapped,
                                        ),
                                      ),
                                    if (_showGameOverOverlay)
                                      Builder(builder: (context) {
                                        final (
                                          emoji,
                                          headline,
                                          subline,
                                          accentColor
                                        ) = _gameOverInfo();
                                        return GameOverOverlay(
                                          boardSize: boardSize,
                                          emoji: emoji,
                                          headline: headline,
                                          subline: subline,
                                          accentColor: accentColor,
                                          onPlayAgain: _dismissGameOver,
                                        );
                                      }),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _buildMyChip(),
              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOpponentChip() {
    final myColorIsWhite = color == 'white';
    return Center(
      child: PlayerChip(
        name: opponentName.isNotEmpty ? opponentName : 'Opponent',
        isWhite: !myColorIsWhite,
      ),
    );
  }

  Widget _buildMyChip() {
    final myColorIsWhite = color == 'white';
    return Center(
      child: PlayerChip(
        name: widget.username.isNotEmpty ? widget.username : 'You',
        isWhite: myColorIsWhite,
      ),
    );
  }
}
