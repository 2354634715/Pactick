[简体中文](SELF_HOSTING.md) | English

# Self-hosted server

The server provides optional synchronization across devices. Standalone local use needs no server. This guide applies to one Ubuntu/Debian host using systemd, Docker Engine, and Compose v2.

This document uses Linux command-line deployment scripts. The Windows/Linux local browser manager supports API start/stop, configuration, logs, backup, isolated restore checks, and administrator account creation. See [local server management](SERVER_MANAGEMENT.en.md) for operating modes and amd64/386 differences. Android task notifications are displayed locally and require no additional reminder service.

## 1. Prepare the host

First install Docker Engine and the Compose plugin using [Docker's Ubuntu installation guide](https://docs.docker.com/engine/install/ubuntu/). Then install other tools and enable Docker:

```bash
sudo apt-get update
sudo apt-get install -y curl openssl nginx certbot gettext-base
sudo systemctl enable --now docker
docker compose version
```

`--local-only` needs no Nginx, Certbot, or gettext-base. The server must be able to pull Go, PostgreSQL, and distroless images. At least 2 GiB RAM is recommended for source builds on the host. Low-memory hosts can use prebuilt binaries as described in [deployment assets](../deploy/README.en.md).

Place reviewed complete source in `/opt/pactick/app`, or another fixed absolute path without spaces. Scheduled backups later use this path. Do not upload an entire development workspace; use a clean source snapshot generated through [releasing](RELEASING.en.md).

HTTPS mode requires domain A/AAAA records pointing to the host and public TCP access on 80 and 443. Remove invalid AAAA records. The script changes neither firewall nor SSH configuration; administrators must open ports according to host policy.

## 2. Install

```bash
cd /opt/pactick/app
sudo bash deploy/scripts/install.sh install \
  --domain api.example.com \
  --email admin@example.com \
  --accept-acme-terms
```

`--accept-acme-terms` means the deployer accepts the Let's Encrypt account terms. The script uses Certbot webroot verification, retains renewal challenge paths, installs an Nginx reload hook after renewal, and enables `certbot.timer`. See [Certbot webroot](https://eff-certbot.readthedocs.io/en/stable/using.html#webroot).

With an existing HTTPS proxy, or for initial acceptance through a tunnel, use local-only mode:

```bash
sudo bash deploy/scripts/install.sh install --local-only
```

It listens only at `http://127.0.0.1:8080`. Remote Android clients cannot directly reach the server's loopback address. Configure your HTTPS/WSS proxy and enter the proxy address in the client.

Optional configuration:

```bash
sudo bash deploy/scripts/install.sh install --local-only \
  --config-dir /opt/pactick/config \
  --backup-dir /var/backups/pactick \
  --port 8080
```

Generate configuration for inspection without installing:

```bash
bash deploy/scripts/install.sh install --prepare-only --local-only \
  --config-dir /tmp/pactick-config
```

`--prepare-only` does create 0600 files containing secrets, but changes no Docker, Nginx, or systemd configuration. Regenerate for the actual deployment directory or migrate the complete configuration and correct its paths. Do not commit this secret-containing directory or attach it to public issues.

Installation order is independent random-secret generation → configuration validation → image build → await PostgreSQL → pre-migration backup → stop existing API → explicit migration → API health check → scheduled backup → optional HTTPS → acceptance. Repeating `install` retains existing secrets, ports, and backup paths; incomplete configuration stops installation. Use `upgrade` to generate a new image tag after source changes.

During HTTPS configuration, a temporary domain-validation site coexists with the original site. The production site is replaced only after certificate issuance succeeds. Certificate issuance, Nginx configuration-check, or reload failure restores the original configuration. Backup scripts use a separate execution lock and random filename suffixes to prevent scheduled and manual backups overwriting one another.

The API publishes only on `127.0.0.1`; PostgreSQL publishes no host port. Configuration defaults to `/opt/pactick/config`; a named Compose volume persists the database. Operational scripts must be maintained by trusted administrators, and their `.env` files use shell-compatible syntax.

## 3. Create an initial account and close registration

Public registration is closed by default. The current image's standalone `/admin` command directly creates ordinary users without temporarily opening registration, registering devices, or issuing login tokens. Run from the repository root:

```bash
printf '%s\n' '{"email":"member@example.com","time_zone":"Asia/Shanghai"}' | \
  sudo bash deploy/scripts/install.sh create-account
```

The command reads one UTF-8 JSON object from standard input, up to 32 KiB. With no password, it generates a random password and returns it in that successful output. Save it in a password manager and keep it out of shared logs. Recreating the same email fails without changing its password. See [account creation](SERVER_MANAGEMENT.en.md#create-accounts) for optional fields, defaults, and standalone usage. The Docker API container must be running and contain `/admin`; upgrade older images missing that command first.

Run `registration open` only when ordinary self-service registration is needed. The endpoint is `POST /v1/auth/register`; see [OpenAPI](../api/openapi.en.yaml) for request format. Close it when finished:

```bash
sudo bash deploy/scripts/install.sh registration close
```

Closing registration does not prevent local administrator account creation or existing-user login. Enter `https://api.example.com` in the client's synchronization settings and sign in. A new server connection defaults to a separate workspace; uploading existing local data requires separate selection. Do not disclose `.env`, database backups, or access tokens.

All subsequent commands support `--config-dir /自定义/目录`. Use the same custom directory each time.

## 4. Upgrade

Review the new version on the administration machine and preserve the previous source and image, then update the same service directory and run the upgrade.

When upgrading old configuration without `HTTP_BEHIND_PROXY`, first set `HTTP_BEHIND_PROXY=true` in protected `api.env`. This declares plaintext container HTTP as an upstream for an isolated reverse proxy; the host publication address must remain `127.0.0.1`. New configurations generate this setting automatically. Old secrets and network settings are not rewritten automatically.

```bash
sudo bash deploy/scripts/install.sh upgrade
sudo bash deploy/scripts/install.sh status
```

The script copies current `compose.env`, generates a new image tag in a private candidate, and uses it for build, database readiness, and pre-migration backup. After backup succeeds, it stops the existing API, records migration state, migrates, and starts the candidate API. Only after API readiness does it replace production `compose.env` with the candidate. Failure removes temporary candidate configuration and retains the last successful image tag in production configuration. Database volumes, backups, and built images are not deleted automatically. If configuration commit or release-marker cleanup encounters filesystem errors, inspect production configuration, the running image, and release markers before retrying.

Build, database-readiness, or backup failure occurs before migration, API stop, or replacement in this release. Fix the cause and retry `upgrade`. With no previously unfinished release, registration controls keep using the production image. An existing `.release-pending` still blocks them.

If stopping the API fails, migration is not called. If writing migration state fails after API stop, migration has also not been called in this attempt. With no previously unfinished release, administrators may restart the original API using production `compose.env` before investigating. If `.release-pending` already exists, inspect the prior release's database state first; this attempt's error does not prove no migration occurred earlier.

Before invoking migration, the script writes `.release-pending` in the configuration directory, recording the candidate image and release phase. A failing migration command may have committed earlier migrations. Failed API startup or readiness may leave an upgraded database or a failed candidate API running. These failures retain `.release-pending`, blocking `registration open|close` before changes to `api.env` or API recreation. `backup`, `restore-check`, and `status` remain available for investigation. A successful `upgrade` retry commits image configuration, removes the marker, and restores registration controls.

Release scripts neither downgrade the database nor restore the original API image automatically. Keeping the original tag in production configuration does not mean the database or running container has rolled back. During migration, the Compose project's API stays stopped and the candidate starts only after migration succeeds. Older versions do not honor current synchronization write locks; do not bypass the script to start an old API during migration. Administrators must separately stop other processes using the database. Service is unavailable from API stop until candidate readiness. After migration failure, the original API stays stopped; choose retry or restoration according to the actual database state.

To return to an old version, inspect `.release-pending`, container logs, and the migration ledger to identify the current database and running image. Restart the old API through production configuration only after confirming compatibility with the current database. Otherwise verify a pre-migration backup in isolation as below, then restore it with its corresponding application version. Restoration discards writes after that backup. Remove `.release-pending` only after manual recovery and API readiness, login, and synchronization checks pass. Merely deleting the marker or changing an image tag is not recovery.

A host defaults to one `pactick` Compose project, one Nginx site, and one backup timer. Multiple instances require separate Compose projects, ports, volumes, sites, and systemd units arranged by the administrator.

## 5. Backup and restoration

```bash
sudo bash deploy/scripts/install.sh backup
sudo systemctl status pactick-backup.timer
sudo bash deploy/scripts/install.sh restore-check \
  /var/backups/pactick/daily/pactick-YYYYMMDD-HHMMSS-RANDOM.dump
```

Daily backups use PostgreSQL custom format with SHA-256. Retention is 7 daily, 4 weekly, 6 monthly, and 10 pre-migration copies. `restore-check` creates a separate volume and network-isolated temporary container, restores and checks the migration ledger and user table, then cleans up. It does not overwrite the live database.

Before restoring a production database, stop writes, preserve a copy of the failed database, and complete the isolated restoration check above. Restoring a verified backup to a new separate server is recommended:

1. Install the complete service with the same or a compatible PostgreSQL major version. Keep registration closed and stop the new host's API.
2. Copy `.dump` and `.sha256` into a private directory on the new host and verify them.
3. Restore into the new host's empty database using `pg_restore --clean --if-exists --no-owner --no-privileges --exit-on-error`. Run only against a destination confirmed safe to overwrite.
4. Start the application version corresponding to the backup and check `/readyz`, login, entity counts, and synchronization.
5. Switch the domain or client configuration only after verification. Retain the original host for rollback.

Local backups cannot protect against whole-host or disk loss. To address those failures, copy backups to another administrator-controlled host or offline media and rehearse recovery. Server account export and client offline backup serve data migration; they do not replace complete operational database backups.

## 6. Acceptance and troubleshooting

```bash
sudo bash deploy/scripts/install.sh status
sudo env PACTICK_PUBLIC_URL=https://api.example.com \
  bash deploy/scripts/verify-deployment.sh
sudo certbot renew --dry-run
sudo journalctl -u pactick-backup.service --since yesterday
```

Also test HTTPS login, two-device synchronization, and WebSocket from another device after deployment. Regularly inspect backup freshness, free disk space, and certificate renewal. Local health checks verify only local service state. Public access, two-device synchronization, and complete disaster recovery need separate acceptance.

## 7. Communication security configuration

The client defaults to HTTPS origins only. Certificate chains and hostnames must pass system trust verification. The current Flutter client uses REST incremental synchronization. The server also provides `/v1/ws` cursor hints; clients using it must connect with WSS on the same server. Debug builds accept HTTP for localhost, 127.0.0.1, ::1, and Android emulator 10.0.2.2 only when `ALLOW_INSECURE_LOCAL_SERVER` is explicitly enabled. This exception allows neither plaintext public domains nor production builds.

The Go API defaults to `127.0.0.1:8080`. Production non-loopback listening requires both `TLS_CERT_FILE` and `TLS_KEY_FILE`, or explicit `HTTP_BEHIND_PROXY=true`. Direct TLS requires at least TLS 1.2. Unreadable certificates or mismatched keys fail startup without falling back to HTTP. `HTTP_BEHIND_PROXY` does not verify a proxy or encrypt connections; administrators must still restrict upstream HTTP to loopback or a dedicated network. Existing Docker deployments listen on `:8080` inside the container, publish only to host loopback through Compose, and use Nginx for public TLS.

The reverse proxy supplies TLS 1.2/1.3, a 2 MiB body limit, login/refresh rate limits, and WebSocket Upgrade forwarding. Nginx limits source IPs to 30 concurrent connections. Ordinary API traffic allows 20 requests/second with a burst of 60, WebSocket handshakes a burst of 10, and authentication endpoints lower separate limits. HTTP redirects use the fixed configured domain. The API itself limits JSON bodies to 2 MiB and headers to 16 KiB, with header-read timeout 5 seconds, request-read 15 seconds, response-write 30 seconds, and idle timeout 90 seconds. WebSocket has separate read/write deadlines and a ping every 30 seconds. It periodically revalidates tokens and devices, closing on expiration, revocation, or validation failure. Clients must subsequently reauthenticate or reconnect. See [Go HTTP Server](https://pkg.go.dev/net/http#Server) and [Nginx WebSocket proxying](https://nginx.org/en/docs/http/websocket.html) for timeout and upgrade behavior.

The API also applies source-address token-bucket limits: authentication replenishes 20 requests/minute with a burst of 10, WebSocket handshakes 30/minute with a burst of 10, and other APIs 600/minute with a burst of 120. At most four password authentications execute concurrently. Exceeding limits returns HTTP 429 and `Retry-After: 3`. Health and readiness probes are exempt. State is process-local and does not replace limits for multiple instances or public ingress. Nginx limits remain independently active.

`TRUSTED_PROXIES` defaults to empty. The API counts TCP peer addresses and does not trust arbitrary client-supplied `X-Forwarded-For`. Behind Nginx or another proxy, list actual proxy-source CIDRs. A directly connected local Nginx might use `127.0.0.1/32,::1/128`. Docker-forwarded peers are usually bridge-network addresses; verify the actual network and restrict trust to the relevant dedicated proxy range. Do not use `0.0.0.0/0` or `::/0`. Without configuration, users may share upstream quotas. With configuration, counting uses the first untrusted address from right to left.

`ALLOWED_ORIGINS` defaults to empty. Native Android requests normally send no Origin and need no entry. Browser requests or WebSocket requests carrying Origin must exactly match a complete HTTPS origin from the comma-separated list, without a path or trailing slash. Disallowed origins return 403. Development and test environments may use HTTP origins. CORS does not replace access-token authentication.

For a database reached over another host's network, configure PostgreSQL TLS and certificate validation. Example `sslmode=disable` is only for the same deployment's container network without a published host port. Keep JWT secrets, database passwords, management-session URLs, and backups in administrator-controlled private locations. Configuration and local automated checks do not establish public TLS, certificate renewal, external access, or real-device acceptance.
