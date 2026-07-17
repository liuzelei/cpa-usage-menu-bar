# CPA Usage Menu Bar

English | [简体中文](./README.zh-CN.md)

A lightweight native macOS menu bar app for monitoring usage from a single [CPA Usage Keeper](https://github.com/Willxup/cpa-usage-keeper) instance. It shows today's token count directly in the menu bar, so you do not need to keep a browser tab open.

## Features

- Show today's token count, cost, request count, or an icon only in the menu bar.
- View request count, tokens, cost, and success rate in a native popover.
- Switch between Today, Last 24 Hours, 7 Days, and 30 Days.
- Authenticate with either a Keeper admin key or a CPA API key.
- Configure the Keeper URL, refresh interval, menu bar metric, and launch at login.
- Store passwords and API keys exclusively in macOS Keychain.
- Automatically reauthenticate when the Keeper session expires.
- Keep the most recent successful data when a network error occurs.
- Enable optional token milestone celebrations with synchronized multi-display playback, three visual styles, and sound effects.

## Requirements

- macOS 13 or later.
- An Apple silicon Mac.
- Apple Command Line Tools or Xcode for building from source.

Install Apple Command Line Tools:

```bash
xcode-select --install
```

## Get the Source

```bash
git clone https://github.com/liuzelei/cpa-usage-menu-bar.git
cd cpa-usage-menu-bar
```

## Build

Build and run the tests first:

```bash
swift test
```

Then create the release app:

```bash
./scripts/build-app.sh
```

The app will be generated at:

```text
dist/CPA Usage.app
```

The build script:

1. Builds the release configuration with Swift Package Manager.
2. Assembles a standard macOS `.app` bundle.
3. Applies a local ad hoc signature so the app can run immediately.

## Install and Launch

Copy the app to `/Applications`:

```bash
cp -R "dist/CPA Usage.app" /Applications/
open "/Applications/CPA Usage.app"
```

This is a menu bar app and does not appear in the Dock during normal operation. The Settings window opens automatically on first launch.

If macOS blocks the app the first time you launch it, right-click the app in Finder and choose **Open**.

## Configuration

### Keeper Service URL

Enter the URL used to access the CPA Usage Keeper dashboard.

The default HTTP port in the Keeper documentation is `8080`. For example, a deployment on your local network might use:

```text
http://192.168.1.10:8080
```

If your deployment changes `APP_PORT`, uses a reverse proxy, or is hosted under a subpath, enter the complete base URL that opens the Keeper dashboard in your browser.

### Authentication

The app supports two authentication methods, each using a different Keeper endpoint:

| Authentication method | Keeper login endpoint | Available data |
| --- | --- | --- |
| Keeper admin key | `/api/v1/auth/login` | Usage for the entire Keeper instance |
| CPA API key | `/api/v1/auth/api-key-login` | Usage for that CPA API key only |

The **Keeper Admin Key** corresponds to `LOGIN_PASSWORD` in the Keeper configuration.

`CPA_MANAGEMENT_KEY` is used by the Keeper server to access the CPA management API. It cannot be used to sign in to the Keeper dashboard.

### Other Settings

- Menu bar display: today's tokens, today's cost, today's request count, or icon only.
- Refresh interval: 30 seconds, 60 seconds, 5 minutes, or 15 minutes.
- Launch at login: uses macOS `SMAppService`. Move the app to `/Applications` first for best results.

Before saving, the app validates the URL and credentials. If validation fails, the existing working configuration is preserved.

### Token Milestone Celebrations

Celebrations are disabled by default. Enable **Token Milestone Celebrations** manually in **Settings…**, then choose one of these styles:

- Cinematic Fireworks: full-screen fireworks with centered milestone text.
- Top Achievement Banner: an achievement card and confetti that appear from the top of the screen.
- Retro Game Achievement: a pixel-art achievement panel with particles and a progress bar.
- Random Each Time: randomly selects one of the three effects for each celebration, using the same effect on every display.

Milestones trigger when the daily total reaches `10M`, `50M`, and `100M` tokens, then for every additional `100M` tokens after that. If one refresh crosses multiple milestones, only the highest one is shown. Each milestone is shown at most once per day.

The app does not replay missed milestones after launch, Mac wake, a date change, or a Keeper identity change. Celebrations appear on all connected displays at the same time without taking keyboard focus or intercepting mouse input.

Sound is disabled by default. When enabled, it plays once per celebration rather than once per display. **Preview Effect** uses a simulated `50M` milestone and the current unsaved effect settings; it does not read or change real usage data or milestone records.

## Usage

Click the icon or value in the menu bar to open the summary popover:

- Switch between Today, 24 Hours, 7 Days, and 30 Days.
- View request count, tokens, cost, and success rate.
- Click the refresh button to update data immediately.
- Click **Open Dashboard** to open the full Keeper dashboard in your default browser.
- Click **Settings…** to change connection or display options.
- Click **Quit** to close the app.

When an exclamation mark appears in the menu bar, click it to view authentication, network, or compatibility errors. During a temporary network error, the app keeps the most recent successful data and its update time.

## Security

- Keeper admin keys and CPA API keys are stored only in macOS Keychain.
- The URL, authentication type, and display preferences are stored locally in `UserDefaults`.
- Observed and displayed token milestone state for the current day is also stored in `UserDefaults` and contains no credentials.
- The app does not log credentials, cookies, login request bodies, or complete API responses.
- When using `http://`, credentials are not protected by TLS during network transmission. Use HTTP only on a trusted local network; HTTPS or a trusted reverse proxy is recommended whenever possible.

## Troubleshooting

### Cannot Connect to Keeper

- Confirm that the same URL opens in a browser on your Mac.
- Confirm that the port is correct. Keeper uses `8080` by default, but your deployment may differ.
- Check your firewall, VPN, reverse proxy, and local network routing.

### Authentication Failed

- Administrators should select **Keeper Admin Key** and enter `LOGIN_PASSWORD`.
- Regular users should select **CPA API Key**.
- Do not use `CPA_MANAGEMENT_KEY` as the Keeper login password.

### No Data in the Menu Bar

- Click the menu bar icon to view the specific error.
- Refresh manually.
- Confirm that the selected CPA API key has generated usage records.

## Project Structure

```text
Sources/CPAUsageMenuBar/    Application source code
Tests/CPAUsageMenuBarTests/ Tests
Resources/Info.plist        macOS app configuration
scripts/build-app.sh        Release packaging script
```

## License

This project is licensed under the [MIT License](./LICENSE).
