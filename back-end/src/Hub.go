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

const quitMessage = "quit"

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
	mu      sync.Mutex
	queue   []*waitingPlayer
	Rooms   map[string]*ChessRoom
	Clients map[string]*ChessClient
}

func NewChessHub() *ChessHub {
	return &ChessHub{
		Rooms:   make(map[string]*ChessRoom),
		Clients: make(map[string]*ChessClient),
	}
}

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

// StartGame est le point d'entrée appelé par CHAQUE joueur (2x au total).
// sync.Once garantit qu'un seul appel exécute réellement la boucle de jeu ;
// le deuxième appel bloque jusqu'à la fin de la partie sans rien dupliquer.
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
		// b7al l gameOnce li kayblock l deuxième caller,
		// hna khasna n-simuler nafss l comportement: nstna l game ykml
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

// runGame contient toute la logique de la partie. N'est exécutée qu'UNE
// seule fois par room grâce à gameOnce dans StartGame.
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

	// --- Goroutine ديال قراءة لكل لاعب، كيصيفطو لنفس الـ channel ---
	msgCh := make(chan playerMsg, 4)
	for _, color := range []string{ColorWhite, ColorBlack} {
		go func(color string) {
			conn := players[color].ActiveConn
			for {
				mt, data, err := conn.ReadMessage()
				msgCh <- playerMsg{color: color, mt: mt, data: data, err: err}
				if err != nil {
					return // القراءة توقفت، خرج من الـ goroutine
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

		// أي قطع اتصال (من أي لاعب) كيتكتشف فوري
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

		// "quit" مقبولة فوري من أي لاعب، بلا ما تستنى الدور
		if moveStr == quitMessage {
			println("Player", players[msg.color].Name, "quit voluntarily.")
			winner := ColorBlack
			if msg.color == ColorBlack {
				winner = ColorWhite
			}
			disconnected = true
			return c.endGameByDisconnect(players, winner, msg.color, true)
		}

		// رسالة جاية من اللاعب لي ماشي دوره → تجاهلها (ماشي move صالح)
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
// findDisconnectedPlayer retourne la couleur du joueur déconnecté (ActiveConn == nil), s'il y en a un.
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

// endGameByDisconnect notifie le gagnant UNE SEULE FOIS (au lieu de 3x avant)
// et distingue quit volontaire vs déconnexion réseau.
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

func (c *ChessHub) JoinRoom(w http.ResponseWriter, r *http.Request) {
	clientID := mux.Vars(r)["client_id"]

	conn, _ := upgrader.Upgrade(w, r, nil)
	defer conn.Close()
	defer c.cleanupClient(clientID)

	c.UserJoined(clientID, conn)
	c.WaitForOthers(clientID)
	c.StartGame(clientID)
}

// cleanupClient marque le client comme déconnecté, et ne supprime la room
// que quand les DEUX joueurs sont partis, pour éviter que l'adversaire
// tombe sur une room supprimée pendant qu'il joue encore.
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