package main

import (
	"log"
	"net/http"

	"back-end/src"

	"github.com/gorilla/mux"
)

func main() {
	var (
		chessHub = src.NewChessHub()
		router   = mux.NewRouter()

		port = "8080"
	)

	router.HandleFunc("/rooms", chessHub.PickRoom)
	router.HandleFunc("/rooms/{client_id}", chessHub.JoinRoom)
	http.Handle("/", router)

	log.Printf("running chess server on port :%s...", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Println(err)
	}
}