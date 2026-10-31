[简体中文](PROJECT_PLAN.md) | English

# Pactick roadmap

Updated: 2026-10-31. Applies to `0.3.0-preview.3+8`. See [project status](docs/PROJECT_STATUS.en.md) for implemented features and limits, and the [Android guide](docs/GETTING_STARTED.en.md) for operations.

## Implemented scope

The Android client supports local tasks, projects, plans, focus, statistics, and backups without an account. Account synchronization is optional. This version integrates English UI, free focus and first task association after a session ends, plan editing/deletion, deadline and plan-start reminders, strict mode, vibration, the private vault, the focus desktop, and system calendar connections.

Language follows the system by default. The focus desktop and system calendar are disabled by default. Ordinary workspace backup version 2 includes vault ciphertext and still accepts version 1. Credentials, local timer ownership, system calendar bindings, and the focus desktop switch do not migrate in backups.

The Go server provides authentication, synchronization, aggregate reads, account export/deletion, and local administration. Only the starting device may first assign a task to an unassigned terminal focus session; timing and reassignment remain protected. Self-hosted servers must upgrade to this source version for that operation; older prebuilt bundles lack the exception.

`website/` provides Chinese and English static website source, local preview, and fixed Release download links. It does not connect to business workspaces and is not a Web client. This task does not deploy it to a server.

## Remaining validation and maintenance

| Task | Completion criteria |
| --- | --- |
| Device validation | Record installation, upgrade, language changes, free-focus association, strict termination, ordinary/private exclusion, desktop navigation, and calendar permission/conflict behavior using the final signed APK, with device and version details |
| Background and vendor behavior | Check lock screen, reboot, force stop, power saving, real notifications, and vibration; automated tests do not replace device results |
| Synchronization and recovery | Check two-device offline conflicts, starting-device restrictions, restore, and isolation of equal user IDs on different servers against the final client/server; database tests must use a real isolated instance |
| Public deployment | Separately validate HTTPS/WSS, renewal, firewall, recovery on a new host, and monitoring; loopback health checks do not prove public deployment |
| Website maintenance | Update fixed links against actual Release assets; check both languages, narrow screens, keyboard use, and no-JavaScript behavior; deployment requires a separate task |

Results apply only to their recorded source, artifacts, and environment. Historical preview.2 single-device results do not cover this version's new features. Release notes state completed checks and remaining gaps; prerelease status does not substitute for validation.

## Maintenance scope and release constraints

The maintainer provides no public synchronization service. Android is the current client platform. Windows/Linux administration programs are server software, not desktop task clients. Payments, trials, activation, team collaboration, app-store submission, and other client platforms are outside this scope.

Prepare reviewed source, a production-signed APK, and checksums under the [release process](docs/RELEASING.en.md). Public Releases do not include raw JSON, internal reports, or logs by default. Necessary project JSON remains inside the source archive. Local database backups do not cover loss of the host or disk; deployers must arrange off-host copies and recovery exercises.

Maintenance prioritizes data loss and security issues, core defects, usability, then features, without a fixed response-time commitment.
