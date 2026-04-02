# Mock GitHub Server

A local HTTP server that impersonates the GitHub API for development and UI testing. When the app is pointed at it via `GITHUB_BASE_URL`, the entire stack — auth, repo sync, polling, status display — works normally against fake data.

## Quick Start

```bash
# Start the server (per-account mode)
python3 scripts/mock-github-server.py "3s2f1r1n" "3s2f1r" "10f"

# In Xcode: Edit Scheme → Run → Arguments → Environment Variables
# Add: GITHUB_BASE_URL = http://localhost:8787

# Build and run. Add accounts through the normal UI — auth completes instantly.
```

## CLI Usage

### Per-account specs (positional args)

Each positional argument defines one account. The spec format is `NsNfNrNn`:
- `N`**s** = N success repos
- `N`**f** = N failed repos
- `N`**r** = N running repos
- `N`**n** = N repos without workflows

```bash
# Account 1: 3 success, 2 failed, 1 running, 1 no-CI
# Account 2: 3 success, 2 failed, 1 running
# Account 3: 10 failed
python3 scripts/mock-github-server.py "3s2f1r1n" "3s2f1r" "10f"
```

### Simple mode (named flags)

Repos are distributed round-robin across accounts:

```bash
python3 scripts/mock-github-server.py --accounts 2 --success 3 --failed 2 --running 1 --noworkflows 1
```

### Options

| Flag | Default | Description |
|------|---------|-------------|
| `--port` | 8787 | Port to listen on |
| `--accounts` | 2 | Number of accounts (simple mode) |
| `--success` | 3 | Success repos (simple mode) |
| `--failed` | 2 | Failed repos (simple mode) |
| `--running` | 1 | Running repos (simple mode) |
| `--noworkflows` | 1 | Repos without CI (simple mode) |

## How It Works

### Data Generation

On startup, the server generates mock accounts and repos from the CLI args. Each repo's **name encodes its status** (e.g., `api-gateway-failure`). When the app later polls `/repos/acme-corp/api-gateway-failure/actions/runs`, the server finds the repo, reads the status from the name, and returns the appropriate GitHub API response.

Accounts get sequential names from a pool (`acme-corp`, `side-projects`, `moonlighting-industries`, ...) and tokens (`mock-token-0`, `mock-token-1`, ...). Repo IDs start at 900,000 to avoid collisions with real GitHub IDs.

### Authentication

The server implements GitHub's OAuth Device Flow with instant approval:

1. `POST /login/device/code` — returns a device code immediately (round-robin: first call gets account 0, next gets account 1, etc.)
2. `POST /login/oauth/access_token` — returns an access token immediately (no polling wait)
3. `GET /user` — returns user info based on the Bearer token

Unrecognized tokens (e.g., from a real GitHub account) receive a 401, preventing real and mock data from mixing.

### API Endpoints

| Endpoint | Response |
|----------|----------|
| `GET /user/repos` | All repos for the authenticated account |
| `GET /repos/{owner}/{repo}/actions/workflows` | 1 workflow, or empty for `*-noworkflows` repos |
| `GET /repos/{owner}/{repo}/actions/runs` | Workflow run with status/conclusion from repo name |
| `GET /repos/{owner}/{repo}/commits/{ref}/status` | Combined commit status matching the repo's state |

### Status Mapping

| Repo name suffix | Workflow run status | Conclusion |
|-----------------|-------------------|------------|
| `*-success` | `completed` | `success` |
| `*-failure` | `completed` | `failure` |
| `*-running` | `in_progress` | `null` |
| `*-noworkflows` | _(no workflows returned)_ | _(N/A)_ |

## Tips

- **Resetting app state:** Run `defaults delete net.shashankshekhar.vigilant` to clear persisted accounts/repos between test sessions.
- **Adding accounts:** Each "Add Account" click in the app gets the next mock account. The server logs which account is being issued.
- **Syncing repos:** After adding accounts, go to Settings > Repositories and click the refresh button.
- **Switching back:** Remove or uncheck `GITHUB_BASE_URL` in the Xcode scheme to return to the real GitHub API.
