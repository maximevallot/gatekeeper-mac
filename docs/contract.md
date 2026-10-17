# Sharing rules with the extension: the proposal and the contract

Status: proposal, 2026-10-17. Not built on either side. The Mac app already reads the file this contract
writes (`today.json`), so it shows real data the day the bridge and the extension change land; until then it
shows sample data.

## The idea

The extension stays the one home of the rules. Its engine already decides what a change is (tighter: now;
looser: next morning at 4:00), and that logic should not be written twice. The Mac app never edits a rule. It
shows today and enforces exam mode on the Mac. Anything the Mac wants changed (start exam mode, end it with the
sentence) is a request that the extension's engine applies or refuses.

## The route: Chrome native messaging, one message at a time

```
extension (Brave or Chrome)                     Mac
  background.js ──sendNativeMessage──▶ gatekeeper-bridge ──writes──▶ today.json ──read by──▶ Gatekeeper.app
              ◀── reply: requests ───            ◀──reads, deletes── requests/*.json ◀──writes──
```

1. `Gatekeeper.app/Contents/MacOS/gatekeeper-bridge` is a small command-line tool inside the app. The browser
   starts it for each message, it does one exchange, and it exits.
2. At every launch the app writes the host manifest `com.gatekeeper.helper.json` into each Chromium browser's
   `NativeMessagingHosts` folder (Brave: `~/Library/Application Support/BraveSoftware/Brave-Browser/`, Chrome:
   `~/Library/Application Support/Google/Chrome/`). `allowed_origins` names the unpacked extension
   (`kfikbbdocggfgfhaegkgkfomhmacdbjp`, from the path of `~/gatekeeper-app/extension`) and the store ID once
   the store gives one. No other extension and no web page can reach the bridge.
3. The extension calls `chrome.runtime.sendNativeMessage("com.gatekeeper.helper", msg)` when the snapshot
   below changes (minutes left move at most once a minute), and at least every 5 minutes as a heartbeat.
   The bridge's reply carries any requests the Mac queued. A request from the Mac therefore takes effect in
   the extension within a minute or so; the Mac enforces its own side at once and does not wait.
4. Files live in `~/Library/Application Support/Gatekeeper/`: the bridge replaces `today.json` atomically;
   the app writes one file per request in `requests/`; the bridge hands each over once and deletes it.

### Why this route

- A local web server in the app (what the Python prototype did on port 7787) can be called by any web page on
  the machine and needs a `127.0.0.1` host permission. Native messaging is closed to everything but the named
  extension.
- Rules kept on the relay would need accounts and would break the promise that the relay stores no rules
  (claim J2). That becomes the route when a phone app needs the same rules.
- One message at a time, instead of `connectNative`, starts no long-lived process and does not keep the
  extension's service worker awake.

### What it costs

- The extension needs the `nativeMessaging` permission. Proposed as an optional permission, asked for from
  the rules page when the user turns on "Mac app", so installing the extension shows no new warning. Adding
  it is a store resubmission (0.2.x, not 0.1.1). To check before relying on it: that Chrome and Brave both
  accept `nativeMessaging` under `optional_permissions` at the extension's minimum Chrome version (116).
- The engine has no exam mode yet. The contract below assumes the extension session adds one.

## The contract, version 1

### Extension → bridge: `snapshot`

```json
{
  "type": "snapshot",
  "v": 1,
  "at": 1760716800000,
  "browser": "com.brave.Browser",
  "extensionId": "kfikbbdocggfgfhaegkgkfomhmacdbjp",
  "pages": { "rules": "pages/rules.html", "week": null },
  "goal": "Finish problem set 4 by Thursday",
  "dayStart": 4,
  "endsAt": 1760774400000,
  "kinds": [
    { "kind": "social", "label": "Social media", "minutes": 15, "usedSeconds": 360 },
    { "kind": "video",  "label": "Video",        "minutes": 20, "usedSeconds": 1200 },
    { "kind": "games",  "label": "Games",        "minutes": 0,  "usedSeconds": 0 }
  ],
  "pending": { "from": 1760774400000 },
  "exam": { "until": 1760742000000, "goal": "15.425 midterm, Wednesday 8:30" }
}
```

- Times are milliseconds since 1970, as the engine keeps them. `endsAt` is `usage.endsAt`.
- `kinds` lists only watched kinds, in the order the rules page shows them. `minutes` 0 means closed all day.
  `usedSeconds` is `usage.seconds[kind]`.
- `pages` are paths inside the extension; the app opens `chrome-extension://<extensionId>/<path>` in
  `browser`. `week` is null until the extension has a week page; the app then opens the rules page.
- `pending` is null or the moment a waiting loosening applies. `exam` is null when exam mode is off.
- `browser` is the bundle ID of the browser running the extension. The bridge can also find it from its parent
  process, so the extension may leave it out.

### Bridge → extension: the reply

```json
{ "ok": true, "v": 1, "requests": [
  { "id": "6F1C…", "type": "exam.start", "until": 1760742000000, "goal": "15.425 midterm" },
  { "id": "9A20…", "type": "exam.end", "sentence": "I am choosing to stop preparing for my exam" }
] }
```

- `exam.start`: a tightening, applied at once. If exam mode is already on, the later `until` wins.
- `exam.end`: applied only if `sentence` is the end sentence, typed by the user. Anything else is refused.
- Each request is handed over once. The result shows in the next snapshot; if the Mac does not see it there
  within two minutes it queues the request again.
- Errors: `{ "ok": false, "error": "bad_message" | "unknown_version" }`. The extension ignores them and tries
  again at the next change.

### What stays on the Mac

The list of apps exam mode hides or quits, and what happens to other browsers. They are Mac settings, changed
only on the Mac. While exam mode is on, the Mac lets an app be added to the list but not removed.

### What the Mac does with the snapshot

- A ring per kind: minutes left, or a lock with "till 4:00" when the budget is spent, or "all day" at 0
  minutes. A snapshot older than its `endsAt` shows full budgets (a new day began).
- Exam mode is on if the snapshot says so or if the Mac started it and the extension has not answered yet; the
  later `until` wins.
