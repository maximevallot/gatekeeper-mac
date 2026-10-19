# Gatekeeper for Mac

The Mac partner of the Gatekeeper extension (`~/gatekeeper-app`). A menu-bar app: its popup is the Today screen
from the design canvas, and its exam mode hides or quits the apps an extension cannot reach (Mail, Outlook,
Slack, WhatsApp, Messages, Discord) and every browser except the one running the extension.

Version 0.3.0 (branch `account`, not released), 2026-10-18. Runs on macOS 14 or later. Signed "to run locally", so it needs no Apple
Developer account, not even a free Apple ID.

## Run it

1. In Finder, open your home folder, then `gatekeeper-mac`, and double-click `Gatekeeper.xcodeproj`. Xcode opens
   it. (Xcode is in Downloads for now; that works.)
2. At the top of the Xcode window, check that it reads **Gatekeeper** then **My Mac**. If it shows another
   device, click it and pick My Mac.
3. Press the ▶ button at the top left (or ⌘R). The first build takes a minute; "Build Succeeded" flashes at
   the top.
4. Nothing appears in the Dock, and that is right: Gatekeeper lives in the menu bar. Look at the top right of
   the screen for a small arch, left of the clock and the Control Center icons.
5. The first time only, a "Gatekeeper on your Mac" settings window opens, and macOS shows a notice that a login
   item was added. That is Gatekeeper opening at login. Close the window when you have looked.

Stop it with the ■ button in Xcode. While exam mode is off you can also quit from the popup: click "Normal
day", then Quit Gatekeeper.

## Testing 0.3 beside 0.2

This branch builds **Gatekeeper 0.3 (test)**: bundle ID `com.gatekeeper.mac.test`, its own folder
(`~/Library/Application Support/Gatekeeper Test`), its own Safari extension (`com.gatekeeper.mac.test.safari`,
built from `~/gatekeeper-app-0.3/extension`), its own Brave host (`com.gatekeeper.helper.test`), the staging relay
(`https://gatekeeper-relay-staging.mvallot22.workers.dev`), and it does not add itself to Login Items. It can sit
next to the 0.2 app without touching it, but two Gatekeepers running at once would both hide apps and both
count, so turn 0.2 off while testing:

1. Quit the 0.2 Mac app: in Xcode's 0.2 window press ■, or in its popup click Normal day › Quit Gatekeeper. In its
   Settings, untick **Open Gatekeeper when you log in** for the time of the test.
2. In Safari › Settings › Extensions, untick the 0.2 **Gatekeeper**. In Brave, `brave://extensions`: turn the 0.2
   Gatekeeper off and load `~/gatekeeper-app-0.3/extension` unpacked.
3. Open `~/gatekeeper-mac-0.3/Gatekeeper.xcodeproj` in Xcode (File › Open…), check **Gatekeeper › My Mac**, press ▶.
4. Safari › Settings › Developer: **Allow unsigned extensions** (again after any Safari restart), then Extensions:
   tick **Gatekeeper 0.3 (test)** and set Edit Websites… › Other websites to **Allow**.
5. Set up Gatekeeper in Brave, then in Safari choose "Already use Gatekeeper?" with the code from Brave's
   **Add a device** (the browser's Gatekeeper toolbar button, or the card at the end of its welcome). Join the Mac app the same way: click the arch, type a fresh code.

To go back: quit 0.3 (■ in its Xcode window), untick it in Safari, turn the 0.2 extension back on in Brave and
Safari, run 0.2 from its Xcode window, and tick Open at login again.

## Join your Gatekeeper (0.3)

Since 0.3 there is one Gatekeeper per person: an account that every browser and this Mac join. The Mac app has no
rules of its own; it shows the account's Today and hides apps in exam mode.

1. Set up Gatekeeper in a browser first (Brave, Chrome or Safari). Finishing its welcome creates your Gatekeeper.
2. In that browser, click Gatekeeper's toolbar button, then **Add a device** (the end of the welcome also shows
   one). It shows a 6-digit code that works once, for 10 minutes.
3. Click the arch in the menu bar and type the code under **Join your Gatekeeper**.

If the browser has Mac app turned on, it hands the code to the Mac by itself and step 3 happens alone.

**What you should see once joined:** **Today**, with a ring per kind you watch (minutes left, a red lock "till
4:00" or "all day"), a ring per site with its own limit, your goal, **Change something** (opens the chat in your
browser) and the links **All rules** and **Your week**. The Mac asks your Gatekeeper every 30 seconds, so a
budget spent in Safari shows here within half a minute.

**Offline:** the popup says when it last reached your Gatekeeper, keeps trying, and keeps any exam mode it knows
about until its end. **Leave** (Settings › Your Gatekeeper) takes this Mac out of the account; leaving loosens
nothing.

To try exam mode: click **Normal day**, then **Start exam mode…**, pick an end, say what it is for, press **Start**.
Apps hide at once; the chip says "Starting exam…" until your Gatekeeper confirms, then "Exam till …". Every
browser in the account goes into exam mode at its next sync. **End exam mode early…** opens the chat in your
browser, where the agent decides; the Mac never ends it.

The account flow is tested end to end against the relay's account under `wrangler dev`: start it with
`npm run dev:account` in ~/gatekeeper-relay-0.3, then run
`TEST_RUNNER_GATEKEEPER_RELAY_IT=http://127.0.0.1:8787 xcodebuild -project Gatekeeper.xcodeproj -scheme Gatekeeper test`.

**Later, not in 0.3** (Maxime, 2026-10-19: "fix that long term"):
- The Mac shows its own **Add a device** code, so another browser or a phone can join from the Mac (the account's
  `POST /account/code`, from the Mac's token).
- The Mac can be the **first device**: it creates the account itself (`POST /account/create` with kind `mac`) and
  runs a short welcome, instead of asking for a browser first.
- A **chat in the Mac app**, through the account (the `chat` request and the thread in the account's copy), so
  "Change something" and "End exam mode early" no longer need a browser.

To test against a relay running on this Mac (`wrangler dev`), start the app with `GATEKEEPER_RELAY=http://127.0.0.1:8787`
in the scheme's environment (Product › Scheme › Edit Scheme › Run › Arguments).

## Use it in Safari

Gatekeeper.app also contains the Safari version of the extension, built from `~/gatekeeper-app/extension` each
time you press Run (that folder is only read). Without the paid Apple developer account, Safari runs it as an
"unsigned" extension, which you allow by hand:

1. In Xcode, press ■ then ▶, so the latest build (with the Safari extension inside) is the one running.
2. In Safari, open **Safari › Settings…**, go to **Advanced**, and tick **Show features for web developers**.
3. Go to the **Developer** tab (on older Safari: the **Develop** menu) and tick **Allow unsigned extensions**.
   Safari asks for your Mac password; that is Safari's own prompt. **Do not quit Safari after this.**
4. Without quitting, go to **Extensions**. Gatekeeper is in the list; tick it. Click **Edit Websites…** and set
   **Other websites** to **Allow**, so it can send a closed site to the gate.
5. Gatekeeper's welcome page opens in Safari. Choose "Already use Gatekeeper?" and type the code from your other browser.

If Gatekeeper is not in the list at step 4, check that **Allow unsigned extensions** is still ticked; if it is,
quit Gatekeeper (■ in Xcode), press ▶ again, and look at Extensions once more.

**Allow unsigned extensions switches itself off every time Safari quits.** Do step 3 again after each restart of
Safari; Gatekeeper's rules stay. This goes away once the app is signed with the paid account.

To check it: on Gatekeeper's rules page in Safari, close one kind all day (0 minutes) and visit a site of it,
for example agar.io under Games. Safari should show the gate instead. Daily minutes count while a Safari window
is in front; Safari cannot tell when you step away, so they keep counting until you switch windows or apps. Settings in the Mac app has a button that opens Safari's extension
settings and says whether Gatekeeper is on there.

To link Safari to the Mac app, turn on **Mac app** in Gatekeeper's Settings in Safari, as in Brave. In Safari the
message goes straight to Gatekeeper.app, with nothing else to set up.

**In 0.3 Safari joins the same Gatekeeper** as your other browsers, with a code from **Add a device**, so
its rules, minutes and exam mode are the same everywhere.

## What it shows

- Everything comes from the extension through Chrome native messaging ([docs/contract.md](docs/contract.md)):
  the extension sends today to `gatekeeper-bridge`, a small tool inside the app (in Safari, to the app itself),
  which saves it in `~/Library/Application Support/Gatekeeper/snapshots/`. At every launch the app tells Brave and Chrome where
  the bridge is (a file named `com.gatekeeper.helper.json` in each one's `NativeMessagingHosts` folder).
- The browser counts as connected while it has sent something in the last two minutes; it sends every minute.
- The rings show exactly what the extension decided. When the day turns over and the browser has not sent the
  new day yet, Today says "Waiting for the browser" rather than reopening anything on the Mac's own clock.
- The Mac only ever asks the browser to tighten (start exam mode). Anything looser, ending exam mode early
  included, happens in the extension.

## Appearance

Light by default. Settings has Appearance: Light, Dark (deep slate, not black) or Match Mac. The colors are the
design canvas's tokens, the same as the extension's.

## Exam mode

Open the popup, click the "Normal day" chip, then Start exam mode…. Pick an end time and press Start. Until
then, the apps on the list and the other browsers are hidden (or quit, if set so in Settings) at once, whenever
they are opened or brought forward, and every two seconds; a notice says which app waits and until when. When
exam mode ends, the apps it hid come back. Exam mode starts only with the browser connected, and an exam mode the
browser started keeps running on the Mac until its end even if the browser closes. Ending early happens in the
extension's chat. While exam mode is on, Quit is greyed out and apps can be added to the list but not taken off.

Hiding and quitting other apps needs no macOS permission, so there is no permission screen.

## Change the project

The Xcode project is generated from `project.yml` by XcodeGen (`brew install xcodegen`, then
`xcodegen generate`). Edit `project.yml`, not the project file, for settings and targets; new Swift files in
`Gatekeeper/` are picked up by regenerating. `swift scripts/make-icon.swift` redraws the app icon.

Tests: ⌘U in Xcode, or `xcodebuild -project Gatekeeper.xcodeproj -scheme Gatekeeper test`. They cover the logic
only (the snapshot, the rings, which apps exam mode acts on) and touch no other app. In a Debug build,
`open Gatekeeper.app --args -showTestNotice` shows one exam-mode notice without hiding anything.
