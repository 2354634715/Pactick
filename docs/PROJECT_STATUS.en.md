[简体中文](PROJECT_STATUS.md) | English

# Features and validation status

Reviewed: 2026-10-31. Applies to `0.3.0-preview.3+8`. This document describes the integrated source for this version. Other worktrees, old APKs, and historical logs do not replace validation of the final candidate. See the [getting started guide](GETTING_STARTED.en.md).

## Features and defaults

| Feature | Implemented behavior and defaults | Main limits |
| --- | --- | --- |
| Language and UI | Follow system by default, with Chinese/English choices; phone navigation is Focus, Today, Tasks, Calendar, Statistics, opening Today | User content stays unchanged; wider Rail/Drawer layouts retain their original order |
| Tasks and plans | Priority ordering, creation, editing, and completion; plans can be added, edited, or deleted | Deleting a plan retains tasks and focus history; no complete ordinary task deletion, tag-management, or recurrence-editor UI |
| Free focus | Start without a task; first associate an existing/new task from review or history after ending | Association is one-time and cannot be cleared or reassigned; timing and pauses stay unchanged; synchronized records require the starting device |
| Normal, guard, strict | Timing continues after the target; strict mode blocks pause and early completion and requires at least 30 seconds plus a reason for emergency termination | Guard requires system permissions; it is not an application lock and cannot prevent force stop |
| Feedback and reminders | Pending-count notifications, deadline/plan-start reminders, and vibration are enabled by default with device-local switches | Inexact alarms may be delayed; private records do not participate in ordinary reminders |
| Focus desktop | Disabled by default; opening a new session or resuming can open it automatically; manual entry is available | Lists Pactick, system apps, and the current whitelist; does not replace the launcher, isolate apps, or block Home/Recents |
| System calendar | Disabled by default; per-workspace connections, 30 past/180 future days; read-only or two-way ordinary plan title/time/time-zone exchange | Requests permissions as needed; conflicts and one-sided deletion require choices; excludes vault, deadlines, and focus; no guaranteed immediate background or provider-network sync |
| Private vault | Separate workspace password, authenticated encryption, local plans/normal focus, and ciphertext backups | Excluded from ordinary sync/search/statistics; lost passwords cannot be recovered; moving data does not erase previously externalized plaintext |
| Workspace backup | Version 2, accepts version 1, maximum 50 MiB; transactional restore into a new workspace | Ordinary content remains plaintext; vault content is ciphertext; excludes credentials, timer ownership, calendar bindings, and desktop preference |
| Server and website | Go authentication/sync/admin tools; Chinese/English static website source and local preview | First terminal association requires this server source; no new prebuilt server assets or website deployment in this release |

See [focus modes](FOCUS_MODES.en.md), [system calendars](SYSTEM_CALENDAR.en.md), [private vault](PRIVATE_TASK_VAULT.en.md), and [backups](LOCAL_BACKUPS.en.md) for detailed rules.

## Compatibility and validation scope

First task association for terminal focus is a new server exception. Older servers reject it. Self-hosters should upgrade using this source version, retaining database and original workspace backups. Do not rewrite historical migrations or reuse cursors from another server. See the [entity contract](ENTITY_SCHEMAS.en.md) for fields and device restrictions.

The Release notes identify the reviewed source archive, APK, source commit, checksums, and executed checks. Build, signature, widget tests, real database checks, and device acceptance are recorded separately. Tests skipped without `PACTICK_TEST_DATABASE_URL` do not count as database validation.

Historical device results do not cover this version's desktop, calendar, language, free focus, or other merged changes. Permissions, vendor background behavior, lock screen/reboot, returning from external apps, TalkBack, two-device use, and public deployment require validation in their actual environments. See the [roadmap](../PROJECT_PLAN.en.md) for completion criteria.
