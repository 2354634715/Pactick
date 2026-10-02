package sync

import (
	"context"
	"errors"
	"fmt"
)

const (
	MaxPushOperations = 200
	MaxPullLimit      = 1000
)

type CursorNotifier interface {
	Publish(userID string, cursor int64)
}

type Service struct {
	store    *PostgresStore
	notifier CursorNotifier
}

func NewService(store *PostgresStore, notifier CursorNotifier) *Service {
	return &Service{store: store, notifier: notifier}
}

func (s *Service) Push(ctx context.Context, userID, deviceID string, operations []Operation) (PushResponse, error) {
	if len(operations) == 0 {
		return PushResponse{}, &APIError{Code: "empty_batch", Message: "operations must not be empty"}
	}
	if len(operations) > MaxPushOperations {
		return PushResponse{}, &APIError{
			Code:    "batch_too_large",
			Message: fmt.Sprintf("a batch may contain at most %d operations", MaxPushOperations),
		}
	}
	seen := make(map[string]struct{}, len(operations))
	results := make([]OperationResult, 0, len(operations))
	for _, operation := range operations {
		if _, duplicate := seen[operation.OperationID]; duplicate {
			results = append(results, rejected(operation.OperationID, "duplicate_operation_id", "operation_id is repeated in this batch", nil))
			continue
		}
		seen[operation.OperationID] = struct{}{}
		result, err := s.store.Apply(ctx, userID, deviceID, operation)
		if err != nil {
			if errors.Is(err, ErrDeviceUnauthorized) {
				return PushResponse{}, err
			}
			return PushResponse{}, fmt.Errorf("apply operation %s: %w", operation.OperationID, err)
		}
		results = append(results, result)
		if result.Snapshot != nil && result.Status == "applied" && result.Snapshot.Cursor > 0 && s.notifier != nil {
			s.notifier.Publish(userID, result.Snapshot.Cursor)
		}
	}
	cursor, err := s.store.CurrentCursor(ctx, userID)
	if err != nil {
		return PushResponse{}, err
	}
	return PushResponse{Results: results, CurrentCursor: cursor}, nil
}

func (s *Service) Pull(ctx context.Context, userID string, after int64, limit int) (PullResponse, error) {
	if after < 0 {
		return PullResponse{}, &APIError{Code: "invalid_cursor", Message: "cursor must not be negative"}
	}
	if limit <= 0 {
		limit = 500
	}
	if limit > MaxPullLimit {
		limit = MaxPullLimit
	}
	return s.store.Pull(ctx, userID, after, limit)
}

func (s *Service) CurrentCursor(ctx context.Context, userID string) (int64, error) {
	return s.store.CurrentCursor(ctx, userID)
}
