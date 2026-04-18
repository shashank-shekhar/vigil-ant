#!/usr/bin/env python3
"""
Mock GitHub API server for local testing of Vigil-ant.

Emulates the GitHub API endpoints used by the app, returning responses
based on a naming convention: repos named *-success, *-failure, *-running,
or *-noworkflows get the corresponding CI status.

Usage:
    # Per-account specs: NsNfNrNn (success/failed/running/noworkflows)
    python3 scripts/mock-github-server.py "3s2f1r1n" "3s2f1r" "10f"

    # Simple mode (distributed round-robin):
    python3 scripts/mock-github-server.py --accounts 2 --success 3 --failed 2

Then run the app with:
    GITHUB_BASE_URL=http://localhost:8787 open Vigilant.app
"""

import argparse
import json
import re
import time
from datetime import datetime, timezone, timedelta
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs


# ---------------------------------------------------------------------------
# Mock data generation
# ---------------------------------------------------------------------------

ACCOUNT_NAMES = [
    "acme-corp", "side-projects", "moonlighting-industries",
    "dev-team", "infra-ops", "data-eng",
]

REPO_PREFIXES = [
    "api-gateway", "dashboard", "auth-service", "mobile-app",
    "data-pipeline", "web-client", "analytics", "notifications",
    "billing", "search-service", "media-proxy", "admin-panel",
    "sdk-python", "docs-site", "infra-config", "ci-tools",
]

# Generated at startup
accounts = []   # list of {id, login, name, token, repos}
all_repos = {}  # full_name -> repo_dict


def parse_account_spec(spec):
    """Parse a spec like '3s2f1r1n' into status counts."""
    counts = {"success": 0, "failure": 0, "running": 0, "noworkflows": 0}
    key_map = {"s": "success", "f": "failure", "r": "running", "n": "noworkflows"}
    for match in re.finditer(r"(\d+)([sfrn])", spec):
        count, key = int(match.group(1)), key_map[match.group(2)]
        counts[key] = count
    return counts


def generate_mock_data(account_specs):
    """Build accounts and repos from per-account specs."""
    global accounts, all_repos

    repo_id = 900_000
    prefix_idx = 0

    for acct_idx, spec in enumerate(account_specs):
        org = ACCOUNT_NAMES[acct_idx % len(ACCOUNT_NAMES)]
        acct = {
            "id": 800_000 + acct_idx,
            "login": org,
            "name": org.replace("-", " ").title(),
            "token": f"mock-token-{acct_idx}",
            "repos": [],
        }

        # Build status list for this account
        statuses = (
            ["success"] * spec["success"]
            + ["failure"] * spec["failure"]
            + ["running"] * spec["running"]
            + ["noworkflows"] * spec["noworkflows"]
        )

        for i, status in enumerate(statuses):
            prefix = REPO_PREFIXES[prefix_idx % len(REPO_PREFIXES)]
            prefix_idx += 1
            name = f"{prefix}-{status}"
            full_name = f"{org}/{name}"

            repo = {
                "id": repo_id,
                "full_name": full_name,
                "name": name,
                "owner": org,
                "default_branch": "main",
                "private": i % 3 == 0,
                "pushed_at": (datetime.now(timezone.utc) - timedelta(hours=i)).strftime("%Y-%m-%dT%H:%M:%SZ"),
                "status": status,
            }
            repo_id += 1
            acct["repos"].append(repo)
            all_repos[full_name] = repo

        accounts.append(acct)


def get_account_for_token(token):
    """Find the account matching a Bearer token."""
    for acct in accounts:
        if acct["token"] == token:
            return acct
    return None


# ---------------------------------------------------------------------------
# Response builders
# ---------------------------------------------------------------------------

def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def past_iso(minutes):
    dt = datetime.now(timezone.utc) - timedelta(minutes=minutes)
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def build_repo_response(repo):
    """GitHub /user/repos item."""
    return {
        "id": repo["id"],
        "full_name": repo["full_name"],
        "name": repo["name"],
        "default_branch": repo["default_branch"],
        "private": repo["private"],
        "pushed_at": repo["pushed_at"],
        "owner": {"login": repo["owner"]},
    }


def build_workflow_run(repo):
    """Single workflow run for /actions/runs."""
    status_map = {
        "success":  ("completed", "success"),
        "failure":  ("completed", "failure"),
        "running":  ("in_progress", None),
    }
    run_status, conclusion = status_map.get(repo["status"], ("completed", "success"))

    run = {
        "id": repo["id"] * 10,
        "status": run_status,
        "conclusion": conclusion,
        "html_url": f"https://github.com/{repo['full_name']}/actions/runs/{repo['id'] * 10}",
        "head_branch": repo["default_branch"],
        "path": ".github/workflows/ci.yml",
        "created_at": past_iso(30),
        "updated_at": past_iso(5) if conclusion else now_iso(),
        "run_started_at": past_iso(28),
    }
    return run


def build_workflows_response(repo):
    """Response for /actions/workflows."""
    if repo["status"] == "noworkflows":
        return {"total_count": 0, "workflows": []}
    return {
        "total_count": 1,
        "workflows": [{
            "id": repo["id"] * 100,
            "name": "CI",
            "path": ".github/workflows/ci.yml",
            "state": "active",
        }],
    }


def build_combined_status(repo):
    """Response for /commits/{ref}/status."""
    return {
        "state": "success" if repo["status"] != "failure" else "failure",
        "statuses": [],
        "sha": "abc123def456",
    }


# ---------------------------------------------------------------------------
# HTTP handler
# ---------------------------------------------------------------------------

# Track which device code maps to which account (round-robin)
device_code_counter = 0


class MockGitHubHandler(BaseHTTPRequestHandler):
    """Handles GitHub API requests using mock data."""

    def log_message(self, format, *args):
        # Terse logging
        print(f"  {self.command} {self.path} -> {args[1] if len(args) > 1 else '?'}")

    def _send_json(self, data, status=200):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("X-RateLimit-Remaining", "4999")
        self.send_header("X-RateLimit-Reset", str(int(time.time()) + 3600))
        self.end_headers()
        self.wfile.write(body)

    def _get_token(self):
        auth = self.headers.get("Authorization", "")
        if auth.startswith("Bearer "):
            return auth[7:]
        return None

    def _read_body(self):
        length = int(self.headers.get("Content-Length", 0))
        return self.rfile.read(length).decode() if length else ""

    # -- Routing --

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/")

        if path == "/user":
            self._handle_user()
        elif path == "/user/repos":
            self._handle_user_repos()
        elif re.match(r"^/repos/[^/]+/[^/]+/actions/workflows$", path):
            self._handle_workflows(path)
        elif re.match(r"^/repos/[^/]+/[^/]+/actions/runs$", path):
            self._handle_runs(path)
        elif re.match(r"^/repos/[^/]+/[^/]+/commits/[^/]+/status$", path):
            self._handle_commit_status(path)
        else:
            self._send_json({"message": "Not Found"}, 404)

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/")
        body = self._read_body()

        if path == "/login/device/code":
            self._handle_device_code(body)
        elif path == "/login/oauth/access_token":
            self._handle_access_token(body)
        else:
            self._send_json({"message": "Not Found"}, 404)

    # -- Auth endpoints --

    def _handle_device_code(self, body):
        global device_code_counter
        acct_idx = device_code_counter % len(accounts)
        device_code_counter += 1
        print(f"  → Issuing device code for account {acct_idx}: {accounts[acct_idx]['login']}")
        self._send_json({
            "device_code": f"mock-device-code-{acct_idx}",
            "user_code": f"MOCK-{acct_idx:04d}",
            "verification_uri": "https://github.com/login/device",
            "expires_in": 900,
            "interval": 1,
        })

    def _handle_access_token(self, body):
        params = parse_qs(body)
        grant_type = params.get("grant_type", [""])[0]

        if grant_type == "refresh_token":
            # Token refresh — return the same token
            refresh_token = params.get("refresh_token", ["mock-refresh-0"])[0]
            # Parse account index from refresh token
            match = re.search(r"(\d+)", refresh_token)
            idx = int(match.group(1)) if match else 0
            acct = accounts[idx % len(accounts)]
            self._send_json({
                "access_token": acct["token"],
                "token_type": "bearer",
                "refresh_token": f"mock-refresh-{idx}",
                "expires_in": 28800,
            })
            return

        # Device code grant — extract account index from device code
        device_code = params.get("device_code", ["mock-device-code-0"])[0]
        match = re.search(r"(\d+)", device_code)
        idx = int(match.group(1)) if match else 0
        acct = accounts[idx % len(accounts)]

        self._send_json({
            "access_token": acct["token"],
            "token_type": "bearer",
            "refresh_token": f"mock-refresh-{idx}",
            "expires_in": 28800,
        })

    # -- API endpoints --

    def _handle_user(self):
        token = self._get_token()
        acct = get_account_for_token(token)
        if not acct:
            self._send_json({"message": "Bad credentials"}, 401)
            return
        self._send_json({
            "login": acct["login"],
            "id": acct["id"],
            "name": acct["name"],
        })

    def _handle_user_repos(self):
        token = self._get_token()
        acct = get_account_for_token(token)
        if not acct:
            self._send_json({"message": "Bad credentials"}, 401)
            return
        repos = [build_repo_response(r) for r in acct["repos"]]
        self._send_json(repos)

    def _handle_workflows(self, path):
        # /repos/{owner}/{repo}/actions/workflows
        parts = path.split("/")
        full_name = f"{parts[2]}/{parts[3]}"
        repo = all_repos.get(full_name)
        if not repo:
            self._send_json({"message": "Not Found"}, 404)
            return
        self._send_json(build_workflows_response(repo))

    def _handle_runs(self, path):
        # /repos/{owner}/{repo}/actions/runs
        parts = path.split("/")
        full_name = f"{parts[2]}/{parts[3]}"
        repo = all_repos.get(full_name)
        if not repo:
            self._send_json({"message": "Not Found"}, 404)
            return
        if repo["status"] == "noworkflows":
            self._send_json({"total_count": 0, "workflow_runs": []})
            return
        run = build_workflow_run(repo)
        self._send_json({"total_count": 1, "workflow_runs": [run]})

    def _handle_commit_status(self, path):
        # /repos/{owner}/{repo}/commits/{ref}/status
        parts = path.split("/")
        full_name = f"{parts[2]}/{parts[3]}"
        repo = all_repos.get(full_name)
        if not repo:
            self._send_json({"message": "Not Found"}, 404)
            return
        self._send_json(build_combined_status(repo))


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def print_summary():
    print("\n" + "=" * 60)
    print("Mock GitHub Server — Generated Data")
    print("=" * 60)
    for acct in accounts:
        print(f"\n  Account: {acct['name']} ({acct['login']})")
        print(f"  Token:   {acct['token']}")
        for repo in acct["repos"]:
            status_icon = {
                "success": "✓",
                "failure": "✗",
                "running": "⟳",
                "noworkflows": "—",
            }.get(repo["status"], "?")
            print(f"    {status_icon} {repo['full_name']}  [{repo['status']}]")
    print("\n" + "=" * 60)


def main():
    parser = argparse.ArgumentParser(
        description="Mock GitHub API server for Vigil-ant",
        epilog='Examples:\n'
               '  %(prog)s "3s2f1r1n" "3s2f1r" "10f"\n'
               '  %(prog)s --accounts 2 --success 3 --failed 2\n',
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("account_specs", nargs="*", metavar="SPEC",
                        help='Per-account spec: NsNfNrNn (e.g. "3s2f1r1n" = 3 success, 2 failed, 1 running, 1 noworkflows)')
    parser.add_argument("--port", type=int, default=8787, help="Port to listen on (default: 8787)")
    # Simple mode flags (used when no positional specs given)
    parser.add_argument("--accounts", type=int, default=2)
    parser.add_argument("--success", type=int, default=3)
    parser.add_argument("--failed", type=int, default=2)
    parser.add_argument("--running", type=int, default=1)
    parser.add_argument("--noworkflows", type=int, default=1)
    args = parser.parse_args()

    if args.account_specs:
        # Per-account mode
        specs = [parse_account_spec(s) for s in args.account_specs]
        if not specs:
            parser.error("At least one account spec is required")
    else:
        # Simple mode: distribute round-robin
        statuses = (
            ["success"] * args.success
            + ["failure"] * args.failed
            + ["running"] * args.running
            + ["noworkflows"] * args.noworkflows
        )
        specs = [{k: 0 for k in ("success", "failure", "running", "noworkflows")} for _ in range(args.accounts)]
        for i, status in enumerate(statuses):
            specs[i % args.accounts][status] += 1

    generate_mock_data(specs)
    print_summary()

    server = HTTPServer(("127.0.0.1", args.port), MockGitHubHandler)
    print(f"\nListening on http://127.0.0.1:{args.port} (loopback only)")
    print(f"Set GITHUB_BASE_URL=http://localhost:{args.port} in your Xcode scheme\n")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down.")
        server.server_close()


if __name__ == "__main__":
    main()
