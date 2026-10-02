package sync

type entityDefinition struct {
	table string
}

var entityDefinitions = map[string]entityDefinition{
	"project":              {table: "projects"},
	"task":                 {table: "tasks"},
	"task_recurrence_rule": {table: "task_recurrence_rules"},
	"tag":                  {table: "tags"},
	"task_tag":             {table: "task_tags"},
	"plan_block":           {table: "plan_blocks"},
	"day_entry":            {table: "day_plan_entries"},
	"focus_policy":         {table: "focus_policies"},
	"focus_session":        {table: "focus_sessions"},
	"focus_interruption":   {table: "focus_interruptions"},
	"reminder":             {table: "reminders"},
}

func definitionFor(entityType string) (entityDefinition, bool) {
	definition, ok := entityDefinitions[entityType]
	return definition, ok
}
