# Vigil-ant

A macOS menu bar app that keeps an eye on your GitHub CI/CD so you don't have to.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange)

## What It Does

You know that feeling when a build has been broken for an hour and nobody noticed? Vigil-ant fixes that. It lives in your menu bar, quietly polling your GitHub repos, and shows a badge with the number of failing builds. When something breaks, you'll know right away.

- **Menu bar badge** — Failing build count, always visible
- **Multi-account** — Personal, work, side projects — monitor them all
- **GitHub Actions** — Get information about the last run and its state
- **Smart polling** — Configurable intervals (1–10 min) with ETag caching so you won't burn through your rate limit
- **Notifications** — macOS alerts when builds break
- **Keyboard shortcut** — Customizable global hotkey to pull up the status popover
- **Auto-updates** — Stays current via Sparkle

## Installation

Grab the latest release from the [Releases](https://github.com/shashank-shekhar/vigil-ant/releases) page.

## Setup

1. **Launch** — The app appears in your menu bar
2. **Sign in** — Click the gear icon → Accounts → Sign in with GitHub
3. **Pick repos** — Head to the Repositories tab and turn on monitoring for the repos you care about

Authentication uses GitHub's Device Flow — you authorize in your browser, the app gets a read-only token. No secrets, no callback servers, no fuss.

## Usage

- **Click the menu bar icon** to see your repos and their status
- **Click a repo** to jump straight to it on GitHub
- **Click Refresh** to check right now instead of waiting for the next poll
- **Open Settings** to manage accounts, repos, and preferences

| Settings Tab | What's There |
|---|---|
| Accounts | Add or remove GitHub accounts |
| Repositories | Toggle monitoring per repo |
| General | Poll interval, launch at login, notifications, shortcut, updates |
| About | Version and links |

---

## Development

### Requirements

- macOS 14+
- Xcode 15+ (Swift 5.9+)

### Build from Source

```bash
git clone https://github.com/shashank-shekhar/vigil-ant.git
cd vigil-ant
open Vigilant/Vigilant.xcodeproj
```

Build and run from Xcode. You'll need a `Secrets.xcconfig` with your GitHub App Client ID and Sparkle public key — see `Secrets.xcconfig.template` for the format.

### Project Structure

```
├── App/                 # SwiftUI views, AppState, utilities
├── Packages/
│   ├── GitHubKit/       # GitHub API client, device flow auth, data models
│   └── CIStatusKit/     # Polling engine, status aggregation
├── Vigilant/            # Xcode project, Info.plist, assets
└── scripts/             # Icon generation, mock server
```

**GitHubKit** handles all GitHub communication — the API client (`GitHubAPIClient`, an actor), OAuth device flow (`DeviceFlowManager`), and response models. **CIStatusKit** owns the polling loop (`StatusPoller`) and merges Actions + commit status into a single severity-ranked `BuildStatus`. The **App** layer ties it together with `AppState`, which orchestrates polling, persistence, and notifications.

### Testing

The two packages have their own test suites using Swift Testing (`@Test` macros):

```bash
cd Packages/GitHubKit && swift test
cd Packages/CIStatusKit && swift test
```

### Local Mock Server

For UI testing without hitting GitHub, there's a mock server that emulates the full API:

```bash
# 3 accounts: first has 3 success + 2 failed + 1 running + 1 no-CI, etc.
python3 scripts/mock-github-server.py "3s2f1r1n" "3s2f1r" "10f"
```

Set `GITHUB_BASE_URL=http://localhost:8787` in your Xcode scheme, then add accounts through the normal UI — auth completes instantly. See [MOCK_SERVER.md](MOCK_SERVER.md) for the full details.

## License
MIT

## Contributing

Contributions welcome — open an issue or send a PR.
