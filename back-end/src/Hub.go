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

type waitingPlayer struct {
	userID string
	name   string
	result chan bool
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

	disconnected := false

	for game.Outcome() == chess.NoOutcome {
		var (
			color         = movesOrder[index%2]
			oppositeColor = movesOrder[(index+1)%2]
		)

		mt, message, err := players[color].ActiveConn.ReadMessage()
		if err != nil || mt == websocket.CloseMessage {
			disconnected = true
			winner := players[oppositeColor]
			if winner.ActiveConn != nil {
				winner.ActiveConn.WriteMessage(websocket.TextMessage, []byte("You won"))
			}
			break
		}

		moveStr := string(message)

		var finalMove *chess.Move
		uciRegex := regexp.MustCompile(`^([a-h][1-8])([a-h][1-8])([qrbn])?$`)
		if uciRegex.MatchString(moveStr) {
			move, err := chess.UCINotation{}.Decode(game.Position(), moveStr)
			if err != nil {
				players[color].ActiveConn.WriteMessage(websocket.TextMessage, []byte("UCI Move machi valid: "+err.Error()))
				continue
			}

			finalMove = move
			game.Move(finalMove)

		} else {
			if err := game.MoveStr(moveStr); err != nil {
				players[color].ActiveConn.WriteMessage(websocket.TextMessage, []byte("Notation machi valid: "+err.Error()))
				continue
			}

			moves := game.Moves()
			if len(moves) > 0 {
				finalMove = moves[len(moves)-1]
			}
		}

		if players[oppositeColor].ActiveConn == nil {
			println("Player", players[oppositeColor].Name, "disconnected. Ending game.")
			disconnected = true
			winner := players[color]
			if winner.ActiveConn != nil {
				winner.ActiveConn.WriteMessage(websocket.TextMessage, []byte("opponent_disconnected"))
				winner.ActiveConn.WriteMessage(websocket.TextMessage, []byte("win"))
			}
			break
		}

		var msgToSend []byte
		if finalMove != nil {
			encoded := chess.UCINotation{}.Encode(game.Position(), finalMove)
			msgToSend = []byte(encoded)
		} else {
			msgToSend = message
		}

		players[oppositeColor].ActiveConn.WriteMessage(websocket.TextMessage, msgToSend)

		index++
	}

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