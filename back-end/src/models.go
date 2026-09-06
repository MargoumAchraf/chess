package src

import (
	"sync"

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
	joinedCount int
	gameOnce    sync.Once // ✅ à ajouter — empêche runGame de tourner deux fois
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