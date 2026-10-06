import Foundation
import Testing
@testable import SealbreakAppModule
@testable import SealbreakCore

@MainActor
struct HomeViewStateTests {
    @Test
    func statusPresentationMapsEveryPhase() {
        let cases: [(
            status: HomeViewState.Status,
            title: String,
            primaryDetail: String,
            secondaryDetail: String,
            progress: Double
        )] = [
            (.unknown, "UNKNOWN", "Status unknown", "Check status before sending", 0),
            (.sealed(progress: 1, threshold: 3, supportsUnseal: true), "SEALED", "1 of 3 shares submitted", "Shamir seal", 1.0 / 3.0),
            (.sealed(progress: 1, threshold: 0, supportsUnseal: false), "SEALED", "1 of 0 shares submitted", "Manual unseal unavailable", 0),
            (.sealed(progress: -1, threshold: 3, supportsUnseal: true), "SEALED", "-1 of 3 shares submitted", "Shamir seal", 0),
            (.sealed(progress: 5, threshold: 3, supportsUnseal: true), "SEALED", "5 of 3 shares submitted", "Shamir seal", 1),
            (.unsealed, "UNSEALED", "Server is available", "Status checked", 1)
        ]

        for item in cases {
            #expect(String(localized: item.status.title) == item.title)
            #expect(String(localized: item.status.primaryDetail) == item.primaryDetail)
            #expect(String(localized: item.status.secondaryDetail) == item.secondaryDetail)
            #expect(item.status.progressFraction == item.progress)
        }
    }

    @Test
    func primaryActionMapsLabelsIconsAndAvailability() throws {
        let cases: [(
            action: HomeViewState.PrimaryAction,
            title: String,
            systemImage: String,
            enabled: Bool
        )] = [
            (.checkStatus(enabled: true), "Check status", "arrow.clockwise", true),
            (.checkStatus(enabled: false), "Check status", "arrow.clockwise", false),
            (.unseal(enabled: true), "Unseal with Face ID", "faceid", true),
            (.unseal(enabled: false), "Unseal with Face ID", "faceid", false),
            (.working(title: ""), "", "hourglass", false),
            (.working(title: "Verifying seal status…"), "Verifying seal status…", "hourglass", false)
        ]

        for item in cases {
            #expect(String(localized: item.action.title) == item.title)
            if case .working(let title) = item.action {
                #expect(item.action.title == title)
            }
            #expect(item.action.systemImage == item.systemImage)
            #expect(item.action.enabled == item.enabled)
        }

        let title = HomeViewState.PrimaryAction.checkStatus(enabled: true).title
        guard case .atURL(let bundleURL) = title.bundle else {
            Issue.record("The action title must use its module resource bundle.")
            return
        }
        let bundle = try #require(Bundle(url: bundleURL))
        #expect(bundle.bundleURL.lastPathComponent == "Sealbreak_SealbreakAppModule.bundle")
    }

    @Test
    func viewStateKeepsServerStatusStableWhileWorking() throws {
        let profile = try ServerProfile(id: UUID(), name: "Server", address: "https://bao.example.com/")
        let currentStatus = sealStatus(sealed: true, supportsUnseal: true)
        let expectedStatus = HomeViewState.Status.sealed(
            progress: 1,
            threshold: 3,
            supportsUnseal: true
        )
        let operations: [(
            operation: HomeFeature.State.Operation,
            activity: String
        )] = [
            (.checkingStatus, "Checking seal status…"),
            (.checkingTarget, "Checking target…"),
            (.waitingForFaceID, "Waiting for Face ID…"),
            (.submittingShare, "Submitting one share…"),
            (.verifyingStatus, "Verifying seal status…"),
            (.removingLocalData, "Removing local data…")
        ]

        for item in operations {
            let state = HomeViewState(
                profile: profile,
                sealStatus: currentStatus,
                operation: item.operation,
                feedback: .warning("Hidden while busy")
            )

            #expect(state.serverName == "Server")
            #expect(state.origin == "bao.example.com")
            #expect(state.status == expectedStatus)
            #expect(state.primaryAction == .working(title: item.operation.activity))
            #expect(String(localized: item.operation.activity) == item.activity)
            #expect(state.feedback == nil)
            #expect(state.isBusy)
        }

        let checkingWithoutKnownStatus = HomeViewState(
            profile: profile,
            sealStatus: nil,
            operation: .checkingStatus,
            feedback: .warning("Hidden while busy")
        )
        #expect(checkingWithoutKnownStatus.status == .unknown)
    }

    @Test
    func viewStateMapsFeedbackBySeverity() throws {
        let profile = try ServerProfile(id: UUID(), name: "Server", address: "https://bao.example.com")
        let sealedStatus = sealStatus(sealed: true, supportsUnseal: true)

        let unknown = HomeViewState(
            profile: profile,
            sealStatus: nil,
            operation: nil,
            feedback: .error("Check the configured target.")
        )
        #expect(unknown.status == .unknown)
        #expect(unknown.primaryAction == .checkStatus(enabled: true))
        #expect(unknown.feedback == .error("Check the configured target."))
        #expect(!unknown.isBusy)

        let sealedInfo = HomeViewState(
            profile: profile,
            sealStatus: sealedStatus,
            operation: nil,
            feedback: .info("Ignored")
        )
        #expect(sealedInfo.status == .sealed(progress: 1, threshold: 3, supportsUnseal: true))
        #expect(sealedInfo.primaryAction == .unseal(enabled: true))
        #expect(sealedInfo.feedback == nil)

        let sealedError = HomeViewState(
            profile: profile,
            sealStatus: sealedStatus,
            operation: nil,
            feedback: .error("Face ID failed")
        )
        #expect(sealedError.status == .sealed(progress: 1, threshold: 3, supportsUnseal: true))
        #expect(sealedError.feedback == .error("Face ID failed"))

        let unsupported = HomeViewState(
            profile: profile,
            sealStatus: sealStatus(sealed: true, supportsUnseal: false),
            operation: nil,
            feedback: .warning("Manual unseal unavailable")
        )
        #expect(unsupported.primaryAction == .unseal(enabled: false))
        #expect(unsupported.feedback == .warning("Manual unseal unavailable"))

        let unsealed = HomeViewState(
            profile: profile,
            sealStatus: sealStatus(sealed: false, supportsUnseal: true),
            operation: nil,
            feedback: .success("Checked")
        )
        #expect(unsealed.status == .unsealed)
        #expect(unsealed.primaryAction == .checkStatus(enabled: true))
        #expect(unsealed.feedback == nil)
    }

    @Test
    func unsealPreflightFailureClearsStaleStatusBeforeShareAccess() throws {
        let profile = try ServerProfile(id: UUID(), name: "Server", address: "https://bao.example.com")
        let viewState = HomeViewState(
            profile: profile,
            sealStatus: nil,
            operation: nil,
            feedback: .error("status failed")
        )
        #expect(viewState.primaryAction == .checkStatus(enabled: true))
    }

    @Test
    func homeFeedbackPreservesKnownStatusBeforeSubmissionAndClearsUncertainState() throws {
        let profile = try ServerProfile(id: UUID(), name: "Server", address: "https://bao.example.com")
        let status = sealStatus(sealed: true, supportsUnseal: true)
        let sourceText = HomeViewState.Status.unknown.primaryDetail
        let failure = AppFailure(sourceText)
        #expect(normalizedAppFailure(failure).feedback.text == sourceText)

        #expect(
            HomeViewState(
                profile: profile,
                sealStatus: status,
                operation: nil,
                feedback: failure.feedback
            ).feedback == failure.feedback
        )
    }

    @Test
    func stalePasteLoadIsDiscardedAfterInvalidation() async {
        let coordinator = SharePasteLoadCoordinator()
        let progress = Progress(totalUnitCount: 1)
        var completion: ((NSString?, Error?) -> Void)?
        var received: Result<String, AppFailure>?

        coordinator.start(
            using: { handler in
                completion = handler
                return progress
            },
            onResult: { received = $0 }
        )

        coordinator.invalidate()
        completion?(NSString(string: "0123456789abcdef0123456789abcdef"), nil)
        await Task.yield()

        #expect(progress.isCancelled)
        #expect(received == nil)
    }

    @Test
    func pasteProviderFailureIsReportedWithoutRawProviderDetails() async {
        struct ProviderFailure: Error {}

        let coordinator = SharePasteLoadCoordinator()
        let progress = Progress(totalUnitCount: 1)
        var completion: ((NSString?, Error?) -> Void)?
        var received: Result<String, AppFailure>?

        coordinator.start(
            using: { handler in
                completion = handler
                return progress
            },
            onResult: { received = $0 }
        )

        completion?(nil, ProviderFailure())
        await Task.yield()

        guard case .failure(let failure) = received else {
            Issue.record("Expected paste provider failure.")
            return
        }

        #expect(String(localized: failure.feedback.text) == "Operation failed. No sensitive diagnostic data was recorded.")
    }

    private func sealStatus(sealed: Bool, supportsUnseal: Bool) -> SealStatus {
        SealStatus(
            type: supportsUnseal ? "shamir" : "transit",
            initialized: true,
            sealed: sealed,
            t: 3,
            n: 5,
            progress: 1,
            migration: false,
            recoverySeal: supportsUnseal ? false : true
        )
    }
}
