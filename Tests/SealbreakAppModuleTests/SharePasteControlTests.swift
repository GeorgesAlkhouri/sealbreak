import Foundation
import Observation
import SwiftUI
import Testing
import UIKit
import XCTest
@testable import SealbreakAppModule
@testable import SealbreakCore

@Suite(.serialized)
@MainActor
struct SharePasteControlTests {
    // Synthetic format-only values; never use real Shamir shares in tests.
    private let share = "0123456789abcdef0123456789abcdef"
    private let clipboardMarker = "clipboard must remain unchanged"

    @Test(arguments: [ScenePhase.inactive, .background])
    func sceneInterruptionDiscardsDelayedPasteAfterReturningActive(phase: ScenePhase) async throws {
        let host = try PasteHost()
        defer { host.close() }
        let target = try await host.target()
        let provider = DelayedPasteProvider()
        UIPasteboard.general.string = clipboardMarker

        target.paste(itemProviders: [provider])
        host.environment.phase = phase
        try await waitUntil { provider.progress.isCancelled }
        host.environment.phase = .active
        provider.complete(share)

        await host.expectNoResult()
        #expect(UIPasteboard.general.string == clipboardMarker)
    }

    @Test
    func screenCaptureDiscardsDelayedPasteAfterCaptureEnds() async throws {
        let host = try PasteHost()
        defer { host.close() }
        let target = try await host.target()
        let provider = DelayedPasteProvider()
        UIPasteboard.general.string = clipboardMarker

        target.paste(itemProviders: [provider])
        host.environment.isCaptured = true
        try await waitUntil { provider.progress.isCancelled }
        host.environment.isCaptured = false
        provider.complete(share)

        await host.expectNoResult()
        #expect(UIPasteboard.general.string == clipboardMarker)
    }

    @Test
    func removingPasteControlDiscardsDelayedPaste() async throws {
        let host = try PasteHost()
        defer { host.close() }
        // Retain the UIKit target so only dismantleUIView can invalidate its load.
        let target = try await host.target()
        let provider = DelayedPasteProvider()
        UIPasteboard.general.string = clipboardMarker

        target.paste(itemProviders: [provider])
        host.environment.showsControl = false
        try await waitUntil { provider.progress.isCancelled }
        provider.complete(share)

        await host.expectNoResult()
        #expect(UIPasteboard.general.string == clipboardMarker)
        withExtendedLifetime(target) {}
    }

    @Test
    func newerPasteDiscardsOlderResultBeforeAcceptingCurrentShare() async throws {
        let host = try PasteHost()
        defer { host.close() }
        let target = try await host.target()
        let older = DelayedPasteProvider()
        let current = DelayedPasteProvider()
        UIPasteboard.general.string = clipboardMarker

        target.paste(itemProviders: [older])
        target.paste(itemProviders: [current])
        #expect(older.progress.isCancelled)
        older.complete("abcdef0123456789abcdef0123456789")
        await host.expectNoResult()
        #expect(UIPasteboard.general.string == clipboardMarker)

        current.complete(share)
        try await waitUntil { !host.results.isEmpty }
        #expect(host.results == [.success(share)])
        #expect(!UIPasteboard.general.hasStrings)
    }

    @Test
    func validPasteClearsClipboardBeforeDeliveringNormalizedShare() async throws {
        let host = try PasteHost()
        defer { host.close() }
        let target = try await host.target()
        let provider = DelayedPasteProvider()
        UIPasteboard.general.string = clipboardMarker

        target.paste(itemProviders: [provider])
        provider.complete(" \(share)\n")
        try await waitUntil { !host.results.isEmpty }

        #expect(host.results == [.success(share)])
        #expect(host.clipboardWasEmptyOnDelivery == [true])
        #expect(!UIPasteboard.general.hasStrings)
    }

    @Test
    func invalidPastePreservesClipboardAndReportsValidationFailure() async throws {
        let host = try PasteHost()
        defer { host.close() }
        let target = try await host.target()
        let provider = DelayedPasteProvider()
        UIPasteboard.general.string = clipboardMarker

        target.paste(itemProviders: [provider])
        provider.complete("not-a-share")
        try await waitUntil { !host.results.isEmpty }

        guard case .failure(let failure) = try #require(host.results.first) else {
            Issue.record("Invalid input must not be delivered as a share.")
            return
        }
        #expect(failure.feedback.level == .error)
        #expect(String(localized: failure.feedback.text) == "Enter one hexadecimal or Base64 Shamir share.")
        #expect(UIPasteboard.general.string == clipboardMarker)
    }

    @Test
    func failedProviderLoadPreservesClipboardAndReportsGenericFeedback() async throws {
        let host = try PasteHost()
        defer { host.close() }
        let target = try await host.target()
        let provider = DelayedPasteProvider()
        UIPasteboard.general.string = clipboardMarker

        target.paste(itemProviders: [provider])
        provider.fail(NSError(domain: "sensitive-provider-detail", code: 1))
        try await waitUntil { !host.results.isEmpty }

        guard case .failure(let failure) = try #require(host.results.first) else {
            Issue.record("A provider failure must not be delivered as a share.")
            return
        }
        #expect(String(localized: failure.feedback.text) == "Operation failed. No sensitive diagnostic data was recorded.")
        #expect(UIPasteboard.general.string == clipboardMarker)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() {
            try #require(ContinuousClock.now < deadline, "Paste lifecycle event did not arrive.")
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

@Observable
@MainActor
private final class PasteEnvironment {
    var phase: ScenePhase = .active
    var isCaptured = false
    var showsControl = true
}

@MainActor
private struct PasteTestView: View {
    let environment: PasteEnvironment
    let onPaste: (Result<String, AppFailure>) -> Void

    var body: some View {
        Group {
            if environment.showsControl {
                SharePasteControl(disabled: false, onPaste: onPaste)
            }
        }
        .environment(\.scenePhase, environment.phase)
        .environment(\.isSceneCaptured, environment.isCaptured)
    }
}

@MainActor
private final class PasteHost {
    let environment = PasteEnvironment()
    private let window: UIWindow
    private var controller: UIHostingController<PasteTestView>?
    private(set) var results: [Result<String, AppFailure>] = []
    private(set) var clipboardWasEmptyOnDelivery: [Bool] = []
    private var unexpectedResult: XCTestExpectation?

    init() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        window = UIWindow(windowScene: scene)
        let controller = UIHostingController(rootView: PasteTestView(environment: environment) { [weak self] result in
            self?.results.append(result)
            self?.clipboardWasEmptyOnDelivery.append(!UIPasteboard.general.hasStrings)
            self?.unexpectedResult?.fulfill()
        })
        self.controller = controller
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
    }

    func target() async throws -> UIView {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while true {
            if let view = controller?.view,
               let control = pasteControl(in: view), let target = control.target as? UIView {
                return target
            }
            try #require(ContinuousClock.now < deadline, "System paste control was not mounted.")
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func expectNoResult() async {
        #expect(results.isEmpty)
        let expectation = XCTestExpectation(description: "Invalidated paste must not deliver a result")
        expectation.isInverted = true
        unexpectedResult = expectation
        let outcome = await XCTWaiter.fulfillment(of: [expectation], timeout: 0.1)
        unexpectedResult = nil
        #expect(outcome == .completed)
        #expect(results.isEmpty)
    }

    func close() {
        window.isHidden = true
        window.rootViewController = nil
        controller = nil
        UIPasteboard.general.items = []
    }

    private func pasteControl(in view: UIView) -> UIPasteControl? {
        if let control = view as? UIPasteControl {
            return control
        }
        return view.subviews.lazy.compactMap { self.pasteControl(in: $0) }.first
    }
}

// Only the OS provider completion is controlled; the production views, load
// coordinator, validation and clipboard side effects run unchanged.
private final class DelayedPasteProvider: NSItemProvider, @unchecked Sendable {
    let progress = Progress(totalUnitCount: 1)
    private var completion: (@Sendable ((any NSItemProviderReading)?, Error?) -> Void)?

    override init() {
        super.init()
        registerObject(NSString(string: "synthetic provider representation"), visibility: .all)
    }

    override func loadObject(
        ofClass aClass: any NSItemProviderReading.Type,
        completionHandler: @escaping @Sendable ((any NSItemProviderReading)?, Error?) -> Void
    ) -> Progress {
        completion = completionHandler
        return progress
    }

    func complete(_ value: String) {
        completion?(NSString(string: value), nil)
        completion = nil
    }

    func fail(_ error: Error) {
        completion?(nil, error)
        completion = nil
    }
}
