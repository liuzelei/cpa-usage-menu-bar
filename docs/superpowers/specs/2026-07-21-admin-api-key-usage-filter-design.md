# Admin API Key Usage Filter Design

## Summary

Add an API key filter to the usage popover for users authenticated with the Keeper administrator password. Administrators can switch between aggregate usage and the usage of one specific CPA API key without exposing or storing the key value.

The filter affects only the four metrics shown in the popover. The menu bar metric and token milestone celebrations always use aggregate usage for the current day.

## Goals

- Let an administrator view usage for one CPA API key in the existing popover.
- Populate the filter with labels supplied by Keeper rather than raw API key values.
- Preserve aggregate daily usage as the source for the menu bar and milestone celebrations.
- Remain compatible with Keeper versions that do not expose the API key options endpoint.
- Return to aggregate usage whenever the app starts or the configured authentication identity changes.

## Non-Goals

- Allowing a CPA API key viewer to inspect other keys.
- Displaying, transmitting beyond login, or persisting a complete CPA API key.
- Persisting the selected filter between application launches.
- Adding a separate usage window or changing the four existing popover metrics.
- Filtering milestone celebrations or the menu bar metric by CPA API key.

## Keeper API Contract

The feature uses the current Keeper administrator API:

- `GET /api/v1/usage/api-keys/options` returns `{ "options": [{ "id": "42", "label": "Primary Key" }] }`.
- `GET /api/v1/usage/overview?range=7d&api_key_id=42` illustrates the existing overview response scoped to the selected CPA API key; the app substitutes the active range and selected ID.

The app sends only the opaque numeric Key ID returned by Keeper. It does not request the settings endpoint that exposes complete key values.

The options request is made only for administrator authentication. CPA API key viewer authentication continues to use `/api/v1/key-overview` and never requests administrator-only Key metadata.

## Data Model and API Client

Add a `CPAAPIKeyOption` value containing:

- `id: String`
- `label: String`

Extend `KeeperAPIClientProtocol` with an administrator-only operation that fetches API key options. Extend overview fetching with an optional `apiKeyID`. The client appends `api_key_id` only when all of the following are true:

- authentication type is administrator password;
- the caller supplies a non-empty Key ID;
- the request targets `/api/v1/usage/overview`.

CPA API key viewer overview requests ignore the optional filter defensively and remain scoped by the authenticated Keeper session.

## Refresh Model State

`UsageRefreshModel` owns the transient filter state:

- `apiKeyOptions`: the options available to an administrator;
- `selectedAPIKeyID`: `nil` means aggregate usage;
- `isAPIKeyFilterAvailable`: true only after a successful, non-empty options response.

The model keeps aggregate and filtered data separate:

1. Every refresh fetches aggregate usage for today without `api_key_id`.
2. That aggregate snapshot updates `todaySnapshot`, the menu bar presentation, and milestone tracking.
3. When the popover selection is aggregate and its range is Today, the same aggregate snapshot also becomes `selectedSnapshot`.
4. Otherwise, the model fetches the selected page range, including `api_key_id` when a Key is selected, and uses that result only for `selectedSnapshot`.

Snapshot caching must distinguish both `UsageRange` and the optional Key ID so a filtered result cannot appear after switching back to aggregate usage or to another Key.

The selection resets to aggregate usage when:

- a model is initialized;
- configuration is saved with a different Keeper URL or authentication type;
- the configured authentication type is not administrator password;
- the selected Key is no longer available.

No filter selection is written to `UserDefaults` or Keychain.

## Popover Interaction

For an administrator, place a Key picker above the existing time range picker when `isAPIKeyFilterAvailable` is true.

The picker contains:

1. `全部用量`, represented by a `nil` Key ID.
2. One item per Keeper option, displayed using its `label`.

Changing the picker immediately refreshes the currently selected time range. During refresh, retain the last successful metrics and use the existing progress indicator. Manual and scheduled refreshes update both aggregate Today data and the currently displayed filtered data.

The Key picker is hidden for CPA API key viewer authentication, an empty options response, and unsupported Keeper versions.

## Compatibility and Error Handling

Treat `404 Not Found` and `501 Not Implemented` from the Key options endpoint as an unsupported capability. In that case:

- clear the options;
- reset the selection to aggregate usage;
- hide the picker;
- continue refreshing aggregate usage without showing a compatibility error.

An empty options response has the same visible behavior.

If a filtered overview returns `404 Not Found`, assume the selected Key was deleted or disabled. Remove the invalid selection, switch to aggregate usage, and refresh the current range once. Do not loop if the aggregate request fails.

Authentication, permission, server, decoding, and transient network failures continue through the existing `AppError` presentation. A failed refresh retains the last successful snapshot.

## Security and Privacy

- Never call `/api/v1/usage/api-keys/settings`.
- Never decode, log, display, or persist a complete CPA API key.
- Use only the `id` and `label` returned by `/api/v1/usage/api-keys/options`.
- Keep the selected ID in memory only.
- Preserve the existing Keychain storage behavior for administrator credentials and CPA API key viewer credentials.

## Testing

API client tests verify:

- administrator option decoding from `id` and `label`;
- option requests use `/api/v1/usage/api-keys/options`;
- filtered administrator overview requests include `api_key_id` and `range`;
- aggregate and CPA API key viewer requests omit `api_key_id`;
- `404` and `501` option responses map to an unsupported-capability result without exposing an app-wide error;
- no request or decoded model contains a complete Key value.

Refresh model tests verify:

- only administrators load Key options;
- empty or unsupported options hide the picker;
- selecting a Key refreshes the current page range;
- filtered snapshots are isolated by range and Key ID;
- aggregate Today always drives `todaySnapshot` and milestone tracking;
- a missing selected Key resets the filter and retries aggregate usage once;
- configuration identity changes reset the selection;
- model initialization defaults to aggregate usage.

Popover-focused tests verify the visibility rule and picker ordering through extracted, deterministic presentation logic rather than brittle UI inspection.

Run the complete Swift test suite after the focused red-green cycles.

## Documentation

Update both `README.md` and `README.zh-CN.md` to describe:

- the administrator-only Key picker;
- aggregate versus per-Key popover usage;
- the fact that menu bar metrics and milestone celebrations remain aggregate;
- graceful behavior with older Keeper versions.
