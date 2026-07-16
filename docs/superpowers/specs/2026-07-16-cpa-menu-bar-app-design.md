# CPA Menu Bar App Design

## Goal

Build a lightweight native macOS menu bar application for monitoring a single CPA Usage Keeper instance without keeping its dashboard open in a browser.

The application shows a configurable metric beside its menu bar icon and provides a compact native usage summary when opened. It supports either full-instance administrator access or usage scoped to one CPA API Key.

## Scope

The first release supports:

- One CPA Usage Keeper instance.
- A configurable Keeper base URL.
- One active identity, using either an administrator password or a CPA API Key.
- Secure credential storage in macOS Keychain.
- A native menu bar icon with a configurable text metric.
- A native summary popover.
- Automatic and manual refresh.
- A button that opens the complete Keeper dashboard in the default browser.
- Optional launch at login.

The first release does not support multiple saved accounts, notifications, custom date ranges, embedded dashboard pages, detailed charts, or editing Keeper data.

## Platform and Technology

The application is a native macOS application written in Swift. AppKit owns the status item, popover/window lifecycle, and application behavior. SwiftUI is used for the popover and settings views where it reduces presentation code without compromising native behavior.

The application is an accessory application and does not appear in the Dock during normal operation.

## User Experience

### Menu Bar

The menu bar item contains an icon and an optional compact metric. The default metric is today's total Token count, abbreviated with `K`, `M`, or `B` suffixes as necessary.

The configured menu bar display can be:

- Icon only.
- Today's Token count.
- Today's estimated cost.
- Today's request count.

The menu bar metric always uses the `today` API range even if the user selects a different range in the popover. This keeps the displayed value stable and predictable.

The normal icon is replaced by a warning variant when the current data is unavailable or stale because of an authentication, network, or server error. The last successful metric remains visible when possible.

### Summary Popover

Clicking the status item opens a native popover containing:

- The configured instance name derived from its host.
- A range selector for Today, Last 24 Hours, Last 7 Days, and Last 30 Days.
- Total requests.
- Total Tokens.
- Estimated cost.
- Success rate.
- Last successful refresh time.
- Current refresh or error state.
- A manual refresh action.
- An action to open the complete Keeper dashboard in the default browser.
- An action to open application settings.
- A quit action.

The popover does not embed the Keeper website.

### Settings

The settings window contains:

- Keeper URL.
- Authentication type: Administrator Password or CPA API Key.
- Credential input.
- Refresh interval.
- Menu bar metric selection.
- Launch at login toggle.

The default refresh interval is 60 seconds. Supported choices are 30 seconds, 60 seconds, 5 minutes, and 15 minutes.

Saving settings first validates the candidate configuration against the Keeper instance. The application only replaces the active configuration after validation succeeds. If validation fails, the previous working configuration and credential remain active.

On first launch, or when no valid configuration exists, opening the menu bar item presents a setup view instead of the summary.

## Authentication

CPA Usage Keeper exposes separate authentication flows that must not be treated as interchangeable credentials.

### Administrator Password

- Login endpoint: `POST /api/v1/auth/login`
- Request body: `{ "password": "..." }`
- Overview endpoint: `GET /api/v1/usage/overview?range=<range>`
- Access scope: full-instance usage.

### CPA API Key

- Login endpoint: `POST /api/v1/auth/api-key-login`
- Request body: `{ "apiKey": "..." }`
- Overview endpoint: `GET /api/v1/key-overview?range=<range>`
- Access scope: usage associated with the authenticated CPA API Key.

Both flows establish a Keeper Cookie Session. The HTTP client retains that session for subsequent requests. When a statistics request returns `401 Unauthorized`, it performs one credential-based reauthentication attempt and retries the statistics request once. A second authentication failure is surfaced to the user and automatic credential retry is suspended until settings change or the user explicitly retries.

The configured credential is stored only in macOS Keychain. The base URL, authentication type, refresh interval, menu bar display choice, and launch-at-login preference may be stored in application preferences.

Credentials, session cookies, and authentication request bodies must never be written to logs.

## Architecture

### AppDelegate and StatusItemController

Own the application lifecycle, status item, menu bar title, popover presentation, settings window, and quit behavior. They consume view state rather than performing API requests directly.

### UsagePopoverView

Render the current usage snapshot, selected range, refresh state, and user actions. It is independent of the active authentication type.

### SettingsView

Collect and validate candidate configuration. It does not persist a new credential until the API validation succeeds.

### KeeperAPIClient

Normalize the configured base URL, perform the appropriate login flow, retain cookies, call the correct overview endpoint, decode responses, and map transport or HTTP failures to application errors.

The client exposes a single overview operation to the rest of the application. Endpoint selection remains internal to the client.

### CredentialStore

Read, replace, and delete the single active credential in macOS Keychain. It exposes credential operations without leaking Keychain implementation details to views or refresh logic.

### PreferencesStore

Persist non-secret settings. It provides an immutable active configuration snapshot so a partially edited settings form cannot alter the running client.

### UsageRefreshService

Coordinate startup refresh, periodic refresh, popover-triggered refresh, manual refresh, retries, and last-known-good data. It coalesces concurrent requests so timer and user actions do not produce duplicate API calls.

### UsageSnapshot

Provide a common application model for both administrator and CPA API Key overview responses. It contains request count, Token count, cost, success rate, range, server timezone metadata, and refresh timestamp.

## Data Flow

1. The application reads the base URL and authentication type from preferences.
2. It reads the active credential from Keychain.
3. `KeeperAPIClient` authenticates using the endpoint selected by the authentication type.
4. The returned Cookie Session is retained in the client's cookie store.
5. The client requests either the administrator overview or Key-scoped overview.
6. The response is normalized into `UsageSnapshot`.
7. `UsageRefreshService` publishes the latest snapshot and retains it as last-known-good data.
8. The popover renders the selected range snapshot.
9. The status item renders a separate `today` snapshot when a daily metric is enabled.

If the popover is already showing Today, the service may share the same successful response with the status item rather than issuing a duplicate request.

## Error Handling

- Missing configuration: show setup UI.
- Invalid URL: reject settings locally before a network request.
- Connection failure or timeout: retain last-known-good data and show the service-unavailable state.
- `401 Unauthorized`: reauthenticate once and retry once.
- Repeated `401`: show an authentication error and stop automatic credential retries.
- `403 Forbidden`: show an authorization error identifying that the selected identity cannot access the requested resource.
- Other non-success status: show a server error with the status code but no sensitive response data.
- Invalid or incompatible JSON: show a compatibility error and keep the application running.
- Empty usage data: render zero values as valid data rather than as an error.

Network operations must not block the main thread. Cancellation of an obsolete range request is not presented as an error.

## Security

- Store the administrator password or CPA API Key in macOS Keychain.
- Store only one active credential.
- Delete the previous Keychain item after a new configuration is validated and committed.
- Do not include secrets or cookies in application logs, crash breadcrumbs, or UI error details.
- Do not persist overview response bodies beyond ordinary in-memory last-known-good state.
- Use the configured URL exactly as the trust boundary chosen by the user; validation confirms scheme, host, authentication, and overview access.

HTTP is permitted because the target may be a private LAN service. The settings UI warns that an HTTP connection sends credentials without transport encryption and recommends HTTPS where available.

## Refresh Behavior

- Refresh immediately after startup when a valid configuration exists.
- Refresh on the configured interval.
- Refresh when the popover opens if the relevant data is older than the configured interval.
- Allow explicit manual refresh.
- Coalesce simultaneous refresh requests for the same range.
- Use a finite request timeout.
- Apply no unbounded background retry loop.

After a transient network or server failure, the next scheduled refresh attempts recovery normally. Authentication failures require explicit retry or a settings change after the single automatic reauthentication attempt fails.

## Testing

### Unit Tests

- URL normalization and validation.
- Authentication type to login and overview endpoint routing.
- Token, request, cost, and success-rate formatting.
- `K`, `M`, and `B` menu bar abbreviation boundaries.
- Overview response normalization.
- Error classification.
- Refresh request coalescing.
- Preservation of last-known-good data.

### API Client Tests

Use a local mock HTTP server to verify:

- Administrator login and overview loading.
- CPA API Key login and scoped overview loading.
- Cookie Session retention.
- Session expiry, one reauthentication, and one request retry.
- Repeated `401`, `403`, timeout, server failure, and malformed JSON handling.
- Absence of secrets in captured log output.

### Application Behavior Tests

- First-launch setup presentation.
- Successful settings validation and persistence.
- Failed candidate settings do not replace the previous configuration.
- Status item text updates after refresh.
- Range changes update the popover without changing the daily menu bar metric.
- Warning state and last-known-good display.
- Launch-at-login preference behavior.

## Completion Criteria

The first release is complete when a user can install and launch the application, configure one Keeper URL and one supported credential type, see today's Token count in the macOS menu bar, open a native usage summary for supported ranges, recover automatically from an expired session, open the full dashboard when needed, and use the application without leaving a browser tab open.
