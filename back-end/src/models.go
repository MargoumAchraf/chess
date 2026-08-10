package src

import (
	"github.com/gorilla/websocket"
	"github.com/notnil/chess"
)

const (
	ColorWhite = "white"
	ColorBlack = "black"
)

// ChessRoom represents a single match between two clients.
type ChessRoom struct {
	ID          string
	Clients     map[string]*ChessClient
	Game        *chess.Game
	joinedCount int // how many of the two clients have opened their game socket
}

// ChessClient represents a connected (or about-to-connect) player.
type ChessClient struct {
	ID                  string
	Name                string
	Color               string
	RoomID              string
	ActiveConn          *websocket.Conn
	ChanNotifyWhenReady chan bool
}