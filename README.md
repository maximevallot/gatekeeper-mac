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

- Until the extension talks to the Mac, Today shows the design's sample day and says "sample" next to the
  title. Real data arrives through `~/Library/Application Support/Gatekeeper/today.json`, which the bridge
  in [docs/contract.md](docs/contract.md) will write. That contract is a proposal; nothing writes the file yet.
- "Change something", "All rules" and "Your week" open the extension's rules page in the browser that has
  the extension (found in Brave's or Chrome's profile). The extension has no week page yet.

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
