# Using GhostMouse

You are driving a real Mac. These instructions come from what actually worked in
practice. Read them before concluding that something cannot be done.

## First call, every time

1. `list_apps` if you do not know the app name.
2. `get_app_state {app}` before acting. It returns the window screenshot, the
   accessibility tree, and often an OCR section.
3. Use the `element_index` values from that call. A new snapshot renumbers elements;
   an old index fails with "stale" and names how many seconds passed.

## Reading the state

- Lines like `[12] AXButton "Save" @100,200 80x24` are accessibility elements.
  Coordinates are screen points and are what `click {element_index: 12}` uses.
- Lines under `ocr:` are recognised text with **screenshot pixel** coordinates,
  `[x,y] text`. Feed those x,y straight into `click {x, y}` or `scroll {x, y}`.
- A window title is the fastest ground truth. If you are unsure where you are, read
  it before acting.

## Acting

- Prefer accessibility actions over pixels: `click {element_index}` uses `AXPress`
  when the element offers it, which does not depend on layout.
- Pixel clicks are the fallback, and the only option for OCR-only apps.
- `set_value` fills a field without typing. `type_text` types at the caret.
- `scroll` takes `direction` and `pages`, plus optional `x`,`y` to choose the pane.
- `press_key` accepts xdotool syntax: `super+t`, `ctrl+3`, `Return`, `Page_Down`.
- `hover {x,y}` moves the pointer without clicking. Hover-only controls (message
  menus, toolbars, reaction bars) only appear after this.
- Children and popovers sometimes reject a plain click. Right-click with
  `click {mouse_button: "right"}` to get a context menu; that menu is often the only
  reliable route to actions like Delete.

## When the tree is thin

Fewer than ~40 nodes means the app exposes almost nothing. Then:

1. Read the `ocr:` block. That is the content.
2. Click OCR coordinates, not guessed ones.
3. Re-read the window title after every action to confirm something happened.

## Failure triage

Do not report "impossible" after one no-op. Work this list first.

1. Did the window title or the diff change? If not, the input was ignored, not wrong.
2. Was the app frontmost? Background posting is the default and some apps (Teams,
   Electron and web-view apps) silently drop it.
3. If input is ignored, the fix is a focus mode: relaunch the server with
   `GM_STEAL_FOCUS=1`. Tell the user this; do not silently give up.
4. Did a transient menu close? Do not raise or re-activate the window between the
   click that opens a menu and the click that uses it.
5. Is the control hover-only? Use `hover` first, then click.
6. Is it inside a dialog? Re-read state; dialogs add new elements.
7. Is the app blocked? Approval is per app: ``ghostmouse approve <app>``. Security surfaces
   can never be approved, and that refusal is final.

## Things that are known to work

These were verified on this machine. Treat them as plausible, not as guaranteed.

- TextEdit, Finder, Chrome, Safari: read, click, type, scroll.
- Chrome: new tab, navigation, typing, page text through accessibility.
- Teams desktop with `GM_STEAL_FOCUS=1`: reading a chat, posting a message,
  deleting a message through the right-click menu.
- Outlook web in Chrome: creating and deleting calendar events through accessibility.

## Safety

- Confirm before destructive actions if the user has not already asked for them.
- After a delete or a send, re-read state and show the user the result.
- Never click through a password field, a security prompt, or a payment confirmation
  on your own initiative.
