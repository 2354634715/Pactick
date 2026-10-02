package server_test

import (
	"context"
	"os"
	"os/exec"
	"runtime"
	"slices"
	"strings"
	"testing"
	"time"

	"gopkg.in/yaml.v3"
)

// The harness runs the real shell entry points against isolated configuration
// files and fake Docker commands; it never requires a daemon or host services.
func TestUpgradeCommitsConfigurationOnlyAfterReady(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("run deploy/tests/upgrade_test.sh directly with Git Bash on Windows; Go invokes the shell harness on Linux")
	}
	bashPath := os.Getenv("PACTICK_TEST_BASH")
	if bashPath == "" {
		var err error
		bashPath, err = exec.LookPath("bash")
		if err != nil {
			t.Skip("bash is required for deployment failure tests")
		}
	}
	for _, stage := range []string{"build", "postgres", "backup", "stop", "state", "migrate", "api", "readyz", "retry", "success"} {
		t.Run(stage, func(t *testing.T) {
			ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
			defer cancel()
			cmd := exec.CommandContext(ctx, bashPath, "deploy/tests/upgrade_test.sh", stage)
			cmd.WaitDelay = 3 * time.Second
			output, err := cmd.CombinedOutput()
			if err != nil {
				t.Fatalf("upgrade failure regression (%s): %v\n%s", stage, err, output)
			}
			t.Log(strings.TrimSpace(string(output)))
		})
	}
}

type composeFile struct {
	Services map[string]composeService `yaml:"services"`
	Networks map[string]struct {
		Internal bool `yaml:"internal"`
	} `yaml:"networks"`
}

type composeService struct {
	Ports       []string `yaml:"ports"`
	Networks    []string `yaml:"networks"`
	ReadOnly    bool     `yaml:"read_only"`
	CapDrop     []string `yaml:"cap_drop"`
	SecurityOpt []string `yaml:"security_opt"`
	Restart     string   `yaml:"restart"`
	Entrypoint  []string `yaml:"entrypoint"`
}

func TestProductionComposeKeepsDatabasePrivate(t *testing.T) {
	raw, err := os.ReadFile("compose.production.yaml")
	if err != nil {
		t.Fatalf("read production compose: %v", err)
	}
	var config composeFile
	if err := yaml.Unmarshal(raw, &config); err != nil {
		t.Fatalf("parse production compose: %v", err)
	}

	postgres, ok := config.Services["postgres"]
	if !ok {
		t.Fatal("production compose has no postgres service")
	}
	if len(postgres.Ports) != 0 {
		t.Fatalf("PostgreSQL must not publish host ports: %v", postgres.Ports)
	}
	if postgres.Restart != "unless-stopped" {
		t.Fatalf("PostgreSQL restart policy = %q", postgres.Restart)
	}
	if !slices.Equal(postgres.Networks, []string{"backend"}) {
		t.Fatalf("PostgreSQL must only join the private backend network: %v", postgres.Networks)
	}
	if network, ok := config.Networks["backend"]; !ok || !network.Internal {
		t.Fatal("backend Docker network must be internal")
	}
	if network, ok := config.Networks["ingress"]; !ok || network.Internal {
		t.Fatal("API ingress Docker network must exist and provide a host-publishable gateway")
	}
}

func TestProductionComposeHardensAPIAndProvidesMigration(t *testing.T) {
	raw, err := os.ReadFile("compose.production.yaml")
	if err != nil {
		t.Fatalf("read production compose: %v", err)
	}
	var config composeFile
	if err := yaml.Unmarshal(raw, &config); err != nil {
		t.Fatalf("parse production compose: %v", err)
	}

	api, ok := config.Services["api"]
	if !ok {
		t.Fatal("production compose has no api service")
	}
	if !slices.Equal(api.Ports, []string{"127.0.0.1:${PACTICK_HTTP_PORT:-8080}:8080"}) {
		t.Fatalf("API must bind only to loopback: %v", api.Ports)
	}
	if !slices.Equal(api.Networks, []string{"ingress", "backend"}) {
		t.Fatalf("API must join ingress and backend networks in that order: %v", api.Networks)
	}
	if !api.ReadOnly || !slices.Contains(api.CapDrop, "ALL") || !slices.Contains(api.SecurityOpt, "no-new-privileges:true") {
		t.Fatalf("API hardening is incomplete: %#v", api)
	}
	if api.Restart != "unless-stopped" {
		t.Fatalf("API restart policy = %q", api.Restart)
	}

	migrate, ok := config.Services["migrate"]
	if !ok || !slices.Equal(migrate.Entrypoint, []string{"/migrate"}) {
		t.Fatalf("explicit migration service is missing or invalid: %#v", migrate)
	}
	if !slices.Equal(migrate.Networks, []string{"backend"}) {
		t.Fatalf("migration service must only join the private backend network: %v", migrate.Networks)
	}
}

func TestProductionImageContainsOperationalBinaries(t *testing.T) {
	raw, err := os.ReadFile("Dockerfile")
	if err != nil {
		t.Fatalf("read Dockerfile: %v", err)
	}
	content := string(raw)
	for _, expected := range []string{
		"-o /out/server ./cmd/server",
		"-o /out/migrate ./cmd/migrate",
		"-o /out/healthcheck ./cmd/healthcheck",
		"COPY --from=build /out/migrate /migrate",
		"COPY --from=build /out/healthcheck /healthcheck",
	} {
		if !strings.Contains(content, expected) {
			t.Fatalf("Dockerfile is missing %q", expected)
		}
	}
}

func TestProductionComposeSupportsPrebuiltLowMemoryImage(t *testing.T) {
	raw, err := os.ReadFile("compose.production.yaml")
	if err != nil {
		t.Fatalf("read production compose: %v", err)
	}
	if count := strings.Count(string(raw), "dockerfile: ${PACTICK_DOCKERFILE:-Dockerfile}"); count != 2 {
		t.Fatalf("configurable production Dockerfile declaration count = %d, want 2", count)
	}

	raw, err = os.ReadFile("Dockerfile.prebuilt")
	if err != nil {
		t.Fatalf("read prebuilt Dockerfile: %v", err)
	}
	content := string(raw)
	for _, expected := range []string{
		"COPY --chmod=0555 prebuilt/server /server",
		"COPY --chmod=0555 prebuilt/migrate /migrate",
		"COPY --chmod=0555 prebuilt/healthcheck /healthcheck",
		"USER nonroot:nonroot",
	} {
		if !strings.Contains(content, expected) {
			t.Fatalf("prebuilt Dockerfile is missing %q", expected)
		}
	}
}

func TestDeploymentVerificationUsesDockerHostPortBindings(t *testing.T) {
	raw, err := os.ReadFile("deploy/scripts/verify-deployment.sh")
	if err != nil {
		t.Fatalf("read deployment verification script: %v", err)
	}
	content := string(raw)
	if strings.Contains(content, "port postgres 5432") {
		t.Fatal("verification must not use `docker compose port` for an unpublished PostgreSQL port")
	}
	if !strings.Contains(content, ".HostConfig.PortBindings") {
		t.Fatal("verification must inspect Docker host port bindings directly")
	}
}

func TestNginxTemplatePreservesWebSocketForwarding(t *testing.T) {
	raw, err := os.ReadFile("deploy/nginx/pactick-https.conf.template")
	if err != nil {
		t.Fatalf("read Nginx template: %v", err)
	}
	content := string(raw)
	start := strings.Index(content, "location = /v1/ws {")
	if start < 0 {
		t.Fatal("Nginx template has no exact WebSocket location")
	}
	remaining := content[start:]
	end := strings.Index(remaining, "\n    }")
	if end < 0 {
		t.Fatal("Nginx WebSocket location is not closed")
	}
	websocketBlock := remaining[:end]
	for _, expected := range []string{
		"proxy_set_header Host $host;",
		"proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;",
		"proxy_set_header Upgrade $http_upgrade;",
		"proxy_set_header Connection $pactick_connection_upgrade;",
		"proxy_read_timeout 90s;",
	} {
		if !strings.Contains(websocketBlock, expected) {
			t.Fatalf("WebSocket proxy block is missing %q", expected)
		}
	}
}

func TestPreOneZeroBackupPolicyIsLocalOnly(t *testing.T) {
	for _, path := range []string{
		"deploy/config/backup.env.example",
		"deploy/scripts/backup.sh",
	} {
		raw, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("read %s: %v", path, err)
		}
		content := strings.ToLower(string(raw))
		for _, forbidden := range []string{"rclone", "require_offsite", "rclone_remote"} {
			if strings.Contains(content, forbidden) {
				t.Fatalf("pre-1.0 server asset %s still enables %q", path, forbidden)
			}
		}
	}
}
