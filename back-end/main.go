package main

import (
	"log"
	"net/http"
	"os"

	"back-end/src"

	"github.com/gorilla/mux"
)

func main() {
	var (
		chessHub = src.NewChessHub()
		router   = mux.NewRouter()

		port = getenv("PORT", "8080")
	)

	router.HandleFunc("/rooms", chessHub.PickRoom)
	router.HandleFunc("/rooms/{client_id}", chessHub.JoinRoom)
	http.Handle("/", router)

	log.Printf("running chess server on port :%s...", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Println(err)
	}
}

func getenv(key, fallback string) string {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	return value
}