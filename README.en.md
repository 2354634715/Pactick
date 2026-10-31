[简体中文](README.md) | English

# Pactick

Pactick is a **personal hobby project** that provides local-first tasks, a calendar, and focus sessions on Android. Users can collect tasks, schedule time, start a focus session, and review time spent.

ChatGPT has participated in the development of this project.

The first release supports Android. Windows, Linux, iOS, and Web clients are outside the scope of this release.

## Installation and use

The project includes an Android client and a Go server and remains in preview. Download the corresponding version from [Releases](https://github.com/2354634715/Pactick/releases) or build it yourself. Standalone local use requires no server; deploy your own server when you need synchronization across devices.

After building, install the APK on an Android device. First launch opens a local workspace. For synchronization, enter your own HTTPS server address in Settings and sign in. See “License and contributions” below for reporting issues.

Task lists sort by priority by default: Urgent → High → Medium → Low → None. Today retains scheduling and manual order. Task reminders are enabled by default: when the system allows notifications and the current workspace has unfinished tasks, one silent notification displays only their count. It is removed when all tasks are complete and can be disabled in Settings. See the [Android getting started guide](docs/GETTING_STARTED.en.md) for operations and limitations.

The source includes free focus with first task association after ending, English support, a private vault, strict mode, a focus desktop, and system calendar connections. The desktop and calendar connections are disabled by default; see the [guide](docs/GETTING_STARTED.en.md) and [project status](docs/PROJECT_STATUS.en.md). The implemented Windows/Linux server GUI and administrator account creation are separate administration software, not desktop task clients.

## Deploy your own server

Prepare an Ubuntu/Debian host with Docker Engine, Compose v2, and systemd. Put the source in a fixed directory, such as `/opt/pactick/app`, and run the following commands from the repository root.

If you already have an HTTPS reverse proxy, use local-only mode:

```bash
sudo bash deploy/scripts/install.sh install --local-only
```

This mode listens only on the server's loopback interface. Remote clients must connect through your configured HTTPS proxy.

To have the script configure Nginx and Let's Encrypt, first install Nginx, Certbot, and gettext-base, point your domain's DNS at the server, and allow public TCP ports 80 and 443. Replace the example domain and email, then run:

```bash
sudo bash deploy/scripts/install.sh install \
  --domain api.example.com \
  --email admin@example.com \
  --accept-acme-terms
```

The API binds only to host loopback, and PostgreSQL publishes no host port. The installer generates private configuration, builds images, backs up before migration, runs migrations explicitly, starts the API, installs daily local backups, and checks readiness. Registration is disabled by default.

See the [self-hosting guide](docs/SELF_HOSTING.en.md) for account creation, registration controls, upgrades, backup, and restoration. See [deployment assets](deploy/README.en.md) for individual scripts.

## Build from source

For the Android client, run the following from the repository root. Enter the client directory, fetch dependencies, run checks and tests, and build a debug APK.

```bash
cd client
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

The output is `client/build/app/outputs/flutter-apk/app-debug.apk`. Debug packages use a development certificate and are for testing only.

For Go server development, start the development environment from the repository root, then run tests and static checks.

```bash
docker compose up --build
go test ./...
go vet ./...
```

`docker compose up --build` runs in the foreground. Once services have started, run the other two commands in a second terminal. The development topology listens at `http://localhost:8080`; production deployment uses the separate `compose.production.yaml`.

See [building](docs/BUILDING.en.md) for toolchains and production signing configuration. See [releasing](docs/RELEASING.en.md) for source snapshots, signed APKs, SHA-256 checksums, certificate fingerprints, and acceptance requirements before publication.

## License and contributions

The project uses a Source Available license. The current license permits personal use, research, self-hosting, and internal company work. Free distribution and externally accessible modified network services require corresponding source code. Selling the software, paid hosting, advertising monetization, and inclusion in external commercial products are restricted.

See the [full license](LICENSE), [license FAQ](docs/LICENSE_FAQ.en.md), and [third-party notices](THIRD_PARTY_NOTICES.en.md). Third-party components retain their respective licenses. The project owner has confirmed the current license text; the relevant third-party and distribution review must still be completed before public release.

Read the [contribution guide](CONTRIBUTING.en.md) before reporting problems or suggesting improvements. Report issues through GitHub Issues or email. Send sensitive material privately as described in [security reporting](SECURITY.en.md). Maintenance priorities are data loss and security, core functionality defects, usability, and new features, in that order. No fixed update frequency or response time is promised.

## Project documentation

- [Current roadmap](PROJECT_PLAN.en.md)
- [Android getting started guide](docs/GETTING_STARTED.en.md)
- [Android priority ordering and task reminder device checks](docs/ANDROID_TASK_REMINDER_CHECKLIST.en.md)
- [Local-first and optional synchronization architecture](docs/PROJECT_ARCHITECTURE.en.md)
- [Entity field contracts](docs/ENTITY_SCHEMAS.en.md)
- [Server architecture](docs/SERVER_ARCHITECTURE.en.md)
- [HTTP API](api/openapi.en.yaml)
- [Changelog](CHANGELOG.en.md)
