package views

import (
	"context"
	"encoding/json"
	"errors"
	"sort"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

var todayNamespace = uuid.MustParse("02cb27af-45c8-4ea8-9425-ec96e7d2e0ac")

type Store struct {
	pool *pgxpool.Pool
}

func NewStore(pool *pgxpool.Pool) *Store {
	return &Store{pool: pool}
}

func (s *Store) Today(ctx context.Context, userID, date, timeZone string) (TodayView, error) {
	location, start, end, err := localDayBounds(date, timeZone)
	if err != nil {
		return TodayView{}, err
	}
	_ = location

	entries, err := s.queryRecords(ctx, `
		SELECT id, version, body, updated_at
		FROM day_plan_entries
		WHERE user_id = $1 AND deleted_at IS NULL AND body ->> 'local_date' = $2
		ORDER BY body ->> 'rank', id`, userID, date)
	if err != nil {
		return TodayView{}, err
	}
	blocks, err := s.queryRecords(ctx, `
		SELECT id, version, body, updated_at
		FROM plan_blocks
		WHERE user_id = $1 AND deleted_at IS NULL
		  AND body ->> 'status' <> 'cancelled'
		  AND (body ->> 'starts_at')::timestamptz < $3
		  AND (body ->> 'ends_at')::timestamptz > $2
		ORDER BY body ->> 'starts_at', id`, userID, start, end)
	if err != nil {
		return TodayView{}, err
	}

	entryByBlock := make(map[string]struct{}, len(entries))
	taskIDs := make(map[string]struct{})
	blockByID := make(map[string]Record, len(blocks))
	for _, block := range blocks {
		blockByID[block.ID] = block
		collectStringID(block.Body, "task_id", taskIDs)
	}
	for _, entry := range entries {
		collectStringID(entry.Body, "task_id", taskIDs)
		if blockID, ok := bodyString(entry.Body, "plan_block_id"); ok {
			entryByBlock[blockID] = struct{}{}
		}
	}
	tasks, err := s.tasksByID(ctx, userID, taskIDs)
	if err != nil {
		return TodayView{}, err
	}
	actualByTask, err := s.actualByTask(ctx, userID, start, end)
	if err != nil {
		return TodayView{}, err
	}

	items := make([]TodayItem, 0, len(entries)+len(blocks))
	for index := range entries {
		entry := entries[index]
		item := TodayItem{ID: entry.ID, DayEntry: &entry, Origin: bodyStringOr(entry.Body, "source", "manual")}
		if blockID, ok := bodyString(entry.Body, "plan_block_id"); ok {
			if block, exists := blockByID[blockID]; exists {
				blockCopy := block
				item.PlanBlock = &blockCopy
				item.PlannedDurationSeconds = blockDuration(block.Body)
			}
		}
		if taskID := linkedTaskID(item.DayEntry, item.PlanBlock); taskID != "" {
			if task, exists := tasks[taskID]; exists {
				taskCopy := task
				item.Task = &taskCopy
			}
			item.ActualDurationSeconds = actualByTask[taskID]
		}
		items = append(items, item)
	}
	for index := range blocks {
		block := blocks[index]
		if _, materialized := entryByBlock[block.ID]; materialized {
			continue
		}
		derivedID := uuid.NewSHA1(todayNamespace, []byte(userID+":"+date+":"+block.ID)).String()
		item := TodayItem{
			ID:                     derivedID,
			Derived:                true,
			Origin:                 "planned",
			PlanBlock:              &block,
			PlannedDurationSeconds: blockDuration(block.Body),
		}
		if taskID, ok := bodyString(block.Body, "task_id"); ok {
			if task, exists := tasks[taskID]; exists {
				taskCopy := task
				item.Task = &taskCopy
			}
			item.ActualDurationSeconds = actualByTask[taskID]
		}
		items = append(items, item)
	}
	return TodayView{Date: date, TimeZone: timeZone, Items: items}, nil
}

func (s *Store) Calendar(ctx context.Context, userID string, startsAt, endsAt time.Time) (CalendarView, error) {
	if !endsAt.After(startsAt) {
		return CalendarView{}, errors.New("ends_at must be after starts_at")
	}
	if endsAt.Sub(startsAt) > 93*24*time.Hour {
		return CalendarView{}, errors.New("calendar range cannot exceed 93 days")
	}
	blocks, err := s.queryRecords(ctx, `
		SELECT id, version, body, updated_at FROM plan_blocks
		WHERE user_id = $1 AND deleted_at IS NULL
		  AND (body ->> 'starts_at')::timestamptz < $3
		  AND (body ->> 'ends_at')::timestamptz > $2
		ORDER BY body ->> 'starts_at', id`, userID, startsAt.UTC(), endsAt.UTC())
	if err != nil {
		return CalendarView{}, err
	}
	sessions, err := s.queryRecords(ctx, `
		SELECT id, version, body, updated_at FROM focus_sessions
		WHERE user_id = $1 AND deleted_at IS NULL
		  AND (body ->> 'started_at')::timestamptz < $3
		  AND COALESCE((body ->> 'ended_at')::timestamptz, now()) > $2
		ORDER BY body ->> 'started_at', id`, userID, startsAt.UTC(), endsAt.UTC())
	if err != nil {
		return CalendarView{}, err
	}
	taskIDs := map[string]struct{}{}
	for _, record := range blocks {
		collectStringID(record.Body, "task_id", taskIDs)
	}
	for _, record := range sessions {
		collectStringID(record.Body, "task_id", taskIDs)
	}
	tasksByID, err := s.tasksByID(ctx, userID, taskIDs)
	if err != nil {
		return CalendarView{}, err
	}
	tasks := make([]Record, 0, len(tasksByID))
	for _, task := range tasksByID {
		tasks = append(tasks, task)
	}
	sort.Slice(tasks, func(i, j int) bool { return tasks[i].ID < tasks[j].ID })
	return CalendarView{
		StartsAt:      startsAt.UTC(),
		EndsAt:        endsAt.UTC(),
		PlanBlocks:    blocks,
		FocusSessions: sessions,
		Tasks:         tasks,
	}, nil
}

func (s *Store) Summary(ctx context.Context, userID, startsOn, endsOn, timeZone string) (Summary, error) {
	location, start, _, err := localDayBounds(startsOn, timeZone)
	if err != nil {
		return Summary{}, err
	}
	_, _, end, err := localDayBounds(endsOn, timeZone)
	if err != nil {
		return Summary{}, err
	}
	if end.Before(start) || end.Equal(start) {
		return Summary{}, errors.New("ends_on must not be before starts_on")
	}
	if end.Sub(start) > 367*24*time.Hour {
		return Summary{}, errors.New("statistics range cannot exceed 366 days")
	}

	days := make(map[string]*DailySummary)
	for current := start.In(location); current.Before(end.In(location)); current = current.AddDate(0, 0, 1) {
		date := current.Format("2006-01-02")
		days[date] = &DailySummary{Date: date}
	}
	if err := s.loadPlannedSummary(ctx, userID, start, end, timeZone, days); err != nil {
		return Summary{}, err
	}
	if err := s.loadActualSummary(ctx, userID, start, end, timeZone, days); err != nil {
		return Summary{}, err
	}
	if err := s.loadCompletedSummary(ctx, userID, start, end, timeZone, days); err != nil {
		return Summary{}, err
	}

	result := Summary{StartsOn: startsOn, EndsOn: endsOn, TimeZone: timeZone, Days: make([]DailySummary, 0, len(days))}
	for _, day := range days {
		result.Days = append(result.Days, *day)
		result.PlannedDurationSeconds += day.PlannedDurationSeconds
		result.ActualDurationSeconds += day.ActualDurationSeconds
		result.CompletedTasks += day.CompletedTasks
	}
	sort.Slice(result.Days, func(i, j int) bool { return result.Days[i].Date < result.Days[j].Date })
	return result, nil
}

func (s *Store) queryRecords(ctx context.Context, query string, args ...any) ([]Record, error) {
	rows, err := s.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	records := make([]Record, 0)
	for rows.Next() {
		var record Record
		var raw []byte
		if err := rows.Scan(&record.ID, &record.Version, &raw, &record.UpdatedAt); err != nil {
			return nil, err
		}
		if err := json.Unmarshal(raw, &record.Body); err != nil {
			return nil, err
		}
		records = append(records, record)
	}
	return records, rows.Err()
}

func (s *Store) tasksByID(ctx context.Context, userID string, ids map[string]struct{}) (map[string]Record, error) {
	result := make(map[string]Record, len(ids))
	if len(ids) == 0 {
		return result, nil
	}
	values := make([]string, 0, len(ids))
	for id := range ids {
		values = append(values, id)
	}
	records, err := s.queryRecords(ctx, `
		SELECT id, version, body, updated_at FROM tasks
		WHERE user_id = $1 AND id = ANY($2::uuid[])`, userID, values)
	if err != nil {
		return nil, err
	}
	for _, record := range records {
		result[record.ID] = record
	}
	return result, nil
}

func (s *Store) actualByTask(ctx context.Context, userID string, start, end time.Time) (map[string]int64, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT body ->> 'task_id', COALESCE(SUM((body ->> 'actual_duration_seconds')::bigint), 0)
		FROM focus_sessions
		WHERE user_id = $1 AND deleted_at IS NULL
		  AND body ->> 'task_id' IS NOT NULL
		  AND body ->> 'status' IN ('completed', 'abandoned', 'interrupted')
		  AND (body ->> 'started_at')::timestamptz >= $2
		  AND (body ->> 'started_at')::timestamptz < $3
		GROUP BY body ->> 'task_id'`, userID, start, end)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := map[string]int64{}
	for rows.Next() {
		var taskID string
		var seconds int64
		if err := rows.Scan(&taskID, &seconds); err != nil {
			return nil, err
		}
		result[taskID] = seconds
	}
	return result, rows.Err()
}

func (s *Store) loadPlannedSummary(ctx context.Context, userID string, start, end time.Time, timeZone string, days map[string]*DailySummary) error {
	rows, err := s.pool.Query(ctx, `
		SELECT to_char((body ->> 'starts_at')::timestamptz AT TIME ZONE $4, 'YYYY-MM-DD'),
		       COALESCE(SUM(EXTRACT(EPOCH FROM (
		           (body ->> 'ends_at')::timestamptz - (body ->> 'starts_at')::timestamptz
		       )))::bigint, 0)
		FROM plan_blocks
		WHERE user_id = $1 AND deleted_at IS NULL AND body ->> 'status' <> 'cancelled'
		  AND (body ->> 'starts_at')::timestamptz >= $2
		  AND (body ->> 'starts_at')::timestamptz < $3
		GROUP BY 1`, userID, start, end, timeZone)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var date string
		var seconds int64
		if err := rows.Scan(&date, &seconds); err != nil {
			return err
		}
		if day := days[date]; day != nil {
			day.PlannedDurationSeconds = seconds
		}
	}
	return rows.Err()
}

func (s *Store) loadActualSummary(ctx context.Context, userID string, start, end time.Time, timeZone string, days map[string]*DailySummary) error {
	rows, err := s.pool.Query(ctx, `
		SELECT to_char((body ->> 'started_at')::timestamptz AT TIME ZONE $4, 'YYYY-MM-DD'),
		       COALESCE(SUM((body ->> 'actual_duration_seconds')::bigint), 0)
		FROM focus_sessions
		WHERE user_id = $1 AND deleted_at IS NULL
		  AND body ->> 'status' IN ('completed', 'abandoned', 'interrupted')
		  AND (body ->> 'started_at')::timestamptz >= $2
		  AND (body ->> 'started_at')::timestamptz < $3
		GROUP BY 1`, userID, start, end, timeZone)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var date string
		var seconds int64
		if err := rows.Scan(&date, &seconds); err != nil {
			return err
		}
		if day := days[date]; day != nil {
			day.ActualDurationSeconds = seconds
		}
	}
	return rows.Err()
}

func (s *Store) loadCompletedSummary(ctx context.Context, userID string, start, end time.Time, timeZone string, days map[string]*DailySummary) error {
	rows, err := s.pool.Query(ctx, `
		SELECT to_char((body ->> 'completed_at')::timestamptz AT TIME ZONE $4, 'YYYY-MM-DD'), COUNT(*)
		FROM tasks
		WHERE user_id = $1 AND deleted_at IS NULL AND body ->> 'status' = 'completed'
		  AND (body ->> 'completed_at')::timestamptz >= $2
		  AND (body ->> 'completed_at')::timestamptz < $3
		GROUP BY 1`, userID, start, end, timeZone)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var date string
		var count int64
		if err := rows.Scan(&date, &count); err != nil {
			return err
		}
		if day := days[date]; day != nil {
			day.CompletedTasks = count
		}
	}
	return rows.Err()
}

func localDayBounds(date, timeZone string) (*time.Location, time.Time, time.Time, error) {
	location, err := time.LoadLocation(timeZone)
	if err != nil {
		return nil, time.Time{}, time.Time{}, errors.New("time_zone must be an IANA time zone")
	}
	parsed, err := time.ParseInLocation("2006-01-02", date, location)
	if err != nil || parsed.Format("2006-01-02") != date {
		return nil, time.Time{}, time.Time{}, errors.New("date must use YYYY-MM-DD format")
	}
	return location, parsed.UTC(), parsed.AddDate(0, 0, 1).UTC(), nil
}

func collectStringID(body map[string]any, field string, result map[string]struct{}) {
	if value, ok := bodyString(body, field); ok {
		result[value] = struct{}{}
	}
}

func bodyString(body map[string]any, field string) (string, bool) {
	value, ok := body[field].(string)
	return value, ok && value != ""
}

func bodyStringOr(body map[string]any, field, fallback string) string {
	if value, ok := bodyString(body, field); ok {
		return value
	}
	return fallback
}

func linkedTaskID(entry, block *Record) string {
	if entry != nil {
		if value, ok := bodyString(entry.Body, "task_id"); ok {
			return value
		}
	}
	if block != nil {
		if value, ok := bodyString(block.Body, "task_id"); ok {
			return value
		}
	}
	return ""
}

func blockDuration(body map[string]any) int64 {
	startsAt, startErr := time.Parse(time.RFC3339Nano, bodyStringOr(body, "starts_at", ""))
	endsAt, endErr := time.Parse(time.RFC3339Nano, bodyStringOr(body, "ends_at", ""))
	if startErr != nil || endErr != nil || !endsAt.After(startsAt) {
		return 0
	}
	return int64(endsAt.Sub(startsAt).Seconds())
}
