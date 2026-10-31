[简体中文](SERVER_MANAGER.md) | English

# Server bundles and command-line entry points

See [local server management](SERVER_MANAGEMENT.en.md) for building and configuring the current management UI, backup, isolated restoration, and troubleshooting. This document retains launcher scripts and account management commands for published server bundles and applies to bundles containing those files. Consult each release's asset list to determine whether it supplies server bundles.

`v0.3.0-preview.1` provides Windows/Linux x86-64 server bundles. Run `launch-manager.cmd` or `launch-manager.sh` from the bundle root to start the local manager. Use `--data-dir` for a separate data directory. Do not copy only the manager executable; retain configuration, deployment files, and tool directories together.

The Docker configuration in source builds the current Go source by default. Bundles produced by `scripts/package_server.py` derive their Compose configuration to use `Dockerfile.prebuilt` and `linux/amd64`, running the supplied `prebuilt/` programs without changing the input source snapshot. `SOURCE_MANIFEST.json` identifies build inputs; `SERVER_PACKAGE.json` records the derived configuration; `SERVER_MANIFEST.json` identifies the final bundle files. Before building or running independently, verify the target OS, architecture, and [build requirements](BUILDING.en.md).

## Run the API from a bundle

The bundled `run-server.cmd` and `run-server.sh` can read `data/api.env`, generated during GUI initialization, and run the API in the foreground. Custom configuration paths and migration-only mode:

```powershell
./run-server.cmd -ConfigFile D:/PactickData/api.env
./run-server.cmd -ConfigFile D:/PactickData/api.env -MigrateOnly
```

```bash
./run-server.sh --config-file /home/operator/.local/share/pactick-server/api.env
./run-server.sh --config-file /home/operator/.local/share/pactick-server/api.env --migrate-only
```

The Windows script requires PowerShell. Configuration is parsed as literal `KEY=value` without executing shell expressions. The GUI does not take over APIs started externally. Stop those processes and other writers using the same database before migration.

## One-click account creation

After database migration, open “Create account”, enter an email, and select “Create account”. The display name defaults to the portion before `@`. GUI defaults are time zone `Asia/Shanghai`, locale `zh-CN`, and Monday as the first weekday. Leaving the password blank generates 24 random bytes encoded as a 32-character Base64URL password, shown only once after successful creation. Custom passwords must meet the server's 10–1024-byte requirement. Duplicate emails return an error without overwriting existing accounts.

The GUI accesses the database directly in local mode and calls `/admin create-account` inside the container in Docker mode. Both reuse server validation and Argon2id hashing. Neither temporarily enables public registration nor creates device registrations, refresh tokens, or login sessions. The Android client subsequently signs in normally with email and password; device registration occurs at login.

Accounts can also be created from the command line. Local `bin/admin[.exe] create-account` reads a single UTF-8 JSON object from standard input and connects through environment variable `DATABASE_URL`. Do not pass passwords as command arguments. The following password-free examples generate a random password:

```bash
printf '%s\n' '{"email":"name@example.com","time_zone":"Asia/Shanghai","locale":"zh-CN"}' | ./bin/admin create-account
```

```powershell
'{"email":"name@example.com","time_zone":"Asia/Shanghai","locale":"zh-CN"}' | ./bin/admin.exe create-account
```

Run these commands from the bundle root after setting `DATABASE_URL` in the current process. CLI defaults are UTC and Monday. Success exits 0 and outputs `ok/user/generated_password`, omitting the last field for custom passwords. Failure exits nonzero and outputs a stable `error.code` and a credential-free message. Inputs over 32 KiB, unknown fields, multiple JSON objects, invalid user data, unavailable databases, and incomplete migrations fail. GUI requests are limited to 16 KiB.
