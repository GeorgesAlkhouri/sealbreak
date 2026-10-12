import AccessibilitySnapshotParser
import ComposableArchitecture
import Foundation
@testable import SealbreakCore
import SwiftUI
import UIKit
import XCTest
@testable import SealbreakAppModule

@MainActor
final class HomeLayoutTests: XCTestCase {
    func testOfflineStatusRefreshKeepsPrimaryActionPositionForEveryStatus() async throws {
        let sealed = SealStatus(
            type: "shamir",
            initialized: true,
            sealed: true,
            t: 3,
            n: 5,
            progress: 0,
            migration: false,
            recoverySeal: false
        )
        let unsealed = SealStatus(
            type: "shamir",
            initialized: true,
            sealed: false,
            t: 3,
            n: 5,
            progress: 0,
            migration: false,
            recoverySeal: false
        )

        for status in [nil, sealed, unsealed] {
            try await assertOfflineRefreshDoesNotMoveButton(initialStatus: status)
        }
    }

    private func assertOfflineRefreshDoesNotMoveButton(initialStatus: SealStatus?) async throws {
        let profile = try ServerProfile(
            id: UUID(),
            name: "Server",
            address: "https://bao.example.com",
            product: .openBao
        )
        let failure = AppFailure(
            "Connection failed or timed out. Check the network, VPN, DNS, and the configured server endpoint."
        )
        let offline = DelayedOfflineStatus()
        var client = SealbreakClient.testValue
        client.waitForForeground = {}
        client.status = { _ in try await offline.check() }

        let homeStore = Store(
            initialState: HomeFeature.State(
                profile: profile,
                status: initialStatus,
                feedback: failure.feedback
            )
        ) {
            HomeFeature()
        } withDependencies: {
            $0.sealbreakClient = client
        }
        let privacyStore = Store(initialState: PrivacyFeature.State()) {
            PrivacyFeature()
        }
        let host = try PrivacyViewHost {
            NavigationStack {
                HomeView(store: homeStore, privacyStore: privacyStore)
            }
            .environment(\.locale, Locale(identifier: "en_US"))
        }
        defer { host.close() }

        let initialLabel = initialStatus?.sealed == true ? "Unseal with Face ID" : "Check status"
        try await host.waitUntil {
            host.accessibility.contains(initialLabel)
                && host.accessibility.contains("Connection failed or timed out")
        }
        let before = try buttonCenter(in: host, label: initialLabel)

        // The reducer removes the error message while the network request is pending.
        let refresh = homeStore.send(.refreshTapped)
        try await host.waitUntil {
            homeStore.operation == .checkingStatus
                && host.accessibility.contains("Checking seal status")
                && !host.accessibility.contains("Connection failed or timed out")
        }
        let pending = try buttonCenter(in: host, label: "Checking seal status…")

        await offline.fail()
        await refresh.finish()
        try await host.waitUntil {
            homeStore.operation == nil
                && host.accessibility.contains("Check status")
                && host.accessibility.contains("Connection failed or timed out")
        }
        let after = try buttonCenter(in: host, label: "Check status")

        XCTAssertEqual(before.x, pending.x, accuracy: 1)
        XCTAssertEqual(before.y, pending.y, accuracy: 1, "Hiding feedback must not move the button.")
        XCTAssertEqual(before.x, after.x, accuracy: 1)
        XCTAssertEqual(before.y, after.y, accuracy: 1, "Restoring feedback must not move the button.")
    }

    private func buttonCenter(in host: PrivacyViewHost, label: String) throws -> CGPoint {
        let elements = AccessibilityHierarchyParser()
            .parseAccessibilityHierarchy(in: host.window)
            .flattenToElements()
        let button = try XCTUnwrap(
            elements.first(where: { $0.label == label }),
            "Expected primary home action labeled \(label)."
        )
        return CGPoint(
            x: button.activationPoint.x,
            y: button.activationPoint.y
        )
    }
}

private actor DelayedOfflineStatus {
    private var continuation: CheckedContinuation<SealStatus, Error>?
    private var failed = false

    func check() async throws -> SealStatus {
        if failed {
            throw AppFailure("Connection failed or timed out.")
        }
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func fail() {
        failed = true
        continuation?.resume(throwing: AppFailure(
            "Connection failed or timed out. Check the network, VPN, DNS, and the configured server endpoint."
        ))
        continuation = nil
    }
}
