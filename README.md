# Gatekeeper for Mac

The Mac partner of the Gatekeeper extension (`~/gatekeeper-app`). A menu-bar app: its popup is the Today screen
from the design canvas, and its exam mode hides or quits the apps an extension cannot reach (Mail, Outlook,
Slack, WhatsApp, Messages, Discord) and every browser except the one running the extension.

Version 0.1.0, 2026-10-17. Runs on macOS 14 or later. Signed "to run locally", so it needs no Apple
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

## What you should see with sample data

Click the arch. The popup says **Today** with a small grey "sample" beside it, because the extension does not
send anything yet. Under it, three rings: **Social** with 9 minutes left, **Video** locked "till 4:00",
**Games** locked "all day". Then the goal "Finish problem set 4 by Thursday", a blue **Change something**
button, and the links **All rules** and **Your week**. The three buttons open the extension's pages in Brave.

To try exam mode: click **Normal day**, then **Start exam mode…**, pick an end a few minutes away (the field
takes typing, or use **2 h**), and press **Start**. The chip turns blue, "Exam till …", and the menu-bar arch
gets a dot. Mail, Outlook, Slack, WhatsApp, Messages, Discord and every browser except Brave hide at once. Click
Mail in the Dock: it hides again and a small notice at the top of the screen says "Mail waits till …". When
the time comes, the apps it hid come back on their own. To end early, click the chip, then **End exam mode
early…**, and type the sentence shown.

## Connect it to the extension

The extension on `~/gatekeeper-app` main (from `94e02f5`) can send today to the Mac. To turn it on:

1. Run Gatekeeper from Xcode once (above). Each launch tells Brave where the bridge is.
2. In Brave, go to `brave://extensions` and click the round reload arrow on Gatekeeper.
3. Open Gatekeeper's rules page, go to Settings, turn on **Mac app**, and accept Brave's prompt
   ("Communicate with cooperating native applications").
4. Within a minute the popup loses "sample" and shows your real rings and goal.

If the switch says "Reload Gatekeeper once", reload it as in step 2.

## What it shows

- Real data comes from the extension through Chrome native messaging ([docs/contract.md](docs/contract.md)):
  the extension sends today to `gatekeeper-bridge`, a small tool inside the app, which saves it to
  `~/Library/Application Support/Gatekeeper/today.json`. At every launch the app tells Brave and Chrome where
  the bridge is (a file named `com.gatekeeper.helper.json` in each one's `NativeMessagingHosts` folder).
  Until the extension sends, Today shows the design's sample day and says "sample" next to the title.
- "Change something" opens the extension's talk page, "All rules" its rules and "Your week" its week, in the
  browser that has the extension.
- The rings show exactly what the extension decided. When the day turns over and the browser has not sent the
  new day yet, Today says "Waiting for the browser" rather than reopening anything on the Mac's own clock.
- Starting exam mode on the Mac is passed to the extension the next time it calls the bridge, within a minute.
  The Mac only ever asks to tighten: ending exam mode early happens in the extension, where the sentence is
  typed, and "End exam mode early" opens that page.

## Appearance

Light by default. Settings has Appearance: Light, Dark (deep slate, not black) or Match Mac. The colors are the
design canvas's tokens, the same as the extension's.

## Exam mode

Open the popup, click the "Normal day" chip, then Start exam mode…. Pick an end time and press Start. Until
then, the apps on the list and the other browsers are hidden (or quit, if set so in Settings) at once, whenever
they are opened or brought forward, and every two seconds; a notice says which app waits and until when. When
exam mode ends, the apps it hid come back. Ending early takes typing the sentence, on the Mac while the
extension is not connected, and in the extension once it holds exam mode. While exam mode is on, Quit is
greyed out and apps can be added to the list but not taken off.

Hiding and quitting other apps needs no macOS permission, so there is no permission screen.

## Change the project

The Xcode project is generated from `project.yml` by XcodeGen (`brew install xcodegen`, then
`xcodegen generate`). Edit `project.yml`, not the project file, for settings and targets; new Swift files in
`Gatekeeper/` are picked up by regenerating. `swift scripts/make-icon.swift` redraws the app icon.

Tests: ⌘U in Xcode, or `xcodebuild -project Gatekeeper.xcodeproj -scheme Gatekeeper test`. They cover the logic
only (the snapshot, the rings, which apps exam mode acts on) and touch no other app. In a Debug build,
`open Gatekeeper.app --args -showTestNotice` shows one exam-mode notice without hiding anything.
