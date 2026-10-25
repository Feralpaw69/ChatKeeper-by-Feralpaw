# ChatKeeper

> World of Warcraft **3.3.5a (WotLK)** addon · made by **feralpaw**

Lightweight chat log. Keeps **one week** of chat, puts it back into your chat tabs after login or `/reload` so you can simply scroll up, and deletes anything older automatically.

## Features
- Logs every chat tab (not the combat log), with colours and item / spell / player links
- Rolling **7-day** history (hard cap 30,000 lines), older lines are deleted at login
- Restores the last 500 lines per tab after login / reload, with a grey day + time stamp
- Small **magnifier button** next to the chat (same size as the chat buttons) opens the search
- `/ck` window with the full week (draws only the visible lines and searches in the background, so it stays smooth even with 30,000 lines), scroll bar, search as you type, **Copy** mode (plain text you mark + Ctrl+C right in the window, **Chat** switches back), **Jump to chat** (scrolls your chat tab to the found line), item tooltips, clickable links
- Web links in chat become clickable – a click puts the link into your chat input, already marked, so Ctrl+C copies it
- **Arrow keys scroll the chat** while the mouse is over it (Shift+Up/Down = top/bottom). Outside the chat the arrows move your character as usual; disabled in combat
- Works alongside **ElvUI** (uses ElvUI's timestamps / URLs / max lines instead of fighting them), DBM, Twitch Emotes

## Commands
| Command | What it does |
|---|---|
| `/ck` or `/chatkeeper` | Open the week log |
| `/ck stats` | Lines and size saved |
| `/ck off <n>` · `/ck on <n>` | Stop / start logging chat tab *n* (e.g. a trade tab) |
| `/ck days <n>` | Days to keep (default 7) |
| `/ck max <n>` | Max lines saved (default 30000) |
| `/ck replay <n>` | Lines restored per tab after login (0 = off) |
| `/ck clear` | Delete the whole log |

## Installation
1. Download the latest ZIP from **Releases** (or *Code → Download ZIP*).
2. Copy the `ChatKeeper` folder into `World of Warcraft/Interface/AddOns/`.
   The folder name must stay exactly like this (no `-main` suffix).
3. Restart the game.

## License
MIT – see [LICENSE](LICENSE).
