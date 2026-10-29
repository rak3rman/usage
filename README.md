# Usage

Claude Code, OpenAI Codex, and Cursor subscription limits in a macOS widget, fed by a
menu bar app. A fork of [Softcap](https://github.com/milushov/softcap).

## Build

Requires Xcode 16 or later and XcodeGen (`brew install xcodegen`).

```sh
make test   # UsageKit tests
make build  # generate Usage.xcodeproj, build the app and widget
make run    # build and open the app
```

The widget reads the app's snapshot from an app group container, and macOS grants that
container only to a team-signed build. Put your identity in `Signing.local.xcconfig`
(git-ignored, see `Signing.xcconfig`). An ad-hoc build runs, but its widget stays empty.

## Use

Open **Accounts…** from the menu bar, choose **Add Claude Code**, **Add Codex**, or
**Add Cursor**, and sign in in the browser. The app polls every five minutes and writes a snapshot; the
widget makes no network requests.

## Layout

| Path | Contents |
|---|---|
| `App/` | Menu bar popover, accounts window, polling |
| `Widget/` | WidgetKit extension |
| `Packages/UsageKit/Sources/UsageKit/` | Claude, Codex, and Cursor clients, browser sign-in, keychain account store, snapshot store |
| `Packages/UsageKit/Sources/UsageViews/` | radical-ui palette, dot bars, account row, widget layouts |

## Data

- **Grants:** keychain item `io.radison.usage.accounts`.
- **Snapshot:** `snapshot.json` in the `<team>.io.radison.usage` app group container.

## Licence

[MIT](LICENSE).
