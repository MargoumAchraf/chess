# ♟️ Chess — Real-Time Multiplayer Chess App

A fullstack mobile chess application built with **Flutter** (frontend) and **Go** (backend). Two players are matched over WebSockets and play a fully rule-validated game of chess in real time, from matchmaking to checkmate.

## Overview

| Layer | Stack |
|---|---|
| Mobile app | Flutter / Dart, `flutter_chess_board`, `chess` (Dart), `web_socket_channel` |
| Backend | Go, Gorilla WebSocket, Gorilla Mux, `notnil/chess` (rules engine), Google UUID |
| Communication | WebSockets — one connection for matchmaking, one per active game |

The backend is the single source of truth for game state: it owns the `notnil/chess` game object, validates every move, decides turn order, and detects checkmate/stalemate/draw. The Flutter app is a thin client that renders the board and forwards the player's moves.

## Features

- **Main menu / Lobby screen** — enter a display name and look for a match.
- **Waiting room** — a player who wants to play is queued until an opponent is found; both are then placed in a private room.
- **Real-time multiplayer** — moves are exchanged instantly over a per-room WebSocket connection.
- **Full rule enforcement** — legal move validation, check/checkmate/stalemate detection, and draw conditions are all handled by the backend's chess engine (illegal moves are rejected and the player is asked to move again).
- **White always moves first** — turn order is fixed server-side (`white`, `black`) regardless of which client connected first; colors are assigned randomly per match.
- **Turn notifications** — each client is told whose turn it is and receives the opponent's move as soon as it's played.
- **Game-over handling** — when the game reaches a terminal state, both players receive the outcome (win/loss/draw) and the method (checkmate, stalemate, resignation, disconnect, etc.).
- **Disconnect handling** — if a player disconnects mid-game, the remaining player is automatically declared the winner.
- **Resign & restart** — players can resign a game in progress or start a new matchmaking search after a game ends.
- **Pawn promotion** — a promotion dialog lets the player choose which piece to promote to.
- **Move highlighting** — the last move and legal destination squares are highlighted on the board.

## Project Structure

```
chess/
├── back-end/               # Go WebSocket server
│   ├── main.go             # HTTP/WS routes: /rooms and /rooms/{client_id}
│   ├── src/
│   │   ├── Hub.go          # Matchmaking queue, room lifecycle, game loop
│   │   └── models.go       # ChessRoom / ChessClient types
│   ├── go.mod / go.sum
│   └── Dockerfile
│
└── mobile/                 # Flutter application
    ├── lib/
    │   ├── main.dart
    │   ├── screen/
    │   │   ├── LobbyScreen.dart    # Main menu + waiting room
    │   │   └── handleGame.dart     # Game board screen & WS handling
    │   └── widgets/                # Board overlays, chips, dialogs, buttons
    ├── assets/pieces/               # SVG piece assets
    └── pubspec.yaml
```

## Backend — API / WebSocket Routes

The server exposes two WebSocket endpoints (matching the required backend routes):

| Route | Purpose |
|---|---|
| `GET /rooms?name={playerName}` | Join the matchmaking queue. The socket stays open until an opponent is found; the server then returns a `client_id` and closes this connection. Disconnecting while waiting removes the player from the queue. |
| `GET /rooms/{client_id}` | Open the per-game socket using the `client_id` from matchmaking. Once both players in the room have connected, the game starts: color assignment is sent first, followed by the opponent's name, then moves are relayed turn by turn. |

**Move format:** moves are sent as plain text, in either **UCI notation** or **Standard Algebraic Notation (SAN)**. Both are accepted and validated by the backend's `notnil/chess` engine — invalid or out-of-turn moves are rejected with an error message and the sender is prompted to try again.

| Move type | UCI example | SAN example | Notes |
|---|---|---|---|
| Normal move | `e2e4` | `e4` | `<from><to>` in UCI |
| Piece move | `g1f3` | `Nf3` | Knight from g1 to f3 |
| Capture | `e4d5` | `exd5` | UCI doesn't mark captures explicitly; SAN uses `x` |
| Long-range move | `e1e7` | `Re7` (or `Qe7`, etc.) | Any legal move along a rank/file/diagonal, e.g. rook/queen/bishop |
| Kingside castling | `e1g1` (white) / `e8g8` (black) | `O-O` | King's two-square move is interpreted as castling |
| Queenside castling | `e1c1` (white) / `e8c8` (black) | `O-O-O` | |
| En passant | `e5d6` | `exd6` | Automatically recognized from the resulting board position, no special flag needed |
| Pawn promotion | `g7g8q` | `g8=Q` | Trailing letter/suffix selects the piece: `q` (queen), `r` (rook), `b` (bishop), `n` (knight) |
| Promotion with capture | `f7g8q` | `fxg8=Q` | |
| Check / checkmate suffix | — | `Qh5+` / `Qh5#` | Optional in SAN; ignored/informational, doesn't affect move resolution |

**SAN piece letters:** 
```bash
    `N` = Knight, 
    `B` = Bishop,
    `R` = Rook,
    `Q` = Queen,
    `K` = King (pawns have no letter, e.g. `e4` not `Pe4`).
```
**End-of-game messages:** on a natural outcome, both clients receive the game outcome (e.g. `1-0`, `0-1`, `1/2-1/2`) and the method (e.g. checkmate, stalemate). On a disconnect, the remaining player receives an explicit win notification instead.

### Running the backend

```bash
cd back-end
go mod download
go run main.go
# Server listens on :8080 by default (override with the PORT env var)
```

Or with Docker:

```bash
cd back-end
docker build -t chess-backend .
docker run -p 8080:8080 chess-backend
```

## Mobile App

### Running the app

```bash
cd mobile
flutter pub get
flutter run
```

Update the WebSocket host used by the app (in `lib/screen/LobbyScreen.dart` / `lib/screen/handleGame.dart`) to point at your running backend (e.g. `ws://<your-ip>:8080` or an ngrok tunnel if testing on a physical device).

### Screens

- **Lobby / Main menu** (`LobbyScreen.dart`) — name entry, "Find match" action, and the waiting-room state while queued.
- **Game board** (`handleGame.dart`) — the chess board, player/opponent info, turn indicator, move history, resign/restart controls, and the game-over overlay.

## How a Match Works

1. Player opens the app and enters the lobby → connects to `/rooms` → is placed in the matchmaking queue.
2. Once two players are queued, the server creates a room, randomly assigns **white**/**black**, and returns a `client_id` to each.
3. Each client connects to `/rooms/{client_id}`. When both have joined, the server starts a fresh game and tells each client its color and its opponent's name.
4. The server enforces turn order (white moves first) and validates every move against the chess engine before relaying it to the opponent.
5. The loop continues until checkmate, stalemate, a draw, a resignation, or a disconnect — at which point both connected players are notified of the result.

## Tech Notes

- Game rule validation (legal moves, check/checkmate/stalemate/draw detection) is delegated entirely to the [`notnil/chess`](https://github.com/notnil/chess) Go package on the backend, so the client cannot bypass the rules.
- Each match lives in its own `ChessRoom`/goroutine pair — the hub only needs a mutex around shared matchmaking/room state, not per-move locking.

## Possible Improvements (Bonus Ideas)

- Single-player mode against a bot/engine (e.g. wiring in Stockfish or a simple minimax AI).
- Public game list / direct player invites, in addition to random matchmaking.
- Persistent accounts and match history.