# Nico Comments for OBS

Niconico Douga–style scrolling comments (弾幕) for OBS: white text with a dark outline sweeping right-to-left,
random big/small sizes, random colours, top/bottom fixed comments, and hype bursts of `8888` / `wwww`.

## Install

1. Keep all the files (`nico-comments.lua`, `nico-comments.html`, `youtube-chat.ps1`) in the same folder.
2. OBS → **Tools → Scripts** → **+** → pick `nico-comments.lua`.
3. The comments appear on top of **every scene** automatically. You don't add a source anywhere.
4. Change the look or chat settings, then click **Apply settings (reload comments)**.

Use **Show comments** (or its hotkey) to turn them on and off. Use **Hide on these scenes** for scenes like
`Brb, Start, End` where you don't want them.

## Stream with comments, record without them

Needs the free **Source Record** plugin by Exeldro.

Tick **Hide comments from recordings**. The script creates a scene called **Nico Clean Feed**. It always mirrors
whatever scene is live, without the comments, and a Source Record filter records it. The stream is unchanged.

**Make the comment-free recording** sets when that recording runs:

| Option | What happens |
|---|---|
| When I press Start Recording | You get two files: the normal one (with comments) and a `… (no comments)` copy. |
| Automatically while I'm streaming | Going live starts a comment-free recording by itself, so you don't need to press Record. |
| While streaming or recording | Either of the above. |

**Replay buffer:** while the toggle is on, starting OBS's replay buffer also starts a clean one of the same
length. Every time you save a replay, a `Replay … (no comments)` file is saved in the same folder.
With **Only keep comment-free replays** ticked (the default), the normal replay with comments is deleted
once the clean one has finished saving. If the clean replay fails to save, the normal one is kept.
Each buffer keeps its footage in RAM, so expect about twice the replay buffer memory use.

Clean files go in your normal OBS recording folder. To change the folder, encoder or format, open
**Nico Clean Feed** → Filters → **Nico Clean Recording**.

Notes:
- Leave the **Nico Clean Feed** scene alone. Don't stream from it and don't delete it while the toggle is on.
- Scene changes are hard cuts in the clean recording. Transitions only show on stream.
- The clean recording is a second encode, so it adds some GPU/CPU load.
- Hotkeys for both toggles are in **Settings → Hotkeys** under *Nico Comments*.

## Comment sources

| Source | How |
|---|---|
| Demo | On by default. Fake Japanese reactions, good for testing or as decoration. |
| Twitch chat | Type your channel name. Read-only, anonymous, no login or token needed. |
| YouTube chat | Type your channel handle (e.g. `@yourname`) and click **Apply settings**. It finds whatever stream you're live on, so you set it once. No API key needed. Windows only: `youtube-chat.ps1` runs hidden in the background and writes `youtube-chat.log` if something goes wrong. |
| Kick chat | Type your Kick channel name (or paste your channel link) and click **Apply settings**. Read-only, no login. Emotes show as their names. If Kick ever blocks the lookup, you can enter your numeric chatroom ID instead. |
| Custom WebSocket | Any server that sends plain text or JSON `{"text": "...", "commands": "big red", "user": "..."}`, such as Streamer.bot or Social Stream Ninja. |

## Chat commands

Viewers can start a message with Niconico-style commands in square brackets:

```
[big red] すごい
[ue cyan] 上に固定
[shita small #ff00ff] bottom, small, custom colour
[@8] stays for 8 seconds
```

- **Size:** `big` `medium` `small`
- **Position:** `naka` (scroll) `ue` (top) `shita` (bottom)
- **Colour:** `white red pink orange yellow green cyan blue purple black`, the premium `*2` colours, or `#RRGGBB`

## Without the script

You can add `nico-comments.html` as a Browser Source yourself and pass settings as URL parameters
(set the source's URL to `file:///C:/path/nico-comments.html?twitch=yourname&scale=1.2&bigPct=25`).
The parameter names match the `DEFAULTS` keys at the top of the HTML file. In this mode you can also
right-click the source → **Interact**, press **Enter** and type comments yourself.

## License

MIT. See [LICENSE](LICENSE).
