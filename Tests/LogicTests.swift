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
                                                     status: "spent", fraction: 0.6, exam: nil, site: nil, examOnly: nil)], sites: nil, exam: nil, watch: nil)
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

    /// A snapshot from the extension's engine (~/gatekeeper-app 6e38dd0) with two sites that have their own limit:
    /// lequipe.fr 15 minutes a day, example-news.com closed only in exam mode.
    func testSitesWithTheirOwnLimitComeAfterTheKinds() throws {
        let url = Bundle(for: SnapshotTests.self).url(forResource: "extension-snapshot-sites", withExtension: "json")!
        let s = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))
        let rings = Ring.rings(from: s)
        XCTAssertEqual(rings.map(\.name), ["Social", "Games", "example-news", "lequipe"])
        XCTAssertEqual(rings[2].state, .examOnly)
        XCTAssertEqual(rings[3].state, .open(minutesLeft: 15, fraction: 1))
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

    func snapshot(examUntil: Date?, at: Double = 0) -> Snapshot {
        Snapshot(v: 1, at: at, browser: nil, extensionId: nil, pages: nil, goal: nil, reopensAt: 1_792_310_400_000,
                 waiting: nil, kinds: [], sites: nil, exam: examUntil.map { .init(until: $0.timeIntervalSince1970 * 1000, goal: nil) },
                 watch: nil)
    }

    func testConnectedMeansAnsweredInTheLastTwoMinutes() {
        XCTAssertTrue(Follow.connected(lastMessage: now.addingTimeInterval(-60), now: now))
        XCTAssertFalse(Follow.connected(lastMessage: now.addingTimeInterval(-121), now: now))
        XCTAssertFalse(Follow.connected(lastMessage: nil, now: now))
    }

    func testTheBrowsersExamModeRunsToItsEndEvenWithTheBrowserClosed() {
        let end = now.addingTimeInterval(3600)
        let held = Follow.hold(nil, seeing: snapshot(examUntil: end, at: 1000))
        XCTAssertEqual(Follow.enforcedExam(held, pendingUntil: nil, now: now), end)
        XCTAssertNil(Follow.enforcedExam(held, pendingUntil: nil, now: end.addingTimeInterval(1)))
    }

    func testOnlyANewerSnapshotEndsExamMode() {
        let end = now.addingTimeInterval(3600)
        let held = Follow.hold(nil, seeing: snapshot(examUntil: end, at: 2000))
        XCTAssertEqual(Follow.hold(held, seeing: snapshot(examUntil: nil, at: 1000)), held, "an older snapshot changes nothing")
        XCTAssertNil(Follow.hold(held, seeing: snapshot(examUntil: nil, at: 3000)), "a newer one from the followed browser ends it")
    }

    func testNoBrowserNoExamMode() {
        XCTAssertNil(Follow.enforcedExam(nil, pendingUntil: nil, now: now))
        XCTAssertNil(Follow.hold(nil, seeing: snapshot(examUntil: nil, at: 1)))
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
        XCTAssertEqual(BridgeCore.handle(["type": "hello"], callerID: nil, browser: nil, appVersion: nil).reply["error"] as? String, "bad_message")
        XCTAssertEqual(BridgeCore.handle(nil, callerID: nil, browser: nil, appVersion: nil).reply["error"] as? String, "bad_message")
    }

    func testRefusesAnotherVersion() {
        let reply = BridgeCore.handle(["type": "snapshot", "v": 2], callerID: nil, browser: "com.apple.Safari", appVersion: nil).reply
        XCTAssertEqual(reply["error"] as? String, "unknown_version")
    }
}

/// Reading what the extension sends: strict about v, at, reopensAt and kinds, lenient about the rest (QA round 2, H2).
final class LenientDecodingTests: XCTestCase {
    func decode(_ json: String) throws -> Snapshot { try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8)) }

    func testABadRowIsSkippedNotTheWholeDay() throws {
        let s = try decode(#"{"v":1,"at":1,"reopensAt":2,"kinds":[{"kind":"social","label":"Social","status":"open","minutes":7.5,"left":3},{"nope":true}]}"#)
        XCTAssertEqual(s.kinds.count, 1)
        XCTAssertEqual(s.kinds[0].minutes, 8)
    }

    func testExamUntilAsAnISOTime() throws {
        let s = try decode(#"{"v":1,"at":1,"reopensAt":2,"kinds":[],"exam":{"until":"2026-10-17T23:00:00-04:00"}}"#)
        XCTAssertEqual(s.exam?.until, 1_792_292_400_000)
    }

    func testAFieldOfTheWrongTypeCountsAsMissing() throws {
        let s = try decode(#"{"v":1,"at":1,"reopensAt":2,"kinds":[],"goal":42,"pages":"x","sites":{"a":1}}"#)
        XCTAssertNil(s.goal)
        XCTAssertNil(s.pages)
        XCTAssertNil(s.sites)
    }

    func testTheFieldsTheMacNeedsAreRequired() {
        XCTAssertThrowsError(try decode(#"{"v":1,"at":1,"kinds":[]}"#), "no reopensAt")
        XCTAssertThrowsError(try decode(#"{"v":1,"at":1,"reopensAt":null,"kinds":[]}"#))
        XCTAssertThrowsError(try decode(#"{"v":1,"at":1,"reopensAt":2,"kinds":{}}"#), "kinds as an object")
    }
}

/// The bridge's exchange since 0.3, in a scratch folder: no stored snapshots, a pairing code kept until the Mac joins.
final class BridgeExchangeTests: XCTestCase {
    var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("gk-bridge-\(UUID().uuidString)")
        setenv("GATEKEEPER_FOLDER", dir.path, 1)
    }

    override func tearDown() {
        unsetenv("GATEKEEPER_FOLDER")
        try? FileManager.default.removeItem(at: dir)
    }

    func snap(_ at: Double, exam: Double? = nil, pair: String? = nil) -> [String: Any] {
        var s: [String: Any] = ["type": "snapshot", "v": 1, "at": at, "reopensAt": 9e12, "kinds": []]
        if let exam { s["exam"] = ["until": exam] }
        if let pair { s["pairCode"] = pair }
        return s
    }

    func testAPairingCodeIsKeptOnceUntilTheMacJoins() throws {
        let r = BridgeCore.handle(snap(1, pair: "123456"), callerID: nil, browser: "com.apple.Safari", appVersion: "0.3.0")
        XCTAssertEqual(r.reply["ok"] as? Bool, true)
        XCTAssertEqual((r.reply["mac"] as? [String: Any])?["joined"] as? Bool, false)
        XCTAssertEqual(NativeHost.takePairCode(), "123456")
        XCTAssertNil(NativeHost.takePairCode(), "read once")
    }

    func testNoPairingCodeOnceJoined() throws {
        try AccountStore.save(AccountMembership(relay: "http://localhost:8787", deviceId: "d1", deviceKey: "k", accountId: nil, joinedAt: Date()))
        _ = BridgeCore.handle(snap(1, pair: "123456"), callerID: nil, browser: "com.brave.Browser", appVersion: nil)
        XCTAssertNil(NativeHost.takePairCode())
    }

    func testAStaleOrMalformedCodeIsIgnored() {
        _ = BridgeCore.handle(snap(1, pair: "12ab56"), callerID: nil, browser: nil, appVersion: nil)
        XCTAssertNil(NativeHost.takePairCode())
        NativeHost.savePairCode("654321")
        XCTAssertNil(NativeHost.takePairCode(now: Date().addingTimeInterval(601)), "older than the code's 10 minutes")
    }

    func testExamModeOnAsksForTheAppToRun() {
        let r = BridgeCore.handle(snap(1, exam: (Date().timeIntervalSince1970 + 3600) * 1000), callerID: nil, browser: nil, appVersion: nil)
        XCTAssertNotNil(r.examUntil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("snapshots").path), "no snapshot is stored any more")
    }

    func testASnapshotTheMacCannotReadIsRefusedWithTheReason() {
        var bad = snap(1)
        bad["reopensAt"] = NSNull()
        let r = BridgeCore.handle(bad, callerID: nil, browser: "com.apple.Safari", appVersion: nil)
        XCTAssertEqual(r.reply["error"] as? String, "bad_message")
        XCTAssertNotNil(r.reply["reason"])
    }

    func testTheFolderIsInTheRealHomeNotASandbox() {
        unsetenv("GATEKEEPER_FOLDER")
        XCTAssertFalse(NativeHost.folder.path.contains("/Library/Containers/"))
        XCTAssertTrue(NativeHost.folder.path.hasSuffix("Library/Application Support/Gatekeeper"))
        setenv("GATEKEEPER_FOLDER", dir.path, 1)
    }

    func testTheDeviceKeyFileIsReadableByThisUserOnly() throws {
        try AccountStore.save(AccountMembership(relay: "r", deviceId: "d", deviceKey: "secret", accountId: "a", joinedAt: Date()))
        let mode = try FileManager.default.attributesOfItem(atPath: AccountStore.file.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
        XCTAssertEqual(AccountStore.load()?.deviceKey, "secret")
        AccountStore.clear()
        XCTAssertNil(AccountStore.load())
    }
}

/// A stand-in relay for the account client: answers each path with a set status and body.
final class StubRelay: URLProtocol {
    static var answers: [String: (Int, [String: Any])] = [:]
    static var lastBody: [String: Any]?
    static var lastAuth: String?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url?.path ?? ""
        Self.lastAuth = request.value(forHTTPHeaderField: "Authorization")
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: buf.count); if n <= 0 { break }; data.append(buf, count: n) }
            stream.close()
            Self.lastBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        let (status, body) = Self.answers[path] ?? (404, ["error": "not_found"])
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: (try? JSONSerialization.data(withJSONObject: body)) ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class AccountClientTests: XCTestCase {
    var client: AccountClient!

    override func setUp() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubRelay.self]
        client = AccountClient(relay: URL(string: "http://relay.test")!, session: URLSession(configuration: config))
        StubRelay.answers = [:]
    }

    func testJoinWithACode() async throws {
        StubRelay.answers[AccountClient.API.join] = (200, ["v": 1, "accountId": "acc-1", "device": ["id": "dev-1", "token": "key-1"],
                                                           "copy": [:], "version": 1, "serverNow": 1])
        let m = try await client.join(code: "12 34 56").membership
        XCTAssertEqual(m.deviceId, "dev-1")
        XCTAssertEqual(m.deviceKey, "key-1")
        XCTAssertEqual(StubRelay.lastBody?["code"] as? String, "123456")
        XCTAssertEqual((StubRelay.lastBody?["device"] as? [String: Any])?["kind"] as? String, "mac")
    }

    func testAWrongCodeSaysWhy() async {
        StubRelay.answers[AccountClient.API.join] = (404, ["v": 1, "error": "bad_code"])
        do { _ = try await client.join(code: "000000"); XCTFail() } catch {
            XCTAssertEqual(error as? AccountClient.Failure, .badCode("bad_code"))
        }
    }

    func testSyncSendsTheRequestsAndReadsToday() async throws {
        let snapshot: [String: Any] = ["v": 1, "at": 5, "reopensAt": 9e12,
                                       "kinds": [["kind": "social", "label": "Social media", "status": "open", "minutes": 15, "left": 9]],
                                       "exam": ["until": 9e12, "goal": "midterm"]]
        StubRelay.answers[AccountClient.API.sync] = (200, ["v": 1, "version": 9, "serverNow": 1, "spansUpTo": 0,
                                                           "copy": ["rules": ["exam": ["until": 9e12, "goal": "midterm"]]],
                                                           "today": snapshot, "results": [["id": "r1", "ok": true]]])
        let m = AccountMembership(relay: "http://relay.test", deviceId: "dev-1", deviceKey: "key-1", accountId: nil, joinedAt: Date())
        let synced = try await client.sync(m, have: 7, requests: [["id": "r1", "type": "startExam", "until": 9e12, "source": "mac"]])
        XCTAssertEqual(synced.today?.kinds.first?.left, 9)
        XCTAssertEqual(synced.today?.exam?.goal, "midterm")
        XCTAssertEqual(synced.version, 9)
        XCTAssertNotNil(synced.results["r1"])
        XCTAssertEqual(StubRelay.lastAuth, "Bearer key-1")
        XCTAssertEqual(StubRelay.lastBody?["have"] as? Int, 7)
        XCTAssertEqual((StubRelay.lastBody?["requests"] as? [[String: Any]])?.first?["type"] as? String, "startExam")
    }

    func testWithoutTodayExamModeComesFromTheCopy() async throws {
        StubRelay.answers[AccountClient.API.sync] = (200, ["v": 1, "version": 3, "serverNow": 1,
                                                           "copy": ["rules": ["exam": ["until": 9e12, "goal": "final"]]], "results": []])
        let m = AccountMembership(relay: "http://relay.test", deviceId: "d", deviceKey: "k", accountId: nil, joinedAt: Date())
        let synced = try await client.sync(m, have: nil, requests: [])
        XCTAssertNil(synced.today)
        XCTAssertEqual(synced.examFromCopy?.goal, "final")
    }

    func testUnchangedKeepsTheLastToday() async throws {
        StubRelay.answers[AccountClient.API.sync] = (200, ["v": 1, "version": 7, "serverNow": 1, "unchanged": true])
        let m = AccountMembership(relay: "http://relay.test", deviceId: "d", deviceKey: "k", accountId: nil, joinedAt: Date())
        let synced = try await client.sync(m, have: 7, requests: [])
        XCTAssertTrue(synced.unchanged)
        XCTAssertNil(synced.today)
    }

    func testARemovedDeviceIsToldApart() async {
        StubRelay.answers[AccountClient.API.sync] = (401, ["v": 1, "error": "bad_token"])
        let m = AccountMembership(relay: "http://relay.test", deviceId: "d", deviceKey: "k", accountId: nil, joinedAt: Date())
        do { _ = try await client.sync(m, have: nil, requests: []); XCTFail() } catch {
            XCTAssertEqual(error as? AccountClient.Failure, .removed)
        }
    }
}
