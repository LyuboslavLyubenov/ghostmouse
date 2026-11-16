# Google Chrome

Chrome exposes a full accessibility tree, so prefer element indices over pixels.

## Reading

- `get_app_state` gives the tab title, the omnibox value, and the whole page tree
  under `AXWebArea`. For content-heavy pages the tree is large; read what you need.
- If a page renders into canvas or a virtualised list, the tree thins out. Then read
  the `ocr:` block and click its coordinates.

## Navigating

1. `press_key {key: "super+t"}` opens a new tab.
2. `type_text` the address into the focused omnibox.
3. `press_key {key: "Return"}`.
4. Wait with `get_app_state`; the engine settles on its own, do not sleep manually.

## URL policy

- Only `http` and `https` pages can be driven.
- `file://`, `javascript:`, `data:` and `ftp:` are refused by design.
- `chrome://newtab`, `about:blank` and `edge://newtab` are allowed, because every task
  starts there.
- `localhost`, `127.0.0.1` and `*.local` are refused as private hosts.

If you get "blocked on ... URLs", that is the policy, not a bug. Ask the user to
navigate somewhere public, or explain why the page is out of scope.

## Working with web apps

- Web apps that are signed in (Outlook, Teams web) behave well: clickable elements,
  readable text, real dialogs.
- Dialogs add new elements; re-read state after opening one.
- For a destructive action, verify afterwards by re-reading and quoting the result.
