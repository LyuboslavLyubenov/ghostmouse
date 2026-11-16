# Microsoft Teams

Teams exposes roughly a dozen accessibility nodes, so every action here is OCR plus
pixels, and every click must be preceded by `get_app_state`.

## Before anything

- The server must run with `GM_STEAL_FOCUS=1`. In background mode Teams ignores
  synthetic clicks and keys completely. If nothing reacts, check that first instead of
  concluding Teams is unreadable.
- `get_app_state` returns an `ocr:` block. Use its `[x,y]` values directly.

## Reading a chat

1. Click the Chat rail: usually around `x=70, y=290` in screenshot pixels.
2. The chat list shows rows with name and preview. Click the row to open it.
3. If the message pane looks empty, check the tab row at the top of the pane
   ("Chat / Shared / Notes / Recap"). The app remembers the last tab, so a chat often
   opens on **Notes**, which is empty. Click **Chat** (around `x=1344, y=156`) and
   read again.
4. Message rows OCR as: sender, time, then text. Your own messages are right aligned.

## Posting a message

1. Open the channel or chat.
2. Click the composer at the bottom (`Message in <channel>`).
3. `type_text` the message. Emoji are fine; the engine sends them as unicode chunks.
4. `press_key {key: "Return"}` to send.
5. Verify: `get_app_state` and look for your text in the OCR block.

## Deleting a message

1. Right-click the message text: `click {x, y, mouse_button: "right"}`.
2. The context menu OCRs as a list: Reply in thread, Edit, Forward, Copy link,
   Save this message, Delete, Pin for everyone.
3. Click **Delete**.
4. Verify: the row becomes "This message has been deleted".

A plain left click on the hover menu does nothing: its accessibility button is 1 px
tall and non-actionable. Right-click is the path that works.

## Channels

- The left pane lists favourites, then teams and channels. A channel row reads
  "Channel <name>".
- Clicking a channel updates the window title to
  `Teams and Channels | <team> | <channel>`. Use the title to confirm you are in the
  right place before typing.

## Calendar

- Teams desktop can create events: `New` button top right, then title, then Save.
- Its event panel is fragile: the Delete button sits under the rail area and dialogs
  close when the window is re-raised.
- For creating or deleting events, **Outlook web in Chrome is more reliable** and has
  a real accessibility tree. Open `https://outlook.office.com/calendar`, click the
  event button, then `Delete`, then confirm `Delete`.
- A created event appears in both Teams and Outlook; deleting it in either is enough.
