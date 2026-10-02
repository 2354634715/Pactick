package main

import (
	"context"
	"io"
	"net/http"
	"os"
	"time"
)

func main() {
	endpoint := os.Getenv("HEALTHCHECK_URL")
	if endpoint == "" {
		endpoint = "http://127.0.0.1:8080/readyz"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		os.Exit(1)
	}
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		os.Exit(1)
	}
	defer response.Body.Close()
	_, _ = io.Copy(io.Discard, io.LimitReader(response.Body, 4096))
	if response.StatusCode != http.StatusOK {
		os.Exit(1)
	}
}
