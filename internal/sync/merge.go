package sync

import (
	"encoding/json"
	"errors"
	"io"
	"sort"
)

type mergeResult struct {
	body           map[string]any
	fieldVersions  map[string]int64
	conflictFields []string
	serverValues   map[string]any
	clientValues   map[string]any
}

func decodeObject(raw json.RawMessage) (map[string]any, error) {
	if len(raw) == 0 {
		return nil, errors.New("patch is required")
	}
	decoder := json.NewDecoder(bytesReader(raw))
	decoder.UseNumber()
	var object map[string]any
	if err := decoder.Decode(&object); err != nil {
		return nil, err
	}
	if object == nil {
		return nil, errors.New("patch must be a JSON object")
	}
	var trailing any
	if err := decoder.Decode(&trailing); !errors.Is(err, io.EOF) {
		return nil, errors.New("patch must contain exactly one JSON object")
	}
	return object, nil
}

func mergeDocument(
	existing map[string]any,
	fieldVersions map[string]int64,
	patch map[string]any,
	changedFields []string,
	baseVersion int64,
	newVersion int64,
) (mergeResult, error) {
	if err := validateChangedFields(patch, changedFields); err != nil {
		return mergeResult{}, err
	}
	body := cloneMap(existing)
	versions := cloneVersions(fieldVersions)
	result := mergeResult{
		body:          body,
		fieldVersions: versions,
		serverValues:  map[string]any{},
		clientValues:  map[string]any{},
	}
	for _, field := range changedFields {
		incoming := patch[field]
		if versions[field] > baseVersion {
			result.conflictFields = append(result.conflictFields, field)
			result.serverValues[field] = body[field]
			result.clientValues[field] = incoming
		}
		if incoming == nil {
			delete(body, field)
		} else {
			body[field] = incoming
		}
		versions[field] = newVersion
	}
	sort.Strings(result.conflictFields)
	return result, nil
}

func validateChangedFields(patch map[string]any, fields []string) error {
	if len(fields) == 0 {
		return &ValidationError{Field: "changed_fields", Message: "must not be empty for an upsert"}
	}
	seen := make(map[string]struct{}, len(fields))
	for _, field := range fields {
		if field == "" {
			return &ValidationError{Field: "changed_fields", Message: "contains an empty field name"}
		}
		if _, duplicate := seen[field]; duplicate {
			return &ValidationError{Field: "changed_fields", Message: "contains duplicate field " + field}
		}
		seen[field] = struct{}{}
		if _, present := patch[field]; !present {
			return &ValidationError{Field: "patch", Message: "is missing changed field " + field}
		}
	}
	if len(patch) != len(seen) {
		return &ValidationError{Field: "patch", Message: "contains fields not declared in changed_fields"}
	}
	return nil
}

func cloneMap(source map[string]any) map[string]any {
	result := make(map[string]any, len(source))
	for key, value := range source {
		result[key] = value
	}
	return result
}

func cloneVersions(source map[string]int64) map[string]int64 {
	result := make(map[string]int64, len(source))
	for key, value := range source {
		result[key] = value
	}
	return result
}
