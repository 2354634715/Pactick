package clientupdate

import (
	"strings"
	"testing"
)

const validReleaseJSON = `{
    "platform": "android",
    "channel": "stable",
    "version": "1.2.3",
    "build_number": 42,
    "required": true,
    "download_url": "https://downloads.example.com/pactick-1.2.3.apk",
    "sha256": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    "size_bytes": 123456,
    "release_notes": "Security and reliability fixes.",
    "published_at": "2026-09-19T08:30:00+08:00"
  }`

const validManifest = `{"releases": [` + validReleaseJSON + `]}`

func TestParseManifestValidatesAndNormalizesRelease(t *testing.T) {
	catalog, err := ParseManifest(validManifest)
	if err != nil {
		t.Fatalf("ParseManifest() error = %v", err)
	}
	release, ok := catalog.Lookup("android", "stable")
	if !ok {
		t.Fatal("configured release was not found")
	}
	if release.Version != "1.2.3" || release.BuildNumber != 42 || !release.Required {
		t.Fatalf("release = %#v", release)
	}
	if release.SHA256 != strings.Repeat("a", 64) {
		t.Fatalf("normalized sha256 = %q", release.SHA256)
	}
	if got := release.PublishedAt.Format("2006-01-02T15:04:05Z07:00"); got != "2026-09-19T00:30:00Z" {
		t.Fatalf("published_at = %q", got)
	}
}

func TestParseManifestRejectsUnsafeOrAmbiguousEntries(t *testing.T) {
	tests := map[string]string{
		"non HTTPS URL":   strings.Replace(validManifest, "https://downloads.example.com", "file://downloads.example.com", 1),
		"URL credentials": strings.Replace(validManifest, "https://downloads.example.com", "https://user:pass@downloads.example.com", 1),
		"duplicate pair":  `{"releases": [` + validReleaseJSON + `,` + validReleaseJSON + `]}`,
		"unknown field":   strings.Replace(validManifest, `"required": true,`, `"required": true, "redirect_to": "https://evil.example",`, 1),
		"build metadata":  strings.Replace(validManifest, `"version": "1.2.3"`, `"version": "1.2.3+42"`, 1),
	}
	for name, manifest := range tests {
		t.Run(name, func(t *testing.T) {
			if _, err := ParseManifest(manifest); err == nil {
				t.Fatal("ParseManifest() accepted invalid manifest")
			}
		})
	}
}

func TestCompareVersionsUsesSemanticVersionPrecedence(t *testing.T) {
	tests := []struct {
		left  string
		right string
		want  int
	}{
		{left: "1.0.0", right: "1.0.0", want: 0},
		{left: "1.0.1", right: "1.0.0", want: 1},
		{left: "2.0.0", right: "10.0.0", want: -1},
		{left: "1.0.0", right: "1.0.0-rc.1", want: 1},
		{left: "1.0.0-beta.11", right: "1.0.0-beta.2", want: 1},
		{left: "1.0.0-alpha", right: "1.0.0-alpha.1", want: -1},
	}
	for _, test := range tests {
		comparison, err := CompareVersions(test.left, test.right)
		if err != nil {
			t.Fatalf("CompareVersions(%q, %q) error = %v", test.left, test.right, err)
		}
		if comparison != test.want {
			t.Fatalf("CompareVersions(%q, %q) = %d, want %d", test.left, test.right, comparison, test.want)
		}
	}
}
