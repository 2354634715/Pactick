package httpapi

import (
	"context"
	"net/http"
	"strconv"
	"time"

	"github.com/gorilla/websocket"
)

func (s *Server) websocket(w http.ResponseWriter, r *http.Request) {
	after, err := parseIntQuery(r, "cursor", 0)
	if err != nil || after < 0 {
		writeError(w, r, http.StatusBadRequest, "invalid_cursor", "cursor must be a non-negative integer", nil)
		return
	}
	upgrader := websocket.Upgrader{
		HandshakeTimeout: 10 * time.Second,
		CheckOrigin: func(request *http.Request) bool {
			origin := request.Header.Get("Origin")
			return origin == "" || s.originAllowed(origin)
		},
	}
	connection, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	defer connection.Close()
	connection.SetReadLimit(4096)

	principal := principalFrom(r.Context())
	updates, unsubscribe := s.hub.Subscribe(principal.UserID)
	defer unsubscribe()

	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()
	go func() {
		defer cancel()
		connection.SetPongHandler(func(string) error {
			return connection.SetReadDeadline(time.Now().Add(70 * time.Second))
		})
		_ = connection.SetReadDeadline(time.Now().Add(70 * time.Second))
		for {
			if _, _, err := connection.ReadMessage(); err != nil {
				return
			}
		}
	}()

	current, err := s.sync.CurrentCursor(ctx, principal.UserID)
	if err != nil {
		return
	}
	if current > after {
		if err := writeSyncNotification(connection, current); err != nil {
			return
		}
	}
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case cursor, open := <-updates:
			if !open {
				return
			}
			if err := writeSyncNotification(connection, cursor); err != nil {
				return
			}
		case <-ticker.C:
			_ = connection.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := connection.WriteMessage(websocket.PingMessage, []byte(strconv.FormatInt(time.Now().Unix(), 10))); err != nil {
				return
			}
		}
	}
}

func writeSyncNotification(connection *websocket.Conn, cursor int64) error {
	_ = connection.SetWriteDeadline(time.Now().Add(10 * time.Second))
	return connection.WriteJSON(map[string]any{
		"type":   "sync_available",
		"cursor": cursor,
	})
}
