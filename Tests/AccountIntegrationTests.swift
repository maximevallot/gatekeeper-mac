import XCTest

/// The Mac's account client against the real relay running locally (`npm run dev:account` in ~/gatekeeper-relay-0.3,
/// with a fake Claude). Skipped unless GATEKEEPER_RELAY_IT names it, e.g.
/// `TEST_RUNNER_GATEKEEPER_RELAY_IT=http://127.0.0.1:8787 xcodebuild … test`.
final class AccountIntegrationTests: XCTestCase {
    var relay: URL!

    override func setUpWithError() throws {
        guard let s = ProcessInfo.processInfo.environment["GATEKEEPER_RELAY_IT"], let url = URL(string: s) else {
            throw XCTSkip("set GATEKEEPER_RELAY_IT to a relay running the account (wrangler dev)")
        }
        relay = url
    }

    /// A stand-in browser: POST to the account with its token.
    func browser(_ path: String, _ body: [String: Any], token: String? = nil) async throws -> (Int, [String: Any]) {
        var r = URLRequest(url: relay.appendingPathComponent(path))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: r)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:])
    }

    func testTheMacJoinsByCodeShowsTodayStartsExamModeAndIsRemoved() async throws {
        // A browser creates the person's Gatekeeper and finishes its welcome.
        let (_, created) = try await browser("/account/create", ["v": 1, "device": ["name": "Brave", "kind": "extension"], "tz": "America/New_York"])
        let token = try XCTUnwrap((created["device"] as? [String: Any])?["token"] as? String)
        let now = Date().timeIntervalSince1970 * 1000
        let (setupStatus, setup) = try await browser("/account/sync", [
            "v": 1, "now": now, "tz": "America/New_York", "spans": [],
            "requests": [["id": "s1", "type": "setup", "kinds": ["social": 15, "video": 20, "games": 0], "goal": "Finish problem set 4"]],
        ], token: token)
        XCTAssertEqual(setupStatus, 200, "\(setup)")

        // Settings › Add a device.
        let (_, coded) = try await browser("/account/code", ["v": 1], token: token)
        let code = try XCTUnwrap(coded["code"] as? String)

        // The Mac joins with it and gets Today.
        let client = AccountClient(relay: relay)
        let joined = try await client.join(code: code)
        let today = try XCTUnwrap(joined.today, "the join answer carries today for a Mac")
        XCTAssertEqual(today.goal, "Finish problem set 4")
        XCTAssertEqual(Ring.rings(from: today).map(\.name), ["Social", "Video", "Games"])
        XCTAssertEqual(Ring.rings(from: today).last?.state, .closedAllDay)

        // The code works once.
        do { _ = try await client.join(code: code); XCTFail("a used code joined") } catch {
            XCTAssertEqual(error as? AccountClient.Failure, .badCode("bad_code"))
        }

        // The Mac starts exam mode; the account confirms it, and the Mac holds it.
        let until = Date().addingTimeInterval(2 * 3600)
        let m = joined.membership
        let synced = try await client.sync(m, have: nil, requests: [
            ["id": "m1", "type": "startExam", "source": "mac", "until": AccountClient.millis(until), "goal": "Midterm"],
        ])
        XCTAssertNotNil(synced.results["m1"], "the request got an answer")
        XCTAssertNil(synced.results["m1"]?["refused"], "\(String(describing: synced.results["m1"]))")
        let examToday = try XCTUnwrap(synced.today)
        XCTAssertEqual(examToday.exam?.goal, "Midterm")
        let held = Follow.hold(nil, seeing: examToday)
        XCTAssertNotNil(Follow.confirmedExam(held, now: Date()))
        XCTAssertTrue(examToday.kinds.allSatisfy { $0.status == "closed" }, "exam mode closes every kind")

        // Asking again with the version it holds: nothing changed.
        let again = try await client.sync(m, have: synced.version, requests: [])
        XCTAssertTrue(again.unchanged || again.today != nil)

        // The Mac cannot loosen: ending exam mode from the Mac is refused.
        let end = try await client.sync(m, have: nil, requests: [["id": "m2", "type": "endExam"]])
        XCTAssertNotNil(end.results["m2"]?["refused"], "\(String(describing: end.results["m2"]))")

        // The browser removes the Mac (a lost laptop); the Mac is told so.
        let (removeStatus, _) = try await browser("/account/remove", ["v": 1, "deviceId": m.deviceId], token: token)
        XCTAssertEqual(removeStatus, 200)
        do { _ = try await client.sync(m, have: nil, requests: []); XCTFail("a removed Mac synced") } catch {
            XCTAssertEqual(error as? AccountClient.Failure, .removed)
        }
    }
}
