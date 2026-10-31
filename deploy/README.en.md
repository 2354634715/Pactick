[简体中文](README.md) | English

# Self-hosting assets

Prepare the host according to the [self-hosting guide](../docs/SELF_HOSTING.en.md). Run the following from the repository root to install the server. `--local-only` configures only a loopback API; the administrator must configure an HTTPS proxy separately.

These assets provide Linux command-line deployment. `deploy/desktop/compose.yaml` serves the separate [local server management UI](../docs/SERVER_MANAGEMENT.en.md). The manager and administrator tools distinguish Windows/Linux amd64 and 386 targets; 386 supports only native-process mode. Administrators can supply account JSON on standard input while keeping public registration closed. Cross-compilation does not establish runtime acceptance on those platforms or install a Windows service.

```bash
sudo bash deploy/scripts/install.sh install --local-only
```

## Files and purposes

| File | Purpose |
| --- | --- |
| `scripts/install.sh` | Configuration initialization, installation, upgrade, registration controls, backup, isolated restore checks, and status. Upgrades use candidate image configuration; a release unfinished after migration blocks registration controls |
| `../compose.production.yaml` | Private PostgreSQL network, loopback API, explicit migration service, and non-root read-only API container |
| `scripts/validate-config.sh` | Check permissions, placeholders, credential consistency, and Compose configuration |
| `scripts/release.sh` | Build images, await the database, back up before migration, stop the old API, migrate, and check API readiness. Commit candidate configuration after readiness when the caller specifies a target |
| `scripts/backup.sh` | Create local logical backups, verify the content directory and SHA-256, and clean up under tiered retention |
| `scripts/restore-check.sh` | Restore in a network-isolated temporary container with a separate volume |
| `scripts/verify-deployment.sh` | Check container health, port binding, API, backup freshness, and optional public HTTPS |
| `config/*.env.example` | Configuration templates; keep actual files outside the repository with mode 0600 |
| `nginx/*.template` | HTTP ACME validation and HTTPS/WSS reverse proxy |
| `systemd/pactick-backup.*` | Daily backups on the server itself |
| `tests/install_test.sh` | Test configuration initialization, idempotence, and failures without Docker |
| `tests/release_test.sh` | Use simulated Docker to check backup, migration, replacement order, and stopping on failure |
| `tests/upgrade_test.sh` | Use isolated configuration and simulated Docker to check build, database readiness, backup, API stop, migration-state writes, preservation of production image configuration on migration/API failure, registration controls, and upgrade retries |
| `tests/https_test.sh` | Check site restoration after certificate issuance, configuration-check, or reload failures in an isolated directory |

## Manual configuration

Without the entry-point installer, copy configuration templates to `/opt/pactick/config`. Set every `.env` file to 0600 and allow only trusted administrators to edit it. Operational scripts read these files as shell configuration.

Generate a hexadecimal database password from 32 random bytes and a separate JWT secret from 64 random bytes. Keep the database password consistent between `postgres.env` and `DATABASE_URL` in `api.env`. Production uses `AUTO_MIGRATE=false`; registration defaults to closed. Native clients need no CORS.

Use a new image tag for every release; do not use `latest`. Leave `CLIENT_UPDATE_MANIFEST_JSON` empty by default. Current clients use Releases to view updates; the server retains the legacy update API for older versions.

`install.sh upgrade` creates a candidate configuration automatically and commits it after API readiness. When calling `release.sh` directly, `PACTICK_COMPOSE_ENV` defaults to `compose.env` in the configuration directory, and the script does not generate a new image tag. For manual releases, first copy the production file to a private candidate, change its `PACTICK_IMAGE`, point `PACTICK_COMPOSE_ENV` to it, and set `PACTICK_RELEASE_CONFIG_TARGET` to that directory's production `compose.env`. Both files must be 0600. On success the script moves the candidate over the target; on failure it preserves the production file and leaves manual candidate disposal to the administrator.

After migration begins, `.release-pending` remains until API readiness and configuration commit complete. Failures in this interval do not automatically roll back the database or containers. The entry point blocks registration controls from recreating an API without confirmed compatibility. See [upgrade and recovery](../docs/SELF_HOSTING.en.md#4-upgrade) for retry and manual recovery conditions. Direct Compose commands are not protected by this check.

## Low-memory hosts

Cross-compile on a trusted administration machine and place four static Linux binaries in `prebuilt/` within the target source directory:

```bash
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -o prebuilt/server ./cmd/server
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -o prebuilt/migrate ./cmd/migrate
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -o prebuilt/healthcheck ./cmd/healthcheck
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -o prebuilt/admin ./cmd/admin
```

Use `GOARCH=arm64` for ARM64 hosts. First generate configuration for the actual deployment directory using `install --prepare-only`, set `PACTICK_DOCKERFILE=Dockerfile.prebuilt` in `compose.env`, then perform installation. The runtime still uses a non-root distroless image.

## Render Nginx manually

Assign the actual domain and port to `API_DOMAIN` and `PACTICK_HTTP_PORT`. Restrict substitution when rendering the HTTPS template to preserve Nginx variables such as `$host`:

```bash
export API_DOMAIN=api.example.com PACTICK_HTTP_PORT=8080
envsubst '${API_DOMAIN} ${PACTICK_HTTP_PORT}' \
  < deploy/nginx/pactick-https.conf.template
```

## Backup limits

Backups default to the server itself. Restore checks verify logical recoverability; loss of the host still requires an available off-site copy and a corresponding recovery procedure.
