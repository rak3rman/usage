import Testing
@testable import UsageKit

@Suite struct OAuthCallbackTests {
    private func parse(_ target: String) -> CallbackOutcome {
        OAuthCallback.parse(
            requestHead: "GET \(target) HTTP/1.1\r\nHost: localhost\r\n\r\n",
            path: "/callback", state: "expected")
    }

    @Test func returnsTheCode() {
        #expect(parse("/callback?code=abc&state=expected") == .code("abc"))
    }

    @Test func refusesAnotherSignInsState() {
        #expect(parse("/callback?code=abc&state=other") == .stateMismatch)
        #expect(parse("/callback?code=abc&state=expected&state=expected") == .stateMismatch)
    }

    @Test func reportsADeniedConsent() {
        #expect(parse("/callback?error=access_denied&state=expected") == .denied("access_denied"))
    }

    @Test(arguments: ["/favicon.ico", "/callback", "//evil.example/callback?code=abc&state=expected"])
    func ignoresOtherRequests(target: String) {
        #expect(parse(target) == .unrelated)
    }
}
