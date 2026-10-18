# Sharing rules with the extension: the proposal and the contract

Status: approved by Maxime on 2026-10-17 ("Yes to the native-messaging contract"). The Mac side (the bridge,
the host manifests, the requests) is built in this repository; the extension side is built by the Gatekeeper
session that owns `~/gatekeeper-app`; it works end to end since 2026-10-17. Without a connected browser the Mac
asks to connect and has no rules, no exam mode and no sample day of its own (Maxime's decision of 2026-10-17,
"Ask to connect", from the one-model review in `~/brain/outputs/html/2026-10-17-gatekeeper-one-model.html`).

## Since 0.3: the account carries Today

From 0.3 each person has one Gatekeeper account on the relay (~/gatekeeper-relay `docs/account-contract.md`,
version 1). The Mac app is a device in it: it joins with a 6-digit code, syncs about every 30 seconds, gets the
account's Today (`today`, in the snapshot shape below) and sends its one kind of request, `startExam`. So in 0.3:

- Native messaging no longer carries Today and no longer hands over requests. The bridge still reads the snapshot
  the extension sends (and refuses one it cannot read), for two things that must be instant on this Mac: while
  exam mode is on it reopens Gatekeeper if it is not running, and if the snapshot carries `pairCode` (a fresh
  6-digit code from the account) and the Mac has not joined, it keeps the code so the Mac joins the same account
  without anyone typing it. The reply's `mac` gains `joined`, so the extension knows whether to send a code.
- "Two browsers" below is gone: every browser and the Mac are devices of one account, so there is nothing to
  follow. `linked.json`, `snapshots/` and `requests/` are deleted at launch.
- Exam mode is held as before: from the account's Today, kept until its end across relaunches and while offline;
  only a newer Today from the account ends it.

The rest of this file is the native-messaging contract as it stood in 0.2, kept because the snapshot shape and
its reading rules are what `today` uses.

## The idea

The extension stays the one home of the rules. Its engine already decides what a change is (tighter: now;
looser: next morning at 4:00), and that logic should not be written twice. The Mac app never edits a rule. It
shows today and enforces exam mode on the Mac. The only thing the Mac asks for is a tightening (start or extend exam
mode), a request that the extension's engine applies; anything looser is done in the extension.

## The route: Chrome native messaging, one message at a time

```
extension (Brave or Chrome)                     Mac
  background.js ──sendNativeMessage──▶ gatekeeper-bridge ──writes──▶ snapshots/<browser>.json ──read by──▶ Gatekeeper.app
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
   below changes (minutes left move at most once a minute), and at least once a minute as a heartbeat
   (`chrome.alarms`). Each send starts the bridge for a few milliseconds. The bridge's reply carries any
   requests the Mac queued, so a request from the Mac takes effect in the extension within a minute; the Mac
   enforces its own side at once and does not wait.
4. Files live in `~/Library/Application Support/Gatekeeper/` of the real home folder (the sandboxed Safari
   extension builds it from the user's record, not from its sandbox): the bridge replaces
   `snapshots/<browser>.json` atomically, where `<browser>` is the caller's bundle ID; `linked.json` names the
   browser the Mac follows; the app writes one file per request in `requests/`; the bridge hands each over once,
   to the followed browser only, and deletes it.

### Two browsers (0.2 only)

Until Gatekeeper has one account per person with the Mac as the hub, the Mac follows **one** browser
(QA round 2, C2 and H1):
- The first browser whose snapshot the bridge can read becomes the followed one (`linked.json`, created
  atomically). Settings in the Mac app can switch to another browser that has connected.
- A snapshot from any other browser is kept in its own file but changes nothing on the Mac, and that browser is
  answered `{ ok: false, error: "other_browser_linked", linked, linkedName }`, so its Mac app switch can say
  "Gatekeeper for Mac follows Safari". It is handed no request.
- Each browser keeps its own rules (Safari's copy of the extension has its own storage); the Mac shows the
  followed one's.

### In Safari

The Safari version of the extension lives inside Gatekeeper.app (`Contents/PlugIns/GatekeeperSafari.appex`,
copied from `~/gatekeeper-app/extension` at build time). Safari sends its `sendNativeMessage` to the app that
contains the extension, whatever host name it names, so there is no host manifest and no bridge tool: the
extension's handler does the same exchange (`BridgeCore`), with `browser` set to `com.apple.Safari`. The
extension's own address in Safari is `safari-web-extension://<uuid>/`, which no ID gives, so the snapshot may
carry `base` (below).

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
- Exam mode lives in the engine (`rules.exam`), started through `proposeRules`.

## The contract, version 1

Revised on 2026-10-17 after the extension session's review (`gatekeeper-mac-contract-review.md` in the shared
notes folder): the Mac sends no loosening, the snapshot carries what the engine decided rather than raw
counters, and the Mac never decides on its own clock that a new day began.

### Extension → bridge: `snapshot`

The engine's `todaySummary(state, now)`, plus who sent it, the pages, and exam mode.

```json
{
  "type": "snapshot",
  "v": 1,
  "at": 1760716800000,
  "browser": "com.brave.Browser",
  "extensionId": "kfikbbdocggfgfhaegkgkfomhmacdbjp",
  "pages": { "today": "pages/popup.html", "rules": "pages/rules.html", "talk": "pages/talk.html",
             "week": "pages/week.html", "exam": "pages/rules.html#exam" },
  "goal": "Finish problem set 4 by Thursday",
  "reopensAt": 1760774400000,
  "waiting": true,
  "kinds": [
    { "kind": "social", "label": "Social media", "short": "Social", "minutes": 15, "left": 9, "status": "open", "fraction": 0.6 },
    { "kind": "video",  "label": "Video",        "short": "Video",  "minutes": 20, "left": 0, "status": "spent", "fraction": 0 },
    { "kind": "games",  "label": "Games",        "short": "Games",  "minutes": 0,  "left": 0, "status": "closed", "fraction": 0 }
  ],
  "exam": { "until": 1760742000000, "goal": "15.425 midterm, Wednesday 8:30" },
  "watch": null
}
```

- Times are milliseconds since 1970, as the engine keeps them. `reopensAt` is `usage.endsAt`.
- `kinds`, `goal`, `reopensAt` and `waiting` (a loosening waits for the morning) are `todaySummary`'s, as is.
  `status` is "open", "spent" or "closed"; the Mac shows exactly that and works nothing out from minutes,
  so passes, video-rule buckets and the clock floor stay the engine's business. Other fields of
  `todaySummary` may be sent; the Mac ignores what it does not know.
- `pages` are paths inside the extension; the app opens `chrome-extension://<extensionId>/<path>` in
  `browser`: "Change something" and "End exam mode early" open `talk`, "All rules" `rules`, "Your week" `week`
  . A missing page falls back to `rules`. (`exam` is no longer used by the Mac.)
- `sites` (optional) lists the sites with a daily limit of their own, after the kinds, in the same shape with
  `kind` "s:<domain>" and `site`. `minutes` and `left` are null for a site closed only in exam mode
  (`examOnly: true`, status "open" outside exam mode); the Mac shows that ring as "exam only".
- `exam` is null when exam mode is off. While it is on, every kind comes as `closed` with `"exam": true`;
  the Mac shows those locked "till" `exam.until`, not "all day".
- `watch` is null, or `{ day, of, until }` during a new install's watch-only week, when `kinds` is empty; the
  Mac then says "Watch week · day 2 of 7".
- `base` (optional) is `runtime.getURL("")`. When present the Mac opens `base + path`; without it,
  `chrome-extension://<extensionId>/path`. Safari needs it.
- `browser` is the bundle ID of the browser running the extension. The bridge fills it from its parent process
  and `extensionId` from the calling origin when the extension leaves them out.

### Bridge → extension: the reply

```json
{ "ok": true, "v": 1, "requests": [
  { "id": "6F1C…", "type": "exam.start", "until": 1760742000000 }
] }
```

- The Mac only ever asks to tighten. `exam.start` starts exam mode, or extends it if the later `until` is this
  one, and applies at once. Any process running as the user could write a request file, so a request that
  loosens anything would be a way around the rules; there is none.
- Ending exam mode early is a loosening, so it happens only in the extension: the Mac's "End exam mode early"
  opens the chat (`pages.talk`, with `?from=rules` added when the path has no query, so it opens as a full
  tab), where the agent decides. The Mac never ends anything, not even with a typed sentence.
- Each request is handed over once. If the next snapshots do not show an `exam.start` within two minutes of
  handing it over, the Mac queues it again.
- Every reply carries `mac: { version, reads: [1] }`, the Mac app's version and the contract versions it
  reads, so an extension can say "Update Gatekeeper for Mac" rather than "isn't answering".
- Errors: `{ "ok": false, "error": "bad_origin" | "bad_message" | "unknown_version" | "write_failed" |
  "other_browser_linked" }`. `bad_message` carries `reason`: the bridge decodes the snapshot with the app's own
  type before accepting it, so a snapshot the Mac can't read is refused rather than answered "ok". The
  extension ignores them and tries again at the next change.

### What stays on the Mac

The list of apps exam mode hides or quits, and what happens to other browsers. They are Mac settings, changed
only on the Mac. While exam mode is on, the Mac lets an app be added to the list but not removed.

### What the Mac requires

`v` (1), `at` and `reopensAt` (milliseconds, numbers; an ISO 8601 time is also read) and `kinds` (an array).
Each row needs `kind`, `label` and `status`. Everything else is optional; a field of the wrong type counts as
missing, a row that can't be read is skipped rather than the whole day, and a decimal where an integer belongs is
rounded. `exam.until` may be milliseconds or an ISO 8601 time with its offset.

### What the Mac does with the snapshot

- A ring per kind, from `status`: "open" shows `left` and `fraction`, "spent" a lock and "till" `reopensAt`,
  "closed" a lock and "all day".
- Once its clock passes `reopensAt` with no newer snapshot, the Mac shows "Waiting for the browser" instead of
  rings. It never reopens anything on its own clock (QA finding H2).
- Exam mode is held: on while the followed browser says so, and the Mac keeps it, saved across relaunches, until its
  `until` or until a snapshot from the same browser with a later `at` says it is off. An older snapshot, or one
  from another browser, changes nothing. While exam mode is on and Gatekeeper is not running (force-quit), the
  Chrome/Brave bridge reopens it at the next call, at most a minute later.
- A Mac-started exam mode is enforced on the Mac at once and
  handed to the extension; once a snapshot shows it, the extension's is the one in force.
- The browser counts as connected while its last message is under two minutes old (it sends one a minute).
  Without it the Mac shows "Connect Gatekeeper in your browser", with one step and a button that opens the
  extension's rules page, and offers no exam mode. An exam mode the engine already started keeps running on the
  Mac until its `until`, even with the browser closed.
- "Start exam mode" is offered only while connected. It sends `exam.start` with `until` and `goal`, hides apps at
  once (a tightening), and shows exam mode as on once a snapshot confirms it. A start not confirmed is dropped
  when the browser stops answering, after ten minutes, or at its end, and its queued request is deleted.

### Done on the extension's side

The items the review listed (exam mode in the engine, the optional `nativeMessaging` permission behind a "Mac
app" switch, the listing and claims rows, the privacy and consent line for the snapshot file, calls from change
detection) are built on `~/gatekeeper-app` main for 0.2.0.
