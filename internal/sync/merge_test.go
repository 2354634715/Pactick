package sync

import (
	"encoding/json"
	"reflect"
	"testing"
)

func TestMergeDocumentMergesIndependentFields(t *testing.T) {
	existing := map[string]any{"title": "old", "priority": "low"}
	versions := map[string]int64{"title": 2, "priority": 1}
	patch := map[string]any{"priority": "high"}
	result, err := mergeDocument(existing, versions, patch, []string{"priority"}, 1, 3)
	if err != nil {
		t.Fatalf("mergeDocument() error = %v", err)
	}
	if len(result.conflictFields) != 0 || result.body["title"] != "old" || result.body["priority"] != "high" {
		t.Fatalf("mergeDocument() = %#v", result)
	}
}

func TestMergeDocumentRecordsSameFieldConflict(t *testing.T) {
	existing := map[string]any{"title": "server"}
	versions := map[string]int64{"title": 4}
	patch := map[string]any{"title": "client"}
	result, err := mergeDocument(existing, versions, patch, []string{"title"}, 2, 5)
	if err != nil {
		t.Fatalf("mergeDocument() error = %v", err)
	}
	if !reflect.DeepEqual(result.conflictFields, []string{"title"}) || result.body["title"] != "client" {
		t.Fatalf("mergeDocument() = %#v", result)
	}
	if result.serverValues["title"] != "server" || result.clientValues["title"] != "client" {
		t.Fatalf("conflict values = %#v / %#v", result.serverValues, result.clientValues)
	}
}

func TestMergeDocumentNullRemovesOptionalField(t *testing.T) {
	result, err := mergeDocument(
		map[string]any{"note": "remove me"},
		map[string]int64{"note": 1},
		map[string]any{"note": nil},
		[]string{"note"},
		1,
		2,
	)
	if err != nil {
		t.Fatalf("mergeDocument() error = %v", err)
	}
	if _, exists := result.body["note"]; exists {
		t.Fatal("mergeDocument() did not remove a null field")
	}
}

func TestDecodeObjectRejectsTrailingJSON(t *testing.T) {
	if _, err := decodeObject(json.RawMessage(`{"title":"one"} {"title":"two"}`)); err == nil {
		t.Fatal("decodeObject() accepted trailing JSON")
	}
}
