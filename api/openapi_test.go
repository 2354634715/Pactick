package api

import (
	"os"
	"strings"
	"testing"

	"gopkg.in/yaml.v3"
)

func TestOpenAPIDocumentParsesAndLocalReferencesResolve(t *testing.T) {
	raw, err := os.ReadFile("openapi.yaml")
	if err != nil {
		t.Fatalf("ReadFile() error = %v", err)
	}
	var document map[string]any
	if err := yaml.Unmarshal(raw, &document); err != nil {
		t.Fatalf("OpenAPI YAML error = %v", err)
	}
	if document["openapi"] != "3.1.0" {
		t.Fatalf("openapi version = %v", document["openapi"])
	}
	components, ok := document["components"].(map[string]any)
	if !ok {
		t.Fatal("components is missing")
	}
	checkReferences(t, document, components)
}

func TestClientUpdateCheckContractIsPublic(t *testing.T) {
	raw, err := os.ReadFile("openapi.yaml")
	if err != nil {
		t.Fatalf("ReadFile() error = %v", err)
	}
	var document map[string]any
	if err := yaml.Unmarshal(raw, &document); err != nil {
		t.Fatalf("OpenAPI YAML error = %v", err)
	}
	paths, ok := document["paths"].(map[string]any)
	if !ok {
		t.Fatal("paths is missing")
	}
	path, ok := paths["/v1/client-updates/check"].(map[string]any)
	if !ok {
		t.Fatal("client update check path is missing")
	}
	operation, ok := path["get"].(map[string]any)
	if !ok {
		t.Fatal("client update GET operation is missing")
	}
	security, ok := operation["security"].([]any)
	if !ok || len(security) != 0 {
		t.Fatalf("client update check must explicitly disable global authentication: %#v", operation["security"])
	}
	responses, ok := operation["responses"].(map[string]any)
	if !ok || responses["200"] == nil || responses["400"] == nil {
		t.Fatalf("client update responses are incomplete: %#v", operation["responses"])
	}
}

func checkReferences(t *testing.T, value any, components map[string]any) {
	t.Helper()
	switch node := value.(type) {
	case map[string]any:
		if reference, ok := node["$ref"].(string); ok && strings.HasPrefix(reference, "#/components/") {
			parts := strings.Split(strings.TrimPrefix(reference, "#/components/"), "/")
			if len(parts) != 2 {
				t.Fatalf("unsupported local reference %q", reference)
			}
			group, ok := components[parts[0]].(map[string]any)
			if !ok || group[parts[1]] == nil {
				t.Fatalf("unresolved local reference %q", reference)
			}
		}
		for _, child := range node {
			checkReferences(t, child, components)
		}
	case []any:
		for _, child := range node {
			checkReferences(t, child, components)
		}
	}
}
