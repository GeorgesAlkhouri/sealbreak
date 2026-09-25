import Foundation
import ComposableArchitecture
import Testing
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
            (.unknown, "UNKNOWN", "Status unknown", "Check status before sending", 0.20),
            (.checking(activity: ""), "CHECKING", "", "Please keep the app open", 0.66),
            (.checking(activity: "Checking target…"), "CHECKING", "Checking target…", "Please keep the app open", 0.66),
            (.sealed(progress: 1, threshold: 3, supportsUnseal: true), "SEALED", "1 of 3 shares submitted", "Shamir seal", 1.0 / 3.0),
            (.sealed(progress: 1, threshold: 0, supportsUnseal: false), "SEALED", "1 of 0 shares submitted", "Manual unseal unavailable", 0),
            (.sealed(progress: -1, threshold: 3, supportsUnseal: true), "SEALED", "-1 of 3 shares submitted", "Shamir seal", 0),
            (.sealed(progress: 5, threshold: 3, supportsUnseal: true), "SEALED", "5 of 3 shares submitted", "Shamir seal", 1),
            (.unsealing(activity: "Submitting one share…"), "UNSEALING", "Submitting one share…", "Please keep the app open", 0.66),
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
    func primaryActionMapsLabelsIconsAndAvailability() {
        let cases: [(
            action: HomeViewState.PrimaryAction,
            title: LocalizedStringResource,
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
            #expect(item.action.title == item.title)
            #expect(item.action.systemImage == item.systemImage)
            #expect(item.action.enabled == item.enabled)
        }
    }

    @Test
    func viewStateMapsEveryOperationToVisibleActivity() throws {
        let profile = try ServerProfile(id: UUID(), name: "Server", address: "https://bao.example.com/")
        let operations: [(HomeFeature.State.Operation, HomeViewState.Status, LocalizedStringResource)] = [
            (.checkingStatus, .checking(activity: "Checking seal status…"), "Checking seal status…"),
            (.checkingTarget, .unsealing(activity: "Checking target…"), "Checking target…"),
            (.waitingForFaceID, .unsealing(activity: "Waiting for Face ID…"), "Waiting for Face ID…"),
            (.submittingShare, .unsealing(activity: "Submitting one share…"), "Submitting one share…"),
            (.verifyingStatus, .unsealing(activity: "Verifying seal status…"), "Verifying seal status…"),
            (.removingLocalData, .checking(activity: "Removing local data…"), "Removing local data…")
        ]

        for (operation, expectedStatus, expectedActivity) in operations {
            let state = HomeViewState(
                profile: profile,
                sealStatus: nil,
                operation: operation,
                notice: "Hidden while busy"
            )

            #expect(state.serverName == "Server")
            #expect(state.origin == "bao.example.com")
            #expect(state.status == expectedStatus)
            #expect(state.primaryAction == .working(title: expectedActivity))
            #expect(state.notice == nil)
            #expect(state.isBusy)
        }
    }

    @Test
    func viewStateMapsUnknownSealedAndUnsealedStates() throws {
        let profile = try ServerProfile(id: UUID(), name: "Server", address: "https://bao.example.com")

        let unknown = HomeViewState(
            profile: profile,
            sealStatus: nil,
            operation: nil,
            notice: "Check the configured target."
        )
        #expect(unknown.status == .unknown)
        #expect(unknown.primaryAction == .checkStatus(enabled: true))
        #expect(unknown.notice == "Check the configured target.")
        #expect(!unknown.isBusy)

        let sealed = HomeViewState(
            profile: profile,
            sealStatus: sealStatus(sealed: true, supportsUnseal: true),
            operation: nil,
            notice: "Ignored"
        )
        #expect(sealed.status == .sealed(progress: 1, threshold: 3, supportsUnseal: true))
        #expect(sealed.primaryAction == .unseal(enabled: true))
        #expect(sealed.notice == nil)

        let unsupported = HomeViewState(
            profile: profile,
            sealStatus: sealStatus(sealed: true, supportsUnseal: false),
            operation: nil,
            notice: "Ignored"
        )
        #expect(unsupported.primaryAction == .unseal(enabled: false))

        let unsealed = HomeViewState(
            profile: profile,
            sealStatus: sealStatus(sealed: false, supportsUnseal: true),
            operation: nil,
            notice: "Ignored"
        )
        #expect(unsealed.status == .unsealed)
        #expect(unsealed.primaryAction == .checkStatus(enabled: true))
        #expect(unsealed.notice == nil)
    }

    @Test
    func serverDetailsRoutesUserIntentThroughDelegates() async throws {
        let profile = try ServerProfile(id: UUID(), name: "Server", address: "https://bao.example.com")
        let store = TestStore(
            initialState: ServerDetailsFeature.State(
                profile: profile,
                status: nil,
                isBusy: false,
                activity: nil,
                notice: ""
            )
        ) {
            ServerDetailsFeature()
        }

        await store.send(.refreshTapped)
        await store.receive(.delegate(.refreshRequested))
        await store.send(.doneTapped)
        await store.receive(.delegate(.dismissRequested))
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
