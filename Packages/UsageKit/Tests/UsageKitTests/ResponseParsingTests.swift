import Foundation
import Testing
@testable import UsageKit

@Suite struct ClaudeUsageTests {
    @Test func readsSessionAndWeeklyFromLimitsAndSkipsScopedEntries() throws {
        let limits = try ClaudeUsage.parse(json("""
            {"five_hour":{"utilization":99,"resets_at":"2026-08-30T14:00:00.277644+00:00"},
             "limits":[
               {"kind":"session","percent":5,"resets_at":"2026-08-30T14:00:29.277644+00:00","scope":null},
               {"kind":"weekly_all","percent":70,"resets_at":null,"scope":{"model":{}}},
               {"kind":"weekly_all","percent":23,"resets_at":"2026-09-05T10:00:00.277667+00:00","scope":null},
               {"kind":"weekly_all","percent":"broken"},
               {"kind":"nimbus_quill","percent":3,"resets_at":null,"scope":null}]}
            """))
        #expect(limits.session == LimitWindow(
            percent: 5, resetsAt: Date(timeIntervalSince1970: 1_788_098_400)))
        #expect(limits.weekly?.percent == 23)
    }

    @Test func fallsBackToFiveHourAndSevenDay() throws {
        let limits = try ClaudeUsage.parse(json("""
            {"five_hour":{"utilization":41,"resets_at":null},
             "seven_day":{"utilization":66,"resets_at":null},
             "limits":[]}
            """))
        #expect(limits == Limits(
            session: LimitWindow(percent: 41, resetsAt: nil),
            weekly: LimitWindow(percent: 66, resetsAt: nil)))
    }

    @Test(arguments: ["not json", #"{"limits":[]}"#])
    func rejectsAResponseWithoutWindows(body: String) {
        #expect(throws: UsageError.self) { try ClaudeUsage.parse(json(body)) }
    }
}

@Suite struct CodexUsageTests {
    @Test func classifiesWindowsAndResolvesRelativeResets() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let report = try CodexUsage.parse(json("""
            {"plan_type":"plus","rate_limit":{
              "primary_window":{"used_percent":70,"limit_window_seconds":604800,"reset_after_seconds":120},
              "secondary_window":{"used_percent":25,"limit_window_seconds":18000,"reset_at":1800003600}}}
            """), now: now)
        #expect(report.plan == "Plus")
        #expect(report.limits.weekly == LimitWindow(percent: 70, resetsAt: now.addingTimeInterval(120)))
        #expect(report.limits.session == LimitWindow(
            percent: 25, resetsAt: Date(timeIntervalSince1970: 1_800_003_600)))
    }

    @Test(arguments: [
        #"{"rate_limit":{}}"#,
        #"{"rate_limit":{"primary_window":{"used_percent":101}}}"#,
        #"{"rate_limit":{"primary_window":{"used_percent":true}}}"#,
    ])
    func rejectsMissingOrOutOfRangeWindows(body: String) {
        #expect(throws: UsageError.self) { try CodexUsage.parse(json(body)) }
    }

    @Test func readsIdentityFromTheIDToken() throws {
        let claims = #"{"email":"someone@example.com","https://api.openai.com/auth":{"chatgpt_account_id":"acct-1","chatgpt_plan_type":"pro"}}"#
        let payload = PKCE.base64URL(Data(claims.utf8))
        let identity = try CodexIdentity.parse(idToken: "header.\(payload).signature")
        #expect(identity == CodexIdentity(accountID: "acct-1", name: "someone@example.com", plan: "Pro"))
    }
}

@Suite struct TokenTests {
    @Test(arguments: [
        #"{"error":"invalid_grant"}"#,
        #"{"error":{"code":"refresh_token_reused"}}"#,
    ])
    func recognisesARejectedRefreshToken(body: String) {
        #expect(throws: RefreshRejected.self) { try Tokens.refreshed(json(body), status: 400) }
    }

    @Test func treatsOtherRefreshFailuresAsTransient() {
        #expect(throws: UsageError.self) { try Tokens.refreshed(json(#"{"error":"server"}"#), status: 503) }
    }
}
