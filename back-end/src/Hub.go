package src

import (
	"fmt"
	"math/rand"
	"net/http"
	"regexp"
	"sync"

	"github.com/google/uuid"
	"github.com/gorilla/mux"
	"github.com/gorilla/websocket"
	"github.com/notnil/chess"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

// waitingPlayer is a client sitting in the matchmaking queue.
type waitingPlayer struct {
	userID string
	name   string
	result chan bool // true = matched into a room, false = canceled
}

// ChessHub owns matchmaking, rooms, and the per-game state machine.
// All state is protected by mu instead of channel workers.
type ChessHub struct {
	mu      sync.Mutex
	queue   []*waitingPlayer
	Rooms   map[string]*ChessRoom   // key is RoomID
	Clients map[string]*ChessClient // key is UserID
}

func NewChessHub() *ChessHub {
	return &ChessHub{
		Rooms:   make(map[string]*ChessRoom),
		Clients: make(map[string]*ChessClient),
	}
}

// NewUser enqueues userID for matchmaking and returns a channel that
// receives true once matched into a room, or false if canceled before
// being matched.
func (c *ChessHub) NewUser(userID, name string) chan bool {
	c.mu.Lock()
	defer c.mu.Unlock()

	result := make(chan bool, 1)
	c.queue = append(c.queue, &waitingPlayer{userID: userID, name: name, result: result})

	for len(c.queue) >= 2 {
		p1 := c.queue[0]
		p2 := c.queue[1]
		c.queue = c.queue[2:]

		roomID := uuid.NewString()
		room := &ChessRoom{ID: roomID, Clients: make(map[string]*ChessClient)}
		c.Rooms[roomID] = room

		p1Color, p2Color := ColorWhite, ColorBlack
		if rand.Intn(2) == 0 {
			p1Color, p2Color = p2Color, p1Color
		}

		c.Clients[p1.userID] = &ChessClient{ID: p1.userID, Name: p1.name, RoomID: roomID, Color: p1Color}
		c.Clients[p2.userID] = &ChessClient{ID: p2.userID, Name: p2.name, RoomID: roomID, Color: p2Color}
		room.Clients[p1.userID] = c.Clients[p1.userID]
		room.Clients[p2.userID] = c.Clients[p2.userID]

		p1.result <- true
		p2.result <- true
	}

	return result
}

// CancelWaitingUser removes userID from the matchmaking queue if it's still
// waiting (called when a waiting client disconnects, e.g. hit "Restart").
// Safe to call even if the user has already been matched — it's a no-op
// in that case since the user is no longer in the queue.
func (c *ChessHub) CancelWaitingUser(userID string) {
	c.mu.Lock()
	defer c.mu.Unlock()

	for i, p := range c.queue {
		if p.userID == userID {
			c.queue = append(c.queue[:i], c.queue[i+1:]...)
			p.result <- false
			return
		}
	}
}

// UserJoined attaches conn to userID's client. Once both clients in the
// room have joined, it starts the chess game and notifies both.
func (c *ChessHub) UserJoined(userID string, conn *websocket.Conn) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	client, ok := c.Clients[userID]
	if !ok || client.ActiveConn != nil {
		// TODO
		// return err
		return nil
	}

	client.ActiveConn = conn
	client.ChanNotifyWhenReady = make(chan bool, 1)

	room := c.Rooms[client.RoomID]
	room.joinedCount++
	if room.joinedCount == 2 {
		room.Game = chess.NewGame(chess.UseNotation(chess.LongAlgebraicNotation{}))
		for _, cl := range room.Clients {
			cl.ChanNotifyWhenReady <- true
		}
	}
	return nil
}

func (c *ChessHub) WaitForOthers(userID string) {
	if client, ok := c.Clients[userID]; ok {
		<-client.ChanNotifyWhenReady
	}
}

func (c *ChessHub) StartGame(userID string) error {
	var (
		client     = c.Clients[userID]
		roomID     = client.RoomID
		movesOrder = []string{ColorWhite, ColorBlack}
		game       = c.Rooms[roomID].Game
		index      = 0
	)
	println("Starting game for user:", userID, "in room:", roomID, "with color:", client.Color)
	players, err := c.GetPlayers(roomID)
	if err != nil {
		return err
	}

	opponent := players[ColorWhite]
	if client.Color == ColorWhite {
		opponent = players[ColorBlack]
	}

	client.ActiveConn.WriteMessage(websocket.TextMessage, []byte(client.Color))
	client.ActiveConn.WriteMessage(websocket.TextMessage, []byte("opponent: "+opponent.Name))

	// tracks whether the game ended because of a disconnect rather than a
	// natural chess outcome (checkmate/stalemate/draw/etc.)
	disconnected := false

	for game.Outcome() == chess.NoOutcome {
		var (
			color         = movesOrder[index%2]
			oppositeColor = movesOrder[(index+1)%2]
		)

		mt, message, err := players[color].ActiveConn.ReadMessage()
		if err != nil || mt == websocket.CloseMessage {
			// the player whose turn it was disconnected (or the read failed);
			// notify the other player that they won by disconnect, if they're
			// still connected.
			disconnected = true
			winner := players[oppositeColor]
			if winner.ActiveConn != nil {
				winner.ActiveConn.WriteMessage(websocket.TextMessage, []byte("You won"))
				// if color_player == ColorWhite {
				// 	winner.ActiveConn.WriteMessage(websocket.TextMessage, []byte("1-0"))
				// } else {
				// 	winner.ActiveConn.WriteMessage(websocket.TextMessage, []byte("0-1"))
				// }
			}
			break
		}

		// 2. TASHI7: Rejje3 l-message string bach tqdar tkhaddmo f l-Regex o l-Chess package
		moveStr := string(message)

		// Had l-variable ghadi n-7etou fih l-move object s7i7 melli n-decodawh
		var finalMove *chess.Move
		uciRegex := regexp.MustCompile(`^([a-h][1-8])([a-h][1-8])([qrbn])?$`)
		// 3. Checki wach UCI Format (bhal g7g8q, e2e4)
		if uciRegex.MatchString(moveStr) {
			move, err := chess.UCINotation{}.Decode(game.Position(), moveStr)
			if err != nil {
				players[color].ActiveConn.WriteMessage(websocket.TextMessage, []byte("UCI Move machi valid: "+err.Error()))
				continue
			}

			finalMove = move
			game.Move(finalMove)

		} else {
			// 4. Ila machi UCI, n-jarbo Algebraic (bhal e4, Nf3, e8=Q)
			// Hna 7it MoveStr f l-package kat-la3b direct, khassna n-jbdou l-move object men l-game history
			if err := game.MoveStr(moveStr); err != nil {
				players[color].ActiveConn.WriteMessage(websocket.TextMessage, []byte("Notation machi valid: "+err.Error()))
				continue // Kay-rj3 l-nefs l-player y-la3b
			}

			// N-jbdou l-move li yllah t-la3b bach n-sftoh nishan l-player l-akhar standard
			moves := game.Moves()
			if len(moves) > 0 {
				finalMove = moves[len(moves)-1]
			}
		}

		// Checki wach l-player l-akhar baqi connected
		if players[oppositeColor].ActiveConn == nil {
			println("Player", players[oppositeColor].Name, "disconnected. Ending game.")
			disconnected = true
			// the mover just made a valid move and the opponent is gone —
			// the mover wins by opponent disconnect.
			winner := players[color]
			if winner.ActiveConn != nil {
				winner.ActiveConn.WriteMessage(websocket.TextMessage, []byte("opponent_disconnected"))
				winner.ActiveConn.WriteMessage(websocket.TextMessage, []byte("win"))
			}
			break
		}

		// 5. TASHI7: Men l-a7san tsfet l-move l-m9add (UCI notation masalan) l-player l-akhar
		// bach hta l-front-end dialo yfham achno t-la3b nishan (yqdar ykoun string dial finalMove)
		var msgToSend []byte
		if finalMove != nil {
			// uci.Encode kat-rj3 dima standard format bhal "g7g8q" aw "e2e4"
			encoded := chess.UCINotation{}.Encode(game.Position(), finalMove)
			msgToSend = []byte(encoded)
		} else {
			msgToSend = message
		}

		players[oppositeColor].ActiveConn.WriteMessage(websocket.TextMessage, msgToSend)

		// Daba l-move daz s7i7, n-zdou index bach y-wlli l-nouba dial l-player l-akhar
		index++
	}

	// Only report the natural chess outcome if the game didn't end because
	// of a disconnect (disconnect messages were already sent above).
	if !disconnected {
		client.ActiveConn.WriteMessage(websocket.TextMessage, []byte(game.Outcome()))
		client.ActiveConn.WriteMessage(websocket.TextMessage, []byte(game.Method().String()))
	}

	return nil
}

func (c *ChessHub) GetPlayers(roomID string) (map[string]*ChessClient, error) {
	players := make(map[string]*ChessClient)
	for _, v := range c.Rooms[roomID].Clients {
		players[v.Color] = v
	}
	return players, nil
}

// PickRoom handles the matchmaking websocket: a client connects, is placed
// in the queue, and either receives its assigned userID once matched or is
// removed from the queue if it disconnects first.
func (c *ChessHub) PickRoom(w http.ResponseWriter, r *http.Request) {
	fmt.Println("New user connected:")
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	defer conn.Close()

	userID := uuid.NewString()
	name := r.URL.Query().Get("name")
	if name == "" {
		name = "Guest-" + userID[:6]
	}

	fmt.Println("New user connected:", userID, "with name:", name)

	result := c.NewUser(userID, name)

	// Watch for the client going away (closed socket, e.g. they hit
	// "Restart") while we're still waiting to be matched.
	disconnected := make(chan struct{})
	go func() {
		defer close(disconnected)
		for {
			if _, _, err := conn.ReadMessage(); err != nil {
				return
			}
		}
	}()

	select {
	case ok := <-result:
		if ok {
			conn.WriteMessage(websocket.TextMessage, []byte(userID))
		}
	case <-disconnected:
		fmt.Println("User", userID, "disconnected before being matched, canceling.")
		c.CancelWaitingUser(userID)
	}
}

// JoinRoom handles the per-match websocket once a client has an assigned
// userID: it waits for the opponent, then runs the game loop.
func (c *ChessHub) JoinRoom(w http.ResponseWriter, r *http.Request) {
	clientID := mux.Vars(r)["client_id"]

	conn, _ := upgrader.Upgrade(w, r, nil)
	defer conn.Close()
	defer func() {
		client := c.Clients[clientID]
		client.ActiveConn = nil
		delete(c.Clients, clientID)
		delete(c.Rooms, client.RoomID)
	}()

	c.UserJoined(clientID, conn)
	c.WaitForOthers(clientID)
	c.StartGame(clientID)
}