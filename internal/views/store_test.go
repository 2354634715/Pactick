package views

import (
	"testing"
	"time"
)

func TestLocalDayBoundsHandlesDST(t *testing.T) {
	_, springStart, springEnd, err := localDayBounds("2026-03-08", "America/New_York")
	if err != nil {
		t.Fatalf("localDayBounds() spring error = %v", err)
	}
	if duration := springEnd.Sub(springStart); duration != 23*time.Hour {
		t.Fatalf("spring day duration = %s, want 23h", duration)
	}
	_, fallStart, fallEnd, err := localDayBounds("2026-11-01", "America/New_York")
	if err != nil {
		t.Fatalf("localDayBounds() fall error = %v", err)
	}
	if duration := fallEnd.Sub(fallStart); duration != 25*time.Hour {
		t.Fatalf("fall day duration = %s, want 25h", duration)
	}
}

func TestBlockDuration(t *testing.T) {
	body := map[string]any{
		"starts_at": "2026-08-31T02:00:00Z",
		"ends_at":   "2026-08-31T03:30:00Z",
	}
	if duration := blockDuration(body); duration != 5400 {
		t.Fatalf("blockDuration() = %d, want 5400", duration)
	}
}
