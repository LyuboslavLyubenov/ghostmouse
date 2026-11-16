# GhostMouse

A local MCP server that gives an LLM hands on macOS applications: read the screen,
click, type, scroll, and verify. It speaks the Model Context Protocol over stdio, so
any MCP client can use it.

No network. No telemetry. Everything stays on the machine.

## Why another one

- **Accessibility first.** Elements are read from the accessibility tree and acted on
  with accessibility actions, so clicks do not depend on pixel-perfect layout.
- **Pixel and OCR fallback.** Web-view apps often expose an empty tree. Then the
  server returns recognised text with coordinates, and you click those.
- **Background by default.** Actions are posted to the target process. Your pointer
  and your focus stay where they are, so you can keep working while the agent drives
  another window.
- **It waits for the UI.** Snapshots settle on three stable samples instead of a fixed
  sleep, and replies include a structural diff against the previous snapshot.
- **It says no.** Protected surfaces are refused, apps need one recorded approval,
  non-http(s) pages and private hosts are blocked, and Esc cancels the next action.

## Tools

| Tool | Purpose |
|---|---|
| `list_apps` | running apps, bundle ids, pids |
| `get_app_state` | window snapshot: tree, screenshot, diff, OCR when sparse |
| `click` | element index or pixels, left/right/middle, multi-click |
| `perform_secondary_action` | named accessibility action |
| `set_value` | fill a settable element |
| `select_text` | select text or place the caret |
| `scroll` | pages, any pane |
| `drag` | press, move, release |
| `press_key` | xdotool-style combinations |
| `hover` | reveal hover-only controls |
| `type_text` | unicode and emoji |
| `get_playbook` | operating guide, optionally per app |

## Requirements

- macOS 14 or newer
- Xcode Command Line Tools (`xcode-select --install`)

## Install

```bash
git clone https://github.com/<you>/ghostmouse.git
cd ghostmouse
./install.sh
```

`install.sh` builds a release `.app`, signs it ad-hoc, and copies it to
`~/Applications`. Then grant two permissions:

1. System Settings → Privacy & Security → **Accessibility**: add `GhostMouse.app`.
2. System Settings → Privacy & Security → **Screen Recording**: add the same app.

```bash
~/Applications/GhostMouse.app/Contents/MacOS/ghostmouse request-permissions
~/Applications/GhostMouse.app/Contents/MacOS/ghostmouse selftest
```

`selftest` prints both flags; both must say `true`.

## Use it from an MCP client

Claude Desktop (`claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "ghostmouse": {
      "command": "/Users/<you>/Applications/GhostMouse.app/Contents/MacOS/ghostmouse"
    }
  }
}
```

Cursor, OpenCode and other clients use the same `command` form:

```json
{"mcp": {"ghostmouse": {"type": "local", "enabled": true,
  "command": ["/Users/<you>/Applications/GhostMouse.app/Contents/MacOS/ghostmouse"]}}}
```

## Approvals

Nothing runs until an app is approved, and security surfaces can never be approved.

```bash
GM=~/Applications/GhostMouse.app/Contents/MacOS/ghostmouse
$GM approvals
$GM approve "TextEdit"
$GM revoke "TextEdit"
$GM policy com.apple.SecurityAgent
```

The list lives at `~/Library/Application Support/GhostMouse/approvals.json`.

## Background or foreground

Default is background: the real pointer does not move and the app you are using keeps
focus. Some web-view apps ignore background events. For those, launch the server with:

```bash
GM_STEAL_FOCUS=1 /path/to/ghostmouse
```

That activates the target and uses the real pointer for clicks. Expect the mouse to
move.

## Playbooks

`initialize.instructions` carries the general guide, `get_playbook` returns it again
with per-app notes, and the first snapshot of an app prepends that app's notes once.
Files live in `playbooks/`.

The guide includes a failure triage list, so an agent checks focus mode, hover state
and the window title before deciding an app cannot be driven.

## Safety model

| Control | Behaviour |
|---|---|
| Denied apps | Security agent, login window, keychain, password managers: refused permanently |
| Approvals | every other app needs one recorded approval |
| URL policy | only http/https; `localhost`, `127.0.0.1`, `*.local` refused; new-tab pages allowed |
| Cancellation | Esc sets a flag; the next action is refused until a new snapshot |
| Visibility | a badge names the controlled window and offers "Esc to cancel" |
| Display | a power assertion is held only for the duration of an action |

## Verified

Exercised on: TextEdit, Finder, Google Chrome, Safari, Microsoft Teams (desktop and
web) and Outlook web. Reading, clicking, typing, scrolling, posting a message,
deleting a message, creating and deleting a calendar event.

Not a promise for every app. Canvas apps, games and heavily customised views may need
the OCR path, and some apps filter injected input entirely.

## Development

```bash
swift build
swift run ghostmouse-tests     # 66 assertions, exits non-zero on failure
./package.sh                   # dist/GhostMouse.app
```

`swift test` needs XCTest, which Command Line Tools alone does not ship; the same
cases exist in `Tests/GhostMouseCoreTests` for a machine with Xcode.

## Layout

```
Sources/GhostMouseCore/   snapshot + diff, settle rules, target policy, approval store
Sources/ghostmouse/       MCP server, tools, capture, input, OCR, badge, playbooks
Sources/ghostmouse-tests/ plain assertion runner
Tests/GhostMouseCoreTests/XCTest mirror
playbooks/                general and per-app guides
package.sh                release build + .app assembly
install.sh                build, sign, install to ~/Applications
```

## Licence

MIT. See [LICENSE](LICENSE).
