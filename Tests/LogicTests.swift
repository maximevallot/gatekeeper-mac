import XCTest

/// The logic that needs no screen and touches no other app: reading the extension's snapshot, the rings,
/// and which apps exam mode acts on.
final class SnapshotTests: XCTestCase {
    /// The snapshot in docs/contract.md, as the extension sends it.
    let contractExample = """
    {"type":"snapshot","v":1,"at":1760716800000,"browser":"com.brave.Browser",
     "extensionId":"kfikbbdocggfgfhaegkgkfomhmacdbjp",
     "pages":{"today":"pages/popup.html","rules":"pages/rules.html","talk":"pages/talk.html","week":"pages/week.html","exam":null},
     "goal":"Finish problem set 4 by Thursday","reopensAt":1760774400000,"waiting":true,
     "kinds":[
       {"kind":"social","label":"Social media","short":"Social","minutes":15,"left":9,"status":"open","fraction":0.6},
       {"kind":"video","label":"Video","short":"Video","minutes":20,"left":0,"status":"spent","fraction":0},
       {"kind":"games","label":"Games","short":"Games","minutes":0,"left":0,"status":"closed","fraction":0}],
     "exam":{"until":1760742000000,"goal":"15.425 midterm, Wednesday 8:30"},
     "watch":null,"setupDone":true}
    """

    func testDecodesTheContractExample() throws {
        let s = try JSONDecoder().decode(Snapshot.self, from: Data(contractExample.utf8))
        XCTAssertEqual(s.v, 1)
        XCTAssertEqual(s.kinds.count, 3)
        XCTAssertEqual(s.pages?.talk, "pages/talk.html")
        XCTAssertNil(s.pages?.exam)
        XCTAssertEqual(s.exam?.goal, "15.425 midterm, Wednesday 8:30")
    }

    func testRingsShowWhatTheEngineDecided() throws {
        let s = try JSONDecoder().decode(Snapshot.self, from: Data(contractExample.utf8))
        let rings = Ring.rings(from: s)
        XCTAssertEqual(rings.map(\.name), ["Social", "Video", "Games"])
        XCTAssertEqual(rings[0].state, .open(minutesLeft: 9, fraction: 0.6))
        XCTAssertEqual(rings[1].state, .spent(reopens: Date(timeIntervalSince1970: 1760774400)))
        XCTAssertEqual(rings[2].state, .closedAllDay)
    }

    func testStatusWinsOverMinutes() {
        // A pass or a video bucket can leave minutes that disagree with the status; the status is what counts.
        let s = Snapshot(v: 1, at: 0, browser: nil, extensionId: nil, pages: nil, goal: nil, reopensAt: 1760774400000,
                         waiting: nil, kinds: [.init(kind: "video", label: "Video", short: nil, minutes: 20, left: 12,
                                                     status: "spent", fraction: 0.6, exam: nil)], exam: nil, watch: nil)
        XCTAssertEqual(Ring.rings(from: s).first?.state, .spent(reopens: s.reopens))
        XCTAssertEqual(Ring.rings(from: s).first?.name, "Video")
    }

    /// A snapshot made by the extension's own engine (~/gatekeeper-app 94e02f5, engine.snapshot()) with exam mode on.
    func testDecodesTheExtensionsRealSnapshot() throws {
        let url = Bundle(for: SnapshotTests.self).url(forResource: "extension-snapshot", withExtension: "json")!
        let s = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))
        XCTAssertEqual(s.v, 1)
        XCTAssertEqual(s.pages?.exam, "pages/rules.html#exam")
        let examEnd = Date(timeIntervalSince1970: s.exam!.until / 1000)
        // In exam mode every kind is closed until the exam ends, not all day.
        XCTAssertEqual(Ring.rings(from: s).map(\.state), Array(repeating: .spent(reopens: examEnd), count: 3))
    }

    func testNextDayStart() {
        let cal = Calendar.current
        let evening = cal.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 22))!
        let night = cal.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 2))!
        let four = cal.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 4))!
        XCTAssertEqual(Day.nextStart(after: evening, hour: 4), four)
        XCTAssertEqual(Day.nextStart(after: night, hour: 4), four)
    }

    func testExtensionIDs() {
        XCTAssertTrue(NativeHost.isExtensionID("kfikbbdocggfgfhaegkgkfomhmacdbjp"))
        XCTAssertFalse(NativeHost.isExtensionID("kfikbbdocggfgfhaegkgkfomhmacdbjz"))
        XCTAssertFalse(NativeHost.isExtensionID("short"))
    }
}

@MainActor
final class ExamGuardTests: XCTestCase {
    func testListedAppsAndOtherBrowsers() {
        let g = ExamGuard()
        g.apps = ExamApp.defaults
        g.apps[2].action = .quit // Slack
        g.extensionBrowser = "com.brave.Browser"
        XCTAssertEqual(g.action(for: "com.apple.mail"), .hide)
        XCTAssertEqual(g.action(for: "com.tinyspeck.slackmacgap"), .quit)
        XCTAssertEqual(g.action(for: "com.apple.Safari"), .hide)
        XCTAssertEqual(g.action(for: "com.google.Chrome"), .hide)
        XCTAssertNil(g.action(for: "com.brave.Browser"), "the browser with the extension stays")
        XCTAssertNil(g.action(for: "com.apple.iCal"), "an app not on the list is left alone")
        XCTAssertFalse(g.active, "a new guard acts on nothing")
    }

    func testUnknownExtensionBrowserSparesEveryChromium() {
        let g = ExamGuard()
        g.extensionBrowser = nil
        XCTAssertNil(g.action(for: "com.brave.Browser"))
        XCTAssertNil(g.action(for: "com.google.Chrome"))
        XCTAssertEqual(g.action(for: "com.apple.Safari"), .hide)
        XCTAssertEqual(g.action(for: "org.mozilla.firefox"), .hide)
    }
}

/// The Mac follows the browser and has no exam mode of its own (Maxime's decision of 2026-10-17).
final class FollowTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_792_250_000)

    func snapshot(examUntil: Date?) -> Snapshot {
        Snapshot(v: 1, at: 0, browser: nil, extensionId: nil, pages: nil, goal: nil, reopensAt: 1_792_310_400_000,
                 waiting: nil, kinds: [], exam: examUntil.map { .init(until: $0.timeIntervalSince1970 * 1000, goal: nil) },
                 watch: nil)
    }

    func testConnectedMeansAnsweredInTheLastTwoMinutes() {
        XCTAssertTrue(Follow.connected(lastMessage: now.addingTimeInterval(-60), now: now))
        XCTAssertFalse(Follow.connected(lastMessage: now.addingTimeInterval(-121), now: now))
        XCTAssertFalse(Follow.connected(lastMessage: nil, now: now))
    }

    func testTheBrowsersExamModeRunsToItsEndEvenWithTheBrowserClosed() {
        let end = now.addingTimeInterval(3600)
        XCTAssertEqual(Follow.enforcedExam(snapshot(examUntil: end), pendingUntil: nil, now: now), end)
        XCTAssertNil(Follow.enforcedExam(snapshot(examUntil: end), pendingUntil: nil, now: end.addingTimeInterval(1)))
    }

    func testNoBrowserNoExamMode() {
        XCTAssertNil(Follow.enforcedExam(nil, pendingUntil: nil, now: now))
        XCTAssertNil(Follow.enforcedExam(snapshot(examUntil: nil), pendingUntil: nil, now: now))
    }

    func testAStartAskedOnTheMacIsEnforcedUntilTheBrowserDecides() {
        let end = now.addingTimeInterval(3600)
        XCTAssertEqual(Follow.enforcedExam(nil, pendingUntil: end, now: now), end)
        let step = { (snap: Snapshot?, connected: Bool, asked: TimeInterval, queued: TimeInterval, stillQueued: Bool) in
            Follow.pendingStep(until: end, asked: self.now.addingTimeInterval(-asked), queued: self.now.addingTimeInterval(-queued),
                               stillQueued: stillQueued, snapshot: snap, connected: connected, now: self.now)
        }
        XCTAssertEqual(step(snapshot(examUntil: end), true, 30, 30, false), .confirmed)
        XCTAssertEqual(step(snapshot(examUntil: nil), true, 30, 30, true), .wait)
        XCTAssertEqual(step(snapshot(examUntil: nil), false, 30, 30, true), .drop, "no browser: no exam mode of the Mac's own")
        XCTAssertEqual(step(snapshot(examUntil: nil), true, 601, 30, true), .drop, "the engine refused it")
        XCTAssertEqual(step(snapshot(examUntil: nil), true, 150, 150, false), .resend)
        XCTAssertEqual(step(snapshot(examUntil: nil), true, 150, 150, true), .wait, "not taken yet: still waiting in the queue")
    }
}

/// The exchange both the Chrome/Brave bridge and the Safari handler use; only the answers that write nothing.
final class BridgeCoreTests: XCTestCase {
    func testRefusesWhatIsNotASnapshot() {
        XCTAssertEqual(BridgeCore.handle(["type": "hello"], callerID: nil, browser: nil)["error"] as? String, "bad_message")
        XCTAssertEqual(BridgeCore.handle(nil, callerID: nil, browser: nil)["error"] as? String, "bad_message")
    }

    func testRefusesAnotherVersion() {
        let reply = BridgeCore.handle(["type": "snapshot", "v": 2], callerID: nil, browser: "com.apple.Safari")
        XCTAssertEqual(reply["error"] as? String, "unknown_version")
    }
}
