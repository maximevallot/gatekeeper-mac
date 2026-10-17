# Gatekeeper for Mac

The Mac partner of the Gatekeeper extension (`~/gatekeeper-app`). A menu-bar app: its popup is the Today screen
from the design canvas, and its exam mode hides or quits the apps an extension cannot reach (Mail, Outlook,
Slack, WhatsApp, Messages, Discord) and every browser except the one running the extension.

Version 0.1.0, 2026-10-17. Runs on macOS 14 or later. Signed "to run locally", so it needs no Apple
Developer account, not even a free Apple ID.

## Run it

1. Open `Gatekeeper.xcodeproj` (double-click it in Finder, or in Xcode: Open… and pick this folder's
   `Gatekeeper.xcodeproj`).
2. At the top of the Xcode window, the scheme should read **Gatekeeper** and the destination **My Mac**.
3. Press **Run** (the ▶ button, or ⌘R).
4. No window appears and nothing shows in the Dock: Gatekeeper lives in the menu bar, at the top right of the
   screen, as a small arch. Click it for Today.
5. The first launch also opens the settings window and turns on "Open Gatekeeper when you log in". macOS shows
   a notice that a login item was added; that is this.

Stop it with the ■ button in Xcode, or from the popup: the "Normal day" chip, then Quit Gatekeeper.

## What it shows

- Real data comes from the extension through Chrome native messaging ([docs/contract.md](docs/contract.md)):
  the extension sends today to `gatekeeper-bridge`, a small tool inside the app, which saves it to
  `~/Library/Application Support/Gatekeeper/today.json`. At every launch the app tells Brave and Chrome where
  the bridge is (a file named `com.gatekeeper.helper.json` in each one's `NativeMessagingHosts` folder).
  Until the extension sends, Today shows the design's sample day and says "sample" next to the title.
- "Change something" opens the extension's talk page, "All rules" its rules and "Your week" its week, in the
  browser that has the extension.
- Starting exam mode on the Mac, or ending it with the sentence, is passed to the extension the next time it
  calls the bridge, within a minute.

## Appearance

Light by default. Settings has Appearance: Light, Dark (deep slate, not black) or Match Mac. The colors are the
design canvas's tokens, the same as the extension's.

## Exam mode

Open the popup, click the "Normal day" chip, then Start exam mode…. Pick an end time and press Start. Until
then, the apps on the list and the other browsers are hidden (or quit, if set so in Settings) at once, whenever
they are opened or brought forward, and every two seconds. Ending early takes typing the sentence. While exam
mode is on, Quit is greyed out and apps can be added to the list but not taken off.

Hiding and quitting other apps needs no macOS permission, so there is no permission screen.

## Change the project

The Xcode project is generated from `project.yml` by XcodeGen (`brew install xcodegen`, then
`xcodegen generate`). Edit `project.yml`, not the project file, for settings and targets; new Swift files in
`Gatekeeper/` are picked up by regenerating. `swift scripts/make-icon.swift` redraws the app icon.
