# Security hardening notes

Record of the security-driven changes in commit `d2f6f64` and what's intentionally left for later. Read this before changing anything in `KeychainHelper`, `DeviceFlowManager`, `GitHubAPIClient`, or the mock server — the choices below are load-bearing.

## Threat model

Vigil-ant holds GitHub OAuth `access_token` + `refresh_token` with the GitHub App's granted scopes (Actions read, Commit statuses read, Metadata read). The relevant adversaries:

- **Local user-space attacker** — code running as the same macOS user (malicious LaunchAgent, compromised shell rc, sibling app). No root, no entitlements. Most realistic threat.
- **Lost/stolen device** — attacker has physical access, may bypass screen lock or cold-boot the keychain DB.
- **Network-adjacent attacker** — same WiFi as the developer running the mock server, or someone able to MITM the API calls if cert validation fails.
- **Log scavenger** — anyone with read access to the unified log store, sysdiagnose bundles, or Console.app output.

Out of scope: a privileged attacker (root, kernel, or with `com.apple.private.*` entitlements) — they can read any keychain item regardless of accessibility class.

## Hardening applied

### 1. OAuth response bodies no longer logged

`Packages/GitHubKit/Sources/GitHubKit/DeviceFlowManager.swift`

`pollForToken` and `refreshToken` previously logged the raw response body with `privacy: .public`. The body literally contains `access_token` / `refresh_token` JSON, so tokens were being written to the unified log store, sysdiagnose bundles, and `log stream` output. Both sites now decode first and log only the OAuth `error` field (e.g. `authorization_pending`, `slow_down`, `none`). `requestDeviceCode` similarly only logs the HTTP status code on success.

**Rule for future log additions:** never interpolate a raw response body or auth header into `os_log` with `privacy: .public`. If you must debug a body, do it locally and don't commit the line.

### 2. `GITHUB_BASE_URL` env override is `#if DEBUG` only

`Packages/GitHubKit/Sources/GitHubKit/GitHubAPIClient.swift`, `DeviceFlowManager.swift`

The env var exists so developers can point the app at `scripts/mock-github-server.py`. Without the gate, a local attacker who can set process env (LaunchAgent, shell rc, `launchctl setenv`) could silently route every OAuth request and API call to a server they control. Release builds compile out the override entirely — the production binary always hits `api.github.com` / `github.com`.

If you need to add another env-driven config knob, follow the same pattern: wrap reads in `#if DEBUG`, default to the production value otherwise.

### 3. Keychain items pinned to `WhenUnlockedThisDeviceOnly`

`App/Utilities/KeychainHelper.swift`

Both `save(token:)` and `saveRefreshToken(_:)` now set:

```swift
kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
```

Practical effect: tokens are excluded from iCloud Keychain sync, encrypted backups, and Migration Assistant transfers. They never leave this Mac. The user re-auths on a new device — fast (device flow) and re-establishes a clean trust boundary.

Existing tokens written before this change keep their old accessibility attribute until the next refresh cycle (which calls `SecItemDelete` then `SecItemAdd` with the new attribute). No explicit migration is needed; tokens roll over on their own within hours of normal use.

**Don't add `kSecAttrAccessControl` with `.userPresence`** — it would prompt for Touch ID / password on every poll, which is unworkable for a background menu bar app.

### 4. Verification URI host validated in release builds

`Packages/GitHubKit/Sources/GitHubKit/DeviceFlowManager.swift`

GitHub's device-code response includes `verification_uri` which the user opens in a browser. After decoding, release builds enforce:

```swift
guard let host = decoded.verificationURI.host,
      host == "github.com" || host.hasSuffix(".github.com") else {
    throw DeviceFlowError.requestFailed("Invalid verification URI host")
}
```

Defense in depth against a server that lies about the verification URL. The suffix check accepts subdomains (in case GitHub moves device flow to e.g. `auth.github.com`) and rejects look-alikes like `github.com.evil.example`. Wrapped in `#if !DEBUG` so the test suite can use mock URIs.

### 5. Mock server bound to loopback

`scripts/mock-github-server.py`

Was binding to `("", port)` with `AF_INET6` dual-stack — reachable from the entire LAN. Now binds to `127.0.0.1` only. Mock-only credentials, but no reason to ever expose this beyond loopback.

## Known gaps (deferred)

These came up in the red team review and were not fixed. Documented here so future maintainers know they're conscious choices, not oversights.

- **No certificate pinning.** URLSession uses the system CA store. A compromised local CA (corporate proxy, malware-installed root) can MITM `api.github.com`. Pinning would help but adds operational overhead (rotating pins, breaking on legitimate cert changes). Lower priority now that the env-var override is closed. (tracked in #49)
- **Keychain refresh failures are logged but not surfaced to the user.** The earlier `try?`-swallow was fixed in commit `3c9a255`: every Keychain call site in `App/` now uses `try`, and the token-refresh path wraps them in a `do/catch` that logs `logger.warning("Token refresh failed...")`, so failures are no longer silently dropped. As before, the refresh token is saved before the access token so the old refresh remains valid on partial failure. The remaining nuance is UX, not security: these logged failures aren't yet surfaced to the user via UI or notification (tracked in #50).
- **No URL scheme handler audit needed** — the app doesn't register one.
- **No formal GitHub Actions workflow audit.** A quick pass over `.github/workflows/ci.yml` and `release.yml` found no current injection vector: neither uses `pull_request_target`, and no untrusted `${{ github.event.* }}` value is interpolated into a `run:` step. The risk is forward-looking only. Before adding any workflow that runs on `pull_request_target` or consumes PR-controlled strings, review it for script injection. A formal audit is tracked in #51.

## Reviewing future changes

When touching auth, polling, or logging, ask:

1. Could this write a token, refresh token, or auth header anywhere outside Keychain (logs, files, network requests to non-GitHub hosts, `UserDefaults`)?
2. Does this introduce a new env-var / config knob that an unprivileged local process could influence?
3. Does this loosen the Keychain accessibility class, sync scope, or access control?
4. Does this trust a server-supplied URL, host, or path without validation?

If any answer is yes, the change needs more thought than a typical PR.
