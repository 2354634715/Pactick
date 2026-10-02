package realtime

import (
	"testing"
	"time"
)

func TestHubPublishesOnlyToAccountSubscribers(t *testing.T) {
	hub := NewHub()
	first, cancelFirst := hub.Subscribe("user-one")
	defer cancelFirst()
	second, cancelSecond := hub.Subscribe("user-two")
	defer cancelSecond()

	hub.Publish("user-one", 42)
	select {
	case cursor := <-first:
		if cursor != 42 {
			t.Fatalf("cursor = %d, want 42", cursor)
		}
	case <-time.After(time.Second):
		t.Fatal("subscriber did not receive a cursor")
	}
	select {
	case cursor := <-second:
		t.Fatalf("other account received cursor %d", cursor)
	default:
	}
}

func TestHubCoalescesToNewestCursor(t *testing.T) {
	hub := NewHub()
	updates, cancel := hub.Subscribe("user")
	defer cancel()
	hub.Publish("user", 10)
	hub.Publish("user", 12)
	if cursor := <-updates; cursor != 12 {
		t.Fatalf("cursor = %d, want 12", cursor)
	}
}
