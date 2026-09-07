package src

import (
	"crypto/rand"
	"fmt"
	mrand "math/rand"
	"net/http"
	"regexp"
	"strings"
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

const quitMessage = "quit"

// characters used to generate room codes (no ambiguous chars like 0/O, 1/I)
const codeCharset = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

type waitingPlayer struct {
	userID string
	name   string
	result chan bool
}
type playerMsg struct {
	color string
	mt    int
	data  []byte
	err   error
}

type ChessHub struct {
	mu        sync.Mutex
	queue     []*waitingPlayer
	codeRooms map[string]*waitingPlayer // code -> host waiting for a friend to join
	Rooms     map[string]*ChessRoom
	Clients   map[string]*ChessClient
}

func NewChessHub() *ChessHub {
	return &ChessHub{
		Rooms:     make(map[string]*ChessRoom),
		Clients:   make(map[string]*ChessClient),
		codeRooms: make(map[string]*waitingPlayer),
	}
}

// ---------- Random matchmaking (unchanged) ----------

func (c *ChessHub) NewUser(userID, name string) chan bool {
	c.mu.Lock()
	defer c.mu.Unlock()

	result := make(chan bool, 1)
	c.queue = append(c.queue, &waitingPlayer{userID: userID, name: name, result: result})

	for len(c.queue) >= 2 {
		p1 := c.queue[0]
		p2 := c.queue[1]
		c.queue = c.queue[2:]
		c.createRoomForPair(p1, p2)

		// Notify both waiting players that they've been matched.
		p1.result <- true
		p2.result <- true
	}

	return result
}

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

// ---------- Room-code (private match) matchmaking ----------

// generateRoomCode makes a random 4-character code, retrying on collision.
// Caller must hold c.mu.
func (c *ChessHub) generateRoomCode() string {
	for {
		b := make([]byte, 4)
		rand.Read(b)
		var sb strings.Builder
		for _, v := range b {
			sb.WriteByte(codeCharset[int(v)%len(codeCharset)])
		}
		code := sb.String()
		if _, exists := c.codeRooms[code]; !exists {
			return code
		}
	}
}

// CreateRoomWithCode registers the caller as waiting host and returns a
// 4-character code to share with a friend, plus a channel that fires once
// the friend joins (true) or the host cancels (false).
func (c *ChessHub) CreateRoomWithCode(userID, name string) (string, chan bool) {
	c.mu.Lock()
	defer c.mu.Unlock()

	code := c.generateRoomCode()
	result := make(chan bool, 1)
	c.codeRooms[code] = &waitingPlayer{userID: userID, name: name, result: result}
	return code, result
}

// CancelRoomCode removes a pending code room if the host disconnects
// before a friend joins.
func (c *ChessHub) CancelRoomCode(code string) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if p, ok := c.codeRooms[code]; ok {
		delete(c.codeRooms, code)
		p.result <- false
	}
}

// JoinRoomWithCode is called by the friend. It looks up the code, pairs the
// two players into a room, and notifies the host via its result channel.
func (c *ChessHub) JoinRoomWithCode(code, userID, name string) error {
	code = strings.ToUpper(strings.TrimSpace(code))

	c.mu.Lock()
	host, ok := c.codeRooms[code]
	if !ok {
		c.mu.Unlock()
		return fmt.Errorf("room code %s not found", code)
	}
	delete(c.codeRooms, code)
	c.createRoomForPair(host, &waitingPlayer{userID: userID, name: name})
	c.mu.Unlock()

	host.result <- true
	return nil
}

// createRoomForPair does the actual room/client bookkeeping shared by both
// random matchmaking and code-based matchmaking. Caller must hold c.mu.
func (c *ChessHub) createRoomForPair(p1, p2 *waitingPlayer) string {
	roomID := uuid.NewString()
	room := &ChessRoom{ID: roomID, Clients: make(map[string]*ChessClient)}
	c.Rooms[roomID] = room

	p1Color, p2Color := ColorWhite, ColorBlack
	if mrand.Intn(2) == 0 {
		p1Color, p2Color = p2Color, p1Color
	}

	c.Clients[p1.userID] = &ChessClient{ID: p1.userID, Name: p1.name, RoomID: roomID, Color: p1Color}
	c.Clients[p2.userID] = &ChessClient{ID: p2.userID, Name: p2.name, RoomID: roomID, Color: p2Color}
	room.Clients[p1.userID] = c.Clients[p1.userID]
	room.Clients[p2.userID] = c.Clients[p2.userID]

	return roomID
}

// ---------- Shared game logic (unchanged below) ----------

func (c *ChessHub) UserJoined(userID string, conn *websocket.Conn) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	client, ok := c.Clients[userID]
	if !ok || client.ActiveConn != nil {
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
	c.mu.Lock()
	client := c.Clients[userID]
	if client == nil {
		c.mu.Unlock()
		return fmt.Errorf("client %s not found", userID)
	}
	roomID := client.RoomID
	room := c.Rooms[roomID]
	if room == nil {
		c.mu.Unlock()
		return fmt.Errorf("room %s not found", roomID)
	}

	if room.gameStarted {
		c.mu.Unlock()

		<-room.gameDone
		return room.gameErr
	}
	room.gameStarted = true
	room.gameDone = make(chan struct{})
	c.mu.Unlock()

	gameErr := c.runGame(roomID)

	c.mu.Lock()
	room.gameErr = gameErr
	close(room.gameDone)
	c.mu.Unlock()

	return gameErr
}

func (c *ChessHub) runGame(roomID string) error {
	c.mu.Lock()
	room, ok := c.Rooms[roomID]
	if !ok {
		c.mu.Unlock()
		return fmt.Errorf("room %s not found", roomID)
	}
	game := room.Game
	c.mu.Unlock()

	players, err := c.GetPlayers(roomID)
	if err != nil {
		return err
	}

	println("Starting game in room:", roomID)

	for _, color := range []string{ColorWhite, ColorBlack} {
		p := players[color]
		if p == nil || p.ActiveConn == nil {
			continue
		}
		opponentColor := ColorBlack
		if color == ColorBlack {
			opponentColor = ColorWhite
		}
		opponent := players[opponentColor]
		opponentName := "unknown"
		if opponent != nil {
			opponentName = opponent.Name
		}
		p.ActiveConn.WriteMessage(websocket.TextMessage, []byte(color))
		p.ActiveConn.WriteMessage(websocket.TextMessage, []byte("opponent: "+opponentName))
	}

	if disconnectedColor, ok := c.findDisconnectedPlayer(players); ok {
		winnerColor := ColorBlack
		if disconnectedColor == ColorBlack {
			winnerColor = ColorWhite
		}
		return c.endGameByDisconnect(players, winnerColor, disconnectedColor, false)
	}

	msgCh := make(chan playerMsg, 4)
	for _, color := range []string{ColorWhite, ColorBlack} {
		go func(color string) {
			conn := players[color].ActiveConn
			for {
				mt, data, err := conn.ReadMessage()
				msgCh <- playerMsg{color: color, mt: mt, data: data, err: err}
				if err != nil {
					return
				}
			}
		}(color)
	}

	var (
		movesOrder   = []string{ColorWhite, ColorBlack}
		index        = 0
		disconnected = false
	)

	for game.Outcome() == chess.NoOutcome {
		expectedColor := movesOrder[index%2]
		oppositeOfExpected := movesOrder[(index+1)%2]

		msg := <-msgCh

		if msg.err != nil || msg.mt == websocket.CloseMessage {
			disconnected = true
			winner := ColorBlack
			if msg.color == ColorBlack {
				winner = ColorWhite
			}
			return c.endGameByDisconnect(players, winner, msg.color, false)
		}

		moveStr := string(msg.data)
		println("Received message from player", players[msg.color].Name, ":", moveStr)

		if moveStr == quitMessage {
			println("Player", players[msg.color].Name, "quit voluntarily.")
			winner := ColorBlack
			if msg.color == ColorBlack {
				winner = ColorWhite
			}
			disconnected = true
			return c.endGameByDisconnect(players, winner, msg.color, true)
		}

		if msg.color != expectedColor {
			if players[msg.color].ActiveConn != nil {
				players[msg.color].ActiveConn.WriteMessage(
					websocket.TextMessage,
					[]byte("Not your turn"),
				)
			}
			continue
		}

		var finalMove *chess.Move
		uciRegex := regexp.MustCompile(`^([a-h][1-8])([a-h][1-8])([qrbn])?$`)
		if uciRegex.MatchString(moveStr) {
			move, err := chess.UCINotation{}.Decode(game.Position(), moveStr)
			if err != nil {
				players[expectedColor].ActiveConn.WriteMessage(websocket.TextMessage, []byte("UCI Move machi valid: "+err.Error()))
				continue
			}
			finalMove = move
			game.Move(finalMove)
		} else {
			if err := game.MoveStr(moveStr); err != nil {
				players[expectedColor].ActiveConn.WriteMessage(websocket.TextMessage, []byte("Notation machi valid: "+err.Error()))
				continue
			}
			moves := game.Moves()
			if len(moves) > 0 {
				finalMove = moves[len(moves)-1]
			}
		}

		if players[oppositeOfExpected].ActiveConn == nil {
			disconnected = true
			return c.endGameByDisconnect(players, expectedColor, oppositeOfExpected, false)
		}

		var msgToSend []byte
		if finalMove != nil {
			encoded := chess.UCINotation{}.Encode(game.Position(), finalMove)
			msgToSend = []byte(encoded)
		} else {
			msgToSend = msg.data
		}

		players[oppositeOfExpected].ActiveConn.WriteMessage(websocket.TextMessage, msgToSend)
		index++
	}

	if !disconnected {
		outcomeMsg := []byte(game.Outcome())
		methodMsg := []byte(game.Method().String())
		for _, p := range players {
			if p.ActiveConn != nil {
				p.ActiveConn.WriteMessage(websocket.TextMessage, outcomeMsg)
				p.ActiveConn.WriteMessage(websocket.TextMessage, methodMsg)
			}
		}
	}

	return nil
}
func (c *ChessHub) findDisconnectedPlayer(players map[string]*ChessClient) (string, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	for _, color := range []string{ColorWhite, ColorBlack} {
		if players[color] == nil || players[color].ActiveConn == nil {
			return color, true
		}
	}
	return "", false
}

func (c *ChessHub) endGameByDisconnect(players map[string]*ChessClient, winnerColor, loserColor string, voluntary bool) error {
	winner := players[winnerColor]
	loser := players[loserColor]

	if winner != nil && winner.ActiveConn != nil {
		if voluntary {
			winner.ActiveConn.WriteMessage(websocket.TextMessage, []byte("opponent_left"))
		} else {
			winner.ActiveConn.WriteMessage(websocket.TextMessage, []byte("opponent_disconnected"))
		}
		winner.ActiveConn.WriteMessage(websocket.TextMessage, []byte("You won"))
	}

	loserName := "unknown"
	if loser != nil {
		loserName = loser.Name
	}

	reason := "disconnected"
	if voluntary {
		reason = "quit voluntarily"
	}
	println("Player", loserName, reason, "- Ending game.")

	return fmt.Errorf("player %s (%s) %s", loserName, loserColor, reason)
}

func (c *ChessHub) GetPlayers(roomID string) (map[string]*ChessClient, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	room, ok := c.Rooms[roomID]
	if !ok {
		return nil, fmt.Errorf("room %s not found", roomID)
	}

	players := make(map[string]*ChessClient)
	for _, v := range room.Clients {
		players[v.Color] = v
	}
	return players, nil
}

// ---------- HTTP/WS handlers ----------

// PickRoom = existing random matchmaking entry point (unchanged).
func (c *ChessHub) PickRoom(w http.ResponseWriter, r *http.Request) {
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

// CreateCodeRoom is the host's entry point: connect, get back a 4-char code,
// then wait until a friend joins with that code (or disconnect to cancel).
// e.g. GET /ws/create-room?name=Alice
func (c *ChessHub) CreateCodeRoom(w http.ResponseWriter, r *http.Request) {
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

	code, result := c.CreateRoomWithCode(userID, name)
	fmt.Println("User", userID, "created room with code:", code)

	// Tell the host their room code so they can share it.
	conn.WriteMessage(websocket.TextMessage, []byte("code:"+code))

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
		fmt.Println("Host", userID, "disconnected before friend joined, canceling code", code)
		c.CancelRoomCode(code)
	}
}

// JoinCodeRoom is the friend's entry point: connect with a code, get paired
// with the host immediately.
// e.g. GET /ws/join-room/{code}?name=Bob
func (c *ChessHub) JoinCodeRoom(w http.ResponseWriter, r *http.Request) {
	code := mux.Vars(r)["code"]

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

	if err := c.JoinRoomWithCode(code, userID, name); err != nil {
		fmt.Println("Join with code failed:", err)
		conn.WriteMessage(websocket.TextMessage, []byte("error: "+err.Error()))
		return
	}

	fmt.Println("User", userID, "joined room with code:", code)
	conn.WriteMessage(websocket.TextMessage, []byte(userID))
}


func (c *ChessHub) JoinRoom(w http.ResponseWriter, r *http.Request) {
	clientID := mux.Vars(r)["client_id"]

	conn, _ := upgrader.Upgrade(w, r, nil)
	defer conn.Close()
	defer c.cleanupClient(clientID)

	c.UserJoined(clientID, conn)
	c.WaitForOthers(clientID)
	c.StartGame(clientID)
}

func (c *ChessHub) cleanupClient(clientID string) {
	c.mu.Lock()
	defer c.mu.Unlock()

	client, ok := c.Clients[clientID]
	if !ok {
		return
	}
	client.ActiveConn = nil
	roomID := client.RoomID
	delete(c.Clients, clientID)

	room, ok := c.Rooms[roomID]
	if !ok {
		return
	}
	delete(room.Clients, clientID)

	if len(room.Clients) == 0 {
		delete(c.Rooms, roomID)
	}
}