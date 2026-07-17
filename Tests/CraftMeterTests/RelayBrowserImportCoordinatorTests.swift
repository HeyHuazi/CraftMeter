import OhMyUsageDomain
import XCTest
@testable import OhMyUsage

final class RelayBrowserImportCoordinatorTests: XCTestCase {
    func testDiscoveryRequiresUserIDAfterFindingBearer() {
        let coordinator = makeCoordinator(bearer: "secret-browser-token")
        let draft = makeDraft(userID: "")

        let result = coordinator.discover(draft: draft, manifest: RelayAdapterRegistry.genericManifest)

        XCTAssertEqual(result.nextAction, .enterUserID)
        XCTAssertEqual(result.credentialSource, "Auto:Test")
        XCTAssertEqual(result.credentialKind, "Bearer")
        XCTAssertFalse(result.message.contains("secret-browser-token"))
    }

    func testDiscoveryCanVerifyWhenUserIDExists() {
        let coordinator = makeCoordinator(bearer: "secret-browser-token")
        let draft = makeDraft(userID: "42")

        let result = coordinator.discover(draft: draft, manifest: RelayAdapterRegistry.genericManifest)

        XCTAssertEqual(result.nextAction, .verify)
        XCTAssertEqual(result.host, "relay.example.com")
        XCTAssertFalse(result.message.contains("secret-browser-token"))
    }

    func testDiscoveryFallsBackWhenNoBrowserCredentialExists() {
        let coordinator = RelayBrowserImportCoordinator(
            browserCredentialService: BrowserCredentialService(
                bearerCandidatesOverride: { _ in [] },
                cookieHeaderOverride: { _ in nil },
                cacheTTL: 0
            )
        )

        let result = coordinator.discover(
            draft: makeDraft(userID: "42"),
            manifest: RelayAdapterRegistry.genericManifest
        )

        XCTAssertEqual(result.nextAction, .manualFallback)
        XCTAssertNil(result.credentialSource)
    }

    private func makeCoordinator(bearer: String) -> RelayBrowserImportCoordinator {
        RelayBrowserImportCoordinator(
            browserCredentialService: BrowserCredentialService(
                bearerCandidatesOverride: { _ in
                    [BrowserDetectedCredential(value: bearer, source: "Auto:Test")]
                },
                cookieHeaderOverride: { _ in nil },
                cacheTTL: 0
            )
        )
    }

    private func makeDraft(userID: String) -> RelaySettingsDraft {
        let provider = ProviderDescriptor.makeOpenRelay(
            name: "Relay",
            baseURL: "https://relay.example.com",
            preferredAdapterID: "generic-newapi"
        )
        var draft = RelaySettingsDraft(provider: provider, preferredAdapterID: "generic-newapi")
        draft.userID = userID
        return draft
    }
}
