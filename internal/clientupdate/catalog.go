package clientupdate

import (
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/url"
	"strings"
	"time"
	"unicode/utf8"
)

const (
	maxManifestBytes = 256 << 10
	maxReleases      = 32
	maxReleaseNotes  = 20_000
)

var supportedPlatforms = map[string]struct{}{
	"android": {},
	"linux":   {},
	"windows": {},
}

var supportedChannels = map[string]struct{}{
	"beta":   {},
	"stable": {},
}

// Release is a deployable client artifact published for one platform and channel.
type Release struct {
	Platform     string
	Channel      string
	Version      string
	BuildNumber  int64
	Required     bool
	DownloadURL  string
	SHA256       string
	SizeBytes    int64
	ReleaseNotes string
	PublishedAt  time.Time
}

type releaseKey struct {
	platform string
	channel  string
}

// Catalog is an immutable lookup table built from CLIENT_UPDATE_MANIFEST_JSON.
type Catalog struct {
	releases map[releaseKey]Release
}

type manifestJSON struct {
	Releases *[]releaseJSON `json:"releases"`
}

type releaseJSON struct {
	Platform     string  `json:"platform"`
	Channel      string  `json:"channel"`
	Version      string  `json:"version"`
	BuildNumber  *int64  `json:"build_number"`
	Required     *bool   `json:"required"`
	DownloadURL  string  `json:"download_url"`
	SHA256       string  `json:"sha256"`
	SizeBytes    *int64  `json:"size_bytes"`
	ReleaseNotes *string `json:"release_notes"`
	PublishedAt  string  `json:"published_at"`
}

// ParseManifest parses and validates a JSON update manifest. An empty value is
// a valid empty catalog, allowing deployments to roll out the endpoint before
// publishing an artifact.
func ParseManifest(raw string) (*Catalog, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return &Catalog{releases: make(map[releaseKey]Release)}, nil
	}
	if len(raw) > maxManifestBytes {
		return nil, fmt.Errorf("manifest exceeds %d bytes", maxManifestBytes)
	}

	decoder := json.NewDecoder(strings.NewReader(raw))
	decoder.DisallowUnknownFields()
	var manifest manifestJSON
	if err := decoder.Decode(&manifest); err != nil {
		return nil, fmt.Errorf("decode manifest: %w", err)
	}
	var extra any
	if err := decoder.Decode(&extra); !errors.Is(err, io.EOF) {
		if err == nil {
			return nil, errors.New("manifest must contain exactly one JSON value")
		}
		return nil, fmt.Errorf("decode trailing manifest data: %w", err)
	}
	if manifest.Releases == nil {
		return nil, errors.New("releases must be a JSON array")
	}
	if len(*manifest.Releases) > maxReleases {
		return nil, fmt.Errorf("releases contains more than %d entries", maxReleases)
	}

	catalog := &Catalog{releases: make(map[releaseKey]Release, len(*manifest.Releases))}
	for index, rawRelease := range *manifest.Releases {
		release, err := validateRelease(rawRelease)
		if err != nil {
			return nil, fmt.Errorf("releases[%d]: %w", index, err)
		}
		key := releaseKey{platform: release.Platform, channel: release.Channel}
		if _, exists := catalog.releases[key]; exists {
			return nil, fmt.Errorf("releases[%d]: duplicate platform/channel pair", index)
		}
		catalog.releases[key] = release
	}
	return catalog, nil
}

// Lookup returns the configured latest release for a platform/channel pair.
func (c *Catalog) Lookup(platform, channel string) (Release, bool) {
	if c == nil {
		return Release{}, false
	}
	release, ok := c.releases[releaseKey{platform: platform, channel: channel}]
	return release, ok
}

// Len returns the number of configured platform/channel releases.
func (c *Catalog) Len() int {
	if c == nil {
		return 0
	}
	return len(c.releases)
}

func ValidatePlatform(value string) error {
	if _, ok := supportedPlatforms[value]; !ok {
		return errors.New("must be one of android, windows, linux")
	}
	return nil
}

func ValidateChannel(value string) error {
	if _, ok := supportedChannels[value]; !ok {
		return errors.New("must be one of stable, beta")
	}
	return nil
}

func validateRelease(raw releaseJSON) (Release, error) {
	if err := ValidatePlatform(raw.Platform); err != nil {
		return Release{}, fmt.Errorf("platform %w", err)
	}
	if err := ValidateChannel(raw.Channel); err != nil {
		return Release{}, fmt.Errorf("channel %w", err)
	}
	if err := ValidateVersion(raw.Version); err != nil {
		return Release{}, fmt.Errorf("version is invalid: %w", err)
	}
	if raw.BuildNumber == nil || *raw.BuildNumber < 1 {
		return Release{}, errors.New("build_number must be a positive integer")
	}
	if raw.Required == nil {
		return Release{}, errors.New("required must be a boolean")
	}
	if err := validateDownloadURL(raw.DownloadURL); err != nil {
		return Release{}, fmt.Errorf("download_url is invalid: %w", err)
	}
	sha256 := strings.ToLower(raw.SHA256)
	if len(sha256) != 64 {
		return Release{}, errors.New("sha256 must contain exactly 64 hexadecimal characters")
	}
	if _, err := hex.DecodeString(sha256); err != nil {
		return Release{}, errors.New("sha256 must contain exactly 64 hexadecimal characters")
	}
	if raw.SizeBytes == nil || *raw.SizeBytes < 1 {
		return Release{}, errors.New("size_bytes must be a positive integer")
	}
	if raw.ReleaseNotes == nil {
		return Release{}, errors.New("release_notes must be a string")
	}
	if !utf8.ValidString(*raw.ReleaseNotes) || utf8.RuneCountInString(*raw.ReleaseNotes) > maxReleaseNotes {
		return Release{}, fmt.Errorf("release_notes must contain at most %d UTF-8 characters", maxReleaseNotes)
	}
	publishedAt, err := time.Parse(time.RFC3339, raw.PublishedAt)
	if err != nil {
		return Release{}, errors.New("published_at must be an RFC 3339 timestamp")
	}

	return Release{
		Platform:     raw.Platform,
		Channel:      raw.Channel,
		Version:      raw.Version,
		BuildNumber:  *raw.BuildNumber,
		Required:     *raw.Required,
		DownloadURL:  raw.DownloadURL,
		SHA256:       sha256,
		SizeBytes:    *raw.SizeBytes,
		ReleaseNotes: *raw.ReleaseNotes,
		PublishedAt:  publishedAt.UTC(),
	}, nil
}

func validateDownloadURL(value string) error {
	if value == "" || strings.TrimSpace(value) != value || len(value) > 2_048 {
		return errors.New("must be a non-empty URL no longer than 2048 characters")
	}
	parsed, err := url.Parse(value)
	if err != nil {
		return errors.New("must be a valid absolute HTTPS URL")
	}
	if parsed.Scheme != "https" || !parsed.IsAbs() || parsed.Hostname() == "" || parsed.User != nil || parsed.Fragment != "" || parsed.Opaque != "" {
		return errors.New("must be an absolute HTTPS URL without credentials or a fragment")
	}
	return nil
}
