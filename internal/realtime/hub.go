package realtime

import "sync"

type Hub struct {
	mu          sync.RWMutex
	subscribers map[string]map[chan int64]struct{}
}

func NewHub() *Hub {
	return &Hub{subscribers: make(map[string]map[chan int64]struct{})}
}

func (h *Hub) Subscribe(userID string) (<-chan int64, func()) {
	channel := make(chan int64, 1)
	h.mu.Lock()
	if h.subscribers[userID] == nil {
		h.subscribers[userID] = make(map[chan int64]struct{})
	}
	h.subscribers[userID][channel] = struct{}{}
	h.mu.Unlock()

	var once sync.Once
	cancel := func() {
		once.Do(func() {
			h.mu.Lock()
			delete(h.subscribers[userID], channel)
			if len(h.subscribers[userID]) == 0 {
				delete(h.subscribers, userID)
			}
			close(channel)
			h.mu.Unlock()
		})
	}
	return channel, cancel
}

func (h *Hub) Publish(userID string, cursor int64) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	for channel := range h.subscribers[userID] {
		select {
		case channel <- cursor:
		default:
			select {
			case previous := <-channel:
				if previous > cursor {
					cursor = previous
				}
			default:
			}
			select {
			case channel <- cursor:
			default:
			}
		}
	}
}
