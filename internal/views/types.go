package views

import "time"

type Record struct {
	ID        string         `json:"id"`
	Version   int64          `json:"version"`
	Body      map[string]any `json:"body"`
	UpdatedAt time.Time      `json:"updated_at"`
}

type TodayItem struct {
	ID                     string  `json:"id"`
	Derived                bool    `json:"derived"`
	Origin                 string  `json:"origin"`
	DayEntry               *Record `json:"day_entry,omitempty"`
	PlanBlock              *Record `json:"plan_block,omitempty"`
	Task                   *Record `json:"task,omitempty"`
	PlannedDurationSeconds int64   `json:"planned_duration_seconds"`
	ActualDurationSeconds  int64   `json:"actual_duration_seconds"`
}

type TodayView struct {
	Date     string      `json:"date"`
	TimeZone string      `json:"time_zone"`
	Items    []TodayItem `json:"items"`
}

type CalendarView struct {
	StartsAt      time.Time `json:"starts_at"`
	EndsAt        time.Time `json:"ends_at"`
	PlanBlocks    []Record  `json:"plan_blocks"`
	FocusSessions []Record  `json:"focus_sessions"`
	Tasks         []Record  `json:"tasks"`
}

type DailySummary struct {
	Date                   string `json:"date"`
	PlannedDurationSeconds int64  `json:"planned_duration_seconds"`
	ActualDurationSeconds  int64  `json:"actual_duration_seconds"`
	CompletedTasks         int64  `json:"completed_tasks"`
}

type Summary struct {
	StartsOn               string         `json:"starts_on"`
	EndsOn                 string         `json:"ends_on"`
	TimeZone               string         `json:"time_zone"`
	PlannedDurationSeconds int64          `json:"planned_duration_seconds"`
	ActualDurationSeconds  int64          `json:"actual_duration_seconds"`
	CompletedTasks         int64          `json:"completed_tasks"`
	Days                   []DailySummary `json:"days"`
}
