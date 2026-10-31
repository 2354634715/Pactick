[简体中文](SERVER_MANAGEMENT.md) | English

# Local server management UI

`cmd/manager` starts a local browser management UI on Windows and Linux. It supports configuration, database initialization, migration, API start/stop/restart, health checks, logs, database backup, isolated restore checks, and ordinary user account creation.

The UI listens only on `127.0.0.1`, using a random port by default. The API defaults to `127.0.0.1:8080`. Closing the manager stops native API processes it started; Docker API and PostgreSQL containers keep running. Closing a browser tab does not stop the manager.

## Build and start

Use the Go version required by the project's `go.mod`. Run in PowerShell from the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build_server_tools.ps1
.\output\server-tools\windows-amd64\bin\manager.exe `
  --bundle-dir . `
  --binary-dir output/server-tools/windows-amd64/bin `
  --data-dir output/server-data
```

The script writes five command binaries to `output/server-tools/<target>/bin/`. It starts no service, changes no database, and uploads no files. Use `-Targets windows-amd64` to build one target. `--bundle-dir` is the complete source directory containing `go.mod`, `Dockerfile`, and `deploy/desktop/compose.yaml`. `--binary-dir` selects native tools and defaults to `bin` under `--bundle-dir`. The source path may contain spaces.

Linux example:

```bash
chmod +x output/server-tools/linux-amd64/bin/*
output/server-tools/linux-amd64/bin/manager \
  --bundle-dir . --binary-dir output/server-tools/linux-amd64/bin \
  --data-dir "$HOME/.local/share/pactick-server"
```

`--data-dir` defaults to `data` under the source or bundle root. `--listen 127.0.0.1:<fixed-port>` fixes the management port; other listening addresses are rejected. With no available desktop browser, add `--no-browser` and open the printed address in a browser on that host. For ordinary remote Linux administration, use the [self-hosting guide](SELF_HOSTING.en.md). Do not expose the management page publicly.

| Build target | Manager/API modes | Prerequisites |
| --- | --- | --- |
| `windows/amd64` | Native process or Docker | Local PostgreSQL, or Docker Desktop and Compose v2 |
| `linux/amd64` | Native process or Docker | Local PostgreSQL, or Docker Engine and Compose v2 |
| `windows/386` | Native process | 32-bit Windows execution environment and reachable PostgreSQL |
| `linux/386` | Native process | 32-bit Linux execution environment and reachable PostgreSQL |

The 386 manager has no Docker mode. Cross-compilation only checks whether target code builds; it does not establish behavior on the OS and CPU. Accept runtime operation separately for all four targets. Implementation of this feature does not mean installation packages for those platforms have been published.

## Select an operating mode

Open “Runtime configuration” on first use.

1. Docker mode builds the current source's API image and starts PostgreSQL in a separate Compose project. First use requires access to build and database images. The project ID, JWT secret, and database password are generated initially, saved in the data directory, and reused. This mode uses PostgreSQL 17 without publishing its database port.
2. Native mode connects to existing PostgreSQL. Enter a `postgres://` or `postgresql://` connection address and save. For a database on another host, use PostgreSQL TLS options such as `sslmode=verify-full` according to its certificate configuration. The database user needs migration privileges. Deployment, migration, and native backup need `pg_dump`; isolated restore checks require `pg_restore` and `CREATEDB`. Programs are found through `PATH`.
3. By default the API listens only on loopback. Selecting `0.0.0.0` exposes plaintext API listening on all interfaces; use it only on networks protected by a firewall and separate HTTPS/WSS reverse proxy. Clients still require HTTPS. For public deployments, use the proxy configuration in [self-hosting](SELF_HOSTING.en.md). Never expose this HTTP port directly to the public network.
4. After saving, select “Deploy and start”. The manager initializes or validates the database, then awaits API `/readyz`. It fails if readiness is not reached within 45 seconds. The process or container may still be running; inspect logs.

Configuration cannot change while the API is running. An initialized data directory cannot switch operating mode or database; use a separate directory for another instance. The manager does not take over native APIs started elsewhere. If a port is occupied, stop the external service or select another port. It installs no Windows Service or systemd unit and changes no firewall rules.

## Service operations and failures

“Stop API” preserves PostgreSQL, volumes, configuration, and backups. “Restart API” stops and restarts the same instance and rechecks readiness. Linux native processes receive an interrupt and are forcibly terminated if they have not exited after 15 seconds. Windows native processes are terminated directly; avoid frequent stops or restarts during writes. Docker stop uses Compose's stop grace period.

After updating source or programs, back up first, then select “Run migrations and start”. The manager makes a separate database backup before both first initialization and subsequent migrations. Backup failure prevents migration. Migration stops the API and writes `.migration-pending` in the data directory. On failure the marker remains, and ordinary startup, restart, and repeated deployment are rejected. Inspect logs and backups before retrying explicit migration. The manager neither rolls back committed database changes nor automatically restores the production database. The administrator must separately stop other writers using the same database.

The log page shows the last 100 Docker API/PostgreSQL lines or the last 64 KiB of native `server.log`, replacing currently known configuration secrets. Log files do not rotate automatically; arrange native log retention separately. Do not upload application logs, the data directory, or database connection addresses publicly.

## Create accounts

“Create account” writes an ordinary user directly through the trusted database administration path without changing `REGISTRATION_ENABLED=false`. It creates no device, access token, or refresh token. The client registers a device and establishes a session at first login. A duplicate email fails without changing its password or profile.

Email is required. Display name defaults to the part before `@`. The CLI defaults to time zone `UTC`, while the management page prefills `Asia/Shanghai`. Locale defaults to `zh-CN`, and the week starts on Monday. Custom passwords are 10–1024 bytes and use the same Argon2id hash as login. A blank password generates a 24-byte random value encoded as a 32-character password, returned only in that successful result. The server stores no plaintext; it cannot be retrieved again after page refresh.

Standalone `cmd/admin` requires neither the manager nor public registration. It accepts only one UTF-8 JSON object on standard input, at most 32 KiB. The database schema must already be migrated. Do not place passwords in command arguments. Supplying only an email and letting the program generate a password is recommended:

```powershell
# Supply DATABASE_URL through the current process environment or protected operations configuration.
'{"email":"member@example.com","time_zone":"Asia/Shanghai"}' |
  .\output\server-tools\windows-amd64\bin\admin.exe create-account
```

Linux/Docker administrators can keep public registration closed and use `/admin create-account` in the running API container. See [self-hosting](SELF_HOSTING.en.md#3-create-an-initial-account-and-close-registration). Results include generated passwords; protect terminal output and redirected files as credentials. Errors include only safe codes and messages. Argument errors exit 2, creation failures exit 1, and success exits 0.

## Backup and restore checks

“Back up database” produces a PostgreSQL custom-format archive and `.sha256` under the data directory's `backups/`. Names include UTC time and a random suffix and do not overwrite existing files. The manager does not automatically delete history. Arrange retention, disk-space monitoring, and offline copies.

“Check backup restoration” accepts only manager-generated filenames, regular files, and matching SHA-256 checksums. Validation failure prevents restore commands. Restore only trusted backups: PostgreSQL archives can contain database-object definitions that execute code. Hashes verify integrity, not provenance.

- Native mode creates a new randomly named database, runs `pg_restore --exit-on-error --no-owner --no-privileges`, checks the current program's migration ledger and account table, and drops the temporary database.
- Docker mode creates a separate PostgreSQL 17 container and volume without networking, restores the archive through standard input, checks that the migration ledger and account table are readable, and removes the temporary container and volume.
- Cleanup is attempted even after failure. Cleanup failure returns the target name; the administrator should inspect and remove that temporary database, container, or volume.

A restore check does not overwrite the current database, switch clients, or restore the live service, and does not replace full disaster-recovery acceptance. See [self-hosting](SELF_HOSTING.en.md#5-backup-and-restoration) for actual database restoration. See the [official pg_restore documentation](https://www.postgresql.org/docs/current/app-pgrestore.html) for archive and restore behavior.

## Local access protection

Each manager startup generates a 32-byte random session token and passes it to the page through a URL fragment. The page stores it in that tab's sessionStorage and removes the fragment from the address bar. API requests require the token. Writes also require a separate random CSRF token and exact Origin. Host must match the current loopback listener. The page uses restrictive CSP and rejects cross-site framing. Restarting the manager invalidates tokens.

A process lock permits only one manager per data directory. Linux configuration and backups use 0600 files and 0700 directories. Windows restrictions also depend on inherited directory ACLs; place data in the current administrator's private directory. Trusted local processes and users able to read the management URL or data directory can still administer the instance. Do not expose the management port to other users through a reverse proxy, shared tunnel, or port forwarding.
