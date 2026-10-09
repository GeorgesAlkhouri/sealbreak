import AccessibilitySnapshot
import AccessibilitySnapshotParser
import ComposableArchitecture
import Foundation
import Observation
import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import SealbreakAppModule
@testable import SealbreakCore

// Fixed iPhone 17 / iOS 26.5, light appearance, English, default Dynamic Type.
// Actions below are component integration, not simulated end-to-end touches.
@MainActor
final class PrivacyViewTests: XCTestCase {
    override func invokeTest() {
        let recording = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"] == "all"
        withSnapshotTesting(record: recording ? .all : .never) { super.invokeTest() }
    }

    func testPrivacyGateMapsPhaseAndCaptureEnvironmentToConcealment() async throws {
        let environment = PrivacyEnvironment()
        let store = Store(initialState: PrivacyFeature.State()) { PrivacyFeature() }
        let button = UIButton(type: .system)
        button.setTitle("Synthetic protected action", for: .normal)
        let host = try PrivacyViewHost {
            PrivacyGate(store: store) {
                NativeButtonProbe(button: button).frame(width: 240, height: 60)
            }.privacyTestEnvironment(environment)
        }
        defer { host.close() }
        try await host.waitUntil { !store.isConcealed && host.accessibility.contains("Synthetic protected action") }
        let point = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: host.window)
        XCTAssertTrue(host.window.hitTest(point, with: nil)?.isDescendant(of: button) == true)
        try host.snapshot("gate-visible")

        environment.phase = .inactive
        try await host.waitUntil { store.isConcealed && host.accessibility.contains("Sealbreak locked") }
        XCTAssertTrue(!host.accessibility.contains("Synthetic protected action"))
        XCTAssertTrue(host.window.hitTest(point, with: nil)?.isDescendant(of: button) != true)
        try host.snapshot("gate-inactive")

        environment.phase = .active
        try await host.waitUntil { !store.isConcealed && host.accessibility.contains("Synthetic protected action") }
        XCTAssertTrue(host.window.hitTest(point, with: nil)?.isDescendant(of: button) == true)
        environment.captured = true
        try await host.waitUntil { store.isCaptured && host.accessibility.contains("Screen capture blocked") }
        XCTAssertTrue(!host.accessibility.contains("Synthetic protected action"))
        XCTAssertTrue(host.window.hitTest(point, with: nil)?.isDescendant(of: button) != true)
        try host.snapshot("gate-captured")
    }

    func testRootHomeIsVisiblyConcealedAndReturnsWithPositiveContent() async throws {
        let fixture = try PrivacyRootFixture()
        defer { fixture.close() }
        try await fixture.host.waitUntil { fixture.host.accessibility.contains(fixture.profile.name) }
        XCTAssertTrue(fixture.host.accessibility.contains("Unseal"))
        try fixture.host.snapshot("root-home-visible")
        fixture.environment.phase = .inactive
        try await fixture.host.waitUntil { fixture.host.accessibility.contains("Sealbreak locked") }
        XCTAssertTrue(!fixture.host.accessibility.contains(fixture.profile.name))
        XCTAssertTrue(!fixture.host.accessibility.contains("Unseal"))
        try fixture.host.snapshot("root-home-inactive")
        fixture.environment.phase = .active
        try await fixture.host.waitUntil { fixture.host.accessibility.contains(fixture.profile.name) }
        XCTAssertTrue(!fixture.store.privacy.isConcealed)
    }

    func testPresentedSheetsStayPresentedAndConcealOnInactive() async throws {
        for sheet in PrivacySheet.allCases {
            let fixture = try PrivacyRootFixture()
            defer { fixture.close() }
            try await fixture.present(sheet)
            let presented = try XCTUnwrap(fixture.host.controller.presentedViewController)
            XCTAssertTrue(fixture.host.accessibility.contains(sheet.visibleLabel))
            if sheet == .details {
                fixture.start(.home(.serverDetails(.presented(.shareFragmentTapped))))
                try await fixture.waitForPendingFragment()
                fixture.probe.succeed(fixture.fragment)
                try await fixture.host.waitUntil { fixture.host.accessibility.contains(fixture.fragment.displayValue) }
            }
            try fixture.host.snapshot("\(sheet)-visible")

            fixture.environment.phase = .inactive
            try await fixture.host.waitUntil { fixture.store.privacy.isConcealed && fixture.host.accessibility.contains("Sealbreak locked") }
            XCTAssertTrue(fixture.host.controller.presentedViewController === presented)
            XCTAssertTrue(sheet == .details ? fixture.store.home?.serverDetails != nil : fixture.store.home?.replaceShare != nil)
            XCTAssertTrue(!fixture.host.accessibility.contains(sheet.visibleLabel))
            XCTAssertTrue(!fixture.host.accessibility.contains(fixture.fragment.displayValue))
            try fixture.host.snapshot("\(sheet)-inactive")

            fixture.environment.phase = .active
            try await fixture.host.waitUntil { fixture.host.accessibility.contains(sheet.visibleLabel) }
            XCTAssertTrue(fixture.host.controller.presentedViewController === presented)
            XCTAssertTrue(!fixture.store.privacy.isConcealed)
            if sheet == .details { XCTAssertTrue(fixture.host.accessibility.contains(fixture.fragment.displayValue)) }
            if sheet == .details {
                fixture.store.send(.home(.serverDetails(.presented(.shareFragmentTapped))))
                for authorization in fixture.authorizations { try await fixture.host.finish(authorization) }
            }
        }
    }

    func testActualDetailsViewRequiresAuthorizationAndShowsOnlyTransientFragment() async throws {
        let fixture = try PrivacyRootFixture()
        defer { fixture.close() }
        try await fixture.present(.details)
        XCTAssertTrue(fixture.host.accessibility.contains("Hidden"))
        XCTAssertTrue(!fixture.host.accessibility.contains(fixture.fragment.displayValue))
        try fixture.host.snapshot("fragment-initial-hidden")

        let deniedAuthorization = fixture.start(.home(.serverDetails(.presented(.shareFragmentTapped))))
        try await fixture.host.waitUntil { fixture.probe.pendingCount == 1 && fixture.store.home?.serverDetails?.isRevealingShare == true }
        XCTAssertTrue(!fixture.host.accessibility.contains(fixture.fragment.displayValue))
        XCTAssertTrue(!fixture.host.accessibility.contains(PrivacyRootFixture.share))
        try fixture.host.snapshot("fragment-pending")
        fixture.probe.fail()
        try await fixture.host.finish(deniedAuthorization)
        try await fixture.host.waitUntil { fixture.store.home?.serverDetails?.isRevealingShare == false && fixture.host.accessibility.contains("Hidden") }
        try fixture.host.snapshot("fragment-denied-hidden")

        let firstAuthorization = fixture.start(.home(.serverDetails(.presented(.shareFragmentTapped))))
        try await fixture.host.waitUntil { fixture.probe.pendingCount == 1 }
        fixture.probe.succeed(fixture.fragment)
        try await fixture.host.waitUntil { fixture.host.accessibility.contains(fixture.fragment.displayValue) }
        XCTAssertTrue(fixture.fragment.displayValue == "012 … def")
        XCTAssertTrue(!fixture.host.accessibility.contains(PrivacyRootFixture.share))
        try fixture.host.snapshot("fragment-authorized")
        fixture.store.send(.home(.serverDetails(.presented(.shareFragmentTapped))))
        try await fixture.host.finish(firstAuthorization)
        try await fixture.host.waitUntil { fixture.host.accessibility.contains("Hidden") }
        try fixture.host.snapshot("fragment-manually-hidden")

        let repeatedAuthorization = fixture.start(.home(.serverDetails(.presented(.shareFragmentTapped))))
        try await fixture.host.waitUntil { fixture.probe.pendingCount == 1 }
        XCTAssertTrue(fixture.probe.requestCount == 3)
        XCTAssertTrue(!fixture.host.accessibility.contains(fixture.fragment.displayValue))
        fixture.probe.succeed(fixture.fragment)
        try await fixture.host.waitUntil { fixture.host.accessibility.contains(fixture.fragment.displayValue) }
        await fixture.clock.advance(by: .seconds(19))
        XCTAssertTrue(fixture.store.home?.serverDetails?.shareFragment == fixture.fragment)
        XCTAssertTrue(fixture.host.accessibility.contains(fixture.fragment.displayValue))
        await fixture.clock.advance(by: .seconds(1))
        try await fixture.host.finish(repeatedAuthorization)
        try await fixture.host.waitUntil { fixture.host.accessibility.contains("Hidden") }
        XCTAssertTrue(fixture.store.home?.serverDetails?.shareFragment == nil)
        try fixture.host.snapshot("fragment-expired-hidden")
    }

    func testBackgroundAndCaptureDismissDetailsAndRejectDelayedAuthorization() async throws {
        for interruption in PrivacyInterruption.allCases {
            for alreadyAuthorized in [false, true] {
                let fixture = try PrivacyRootFixture()
                defer { fixture.close() }
                try await fixture.present(.details)
                let authorization = fixture.start(.home(.serverDetails(.presented(.shareFragmentTapped))))
                try await fixture.waitForPendingFragment()
                if alreadyAuthorized {
                    fixture.probe.succeed(fixture.fragment)
                    try await fixture.host.waitUntil { fixture.host.accessibility.contains(fixture.fragment.displayValue) }
                    try fixture.host.snapshot("details-authorized-before-interruption")
                }
                if interruption == .background {
                    fixture.environment.phase = .background
                } else {
                    fixture.environment.captured = true
                }
                try await fixture.host.waitUntil { fixture.store.home?.serverDetails == nil && fixture.probe.cancelCount > 0 }
                try await fixture.host.waitUntil { fixture.host.controller.presentedViewController == nil }
                if !alreadyAuthorized {
                    try await fixture.host.waitUntil { fixture.probe.fragmentWasCancelled }
                    fixture.probe.succeed(fixture.fragment)
                }
                await fixture.clock.advance(by: .seconds(20))
                try await fixture.host.finish(authorization)
                XCTAssertTrue(fixture.store.home?.serverDetails == nil)
                XCTAssertTrue(!fixture.host.accessibility.contains(fixture.fragment.displayValue))
                XCTAssertTrue(!fixture.host.accessibility.contains(PrivacyRootFixture.share))
                try fixture.host.snapshot("details-after-\(interruption)")
            }
        }
    }

    func testBackgroundAndCaptureDismissReplacementAndDiscardPendingSave() async throws {
        for interruption in PrivacyInterruption.allCases {
            let fixture = try PrivacyRootFixture()
            defer { fixture.close() }
            try await fixture.present(.replacement)
            let authorization = fixture.start(.home(.replaceShare(.presented(.saveTapped(share: PrivacyRootFixture.share)))))
            try await fixture.host.waitUntil { fixture.probe.pendingReplacementCount == 1 }
            if interruption == .background {
                fixture.environment.phase = .background
            } else {
                fixture.environment.captured = true
            }
            try await fixture.host.waitUntil { fixture.store.home?.replaceShare == nil && fixture.probe.cancelCount > 0 }
            try await fixture.host.waitUntil { fixture.host.controller.presentedViewController == nil && fixture.probe.replacementWasCancelled }
            fixture.probe.completeReplacement()
            try await fixture.host.finish(authorization)
            await fixture.clock.advance(by: .zero)
            XCTAssertTrue(fixture.store.home?.replaceShare == nil)
            XCTAssertTrue(!fixture.host.accessibility.contains(PrivacyRootFixture.share))
        }
    }
}

enum PrivacySheet: CaseIterable {
    case details, replacement
    var visibleLabel: String { self == .details ? "Server details" : "Local share" }
}

enum PrivacyInterruption: CaseIterable { case background, capture }

@Observable
@MainActor
final class PrivacyEnvironment {
    var phase: ScenePhase = .active
    var captured = false
}

private extension View {
    func privacyTestEnvironment(_ environment: PrivacyEnvironment) -> some View {
        modifier(PrivacyTestEnvironment(environment: environment))
    }
}

private struct PrivacyTestEnvironment: ViewModifier {
    let environment: PrivacyEnvironment
    func body(content: Content) -> some View {
        content.environment(\.scenePhase, environment.phase)
            .environment(\.isSceneCaptured, environment.captured)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.dynamicTypeSize, .large)
            .preferredColorScheme(.light)
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
    }
}

private struct NativeButtonProbe: UIViewRepresentable {
    let button: UIButton
    func makeUIView(context: Context) -> UIButton { button }
    func updateUIView(_ uiView: UIButton, context: Context) {}
}

@MainActor
final class PrivacyViewHost {
    let window: UIWindow
    let controller: UIHostingController<AnyView>
    private let previousAnimations = UIView.areAnimationsEnabled

    init<Content: View>(@ViewBuilder content: () -> Content) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.overrideUserInterfaceStyle = .light
        controller = UIHostingController(rootView: AnyView(content()))
        window.rootViewController = controller
        UIView.setAnimationsEnabled(false)
        UIPasteboard.general.string = PrivacyRootFixture.share
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
    }

    var accessibility: String {
        AccessibilityHierarchyParser().parseAccessibilityHierarchy(in: window).flattenToElements()
            .map(\.description).joined(separator: "\n") + "\n"
    }

    var pasteControlIsEnabled: Bool {
        let elements = AccessibilityHierarchyParser().parseAccessibilityHierarchy(in: window).flattenToElements()
        guard let paste = elements.first(where: { $0.label == "Paste" }) else { return false }
        // Read the real UIKit control at the parser's public activation point.
        // This is a readiness check; it does not activate the accessibility element.
        var view = window.hitTest(CGPoint(x: paste.activationPoint.x, y: paste.activationPoint.y), with: nil)
        while let candidate = view {
            if let control = candidate as? UIPasteControl { return control.isEnabled }
            view = candidate.superview
        }
        return false
    }

    func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() {
            _ = try XCTUnwrap(ContinuousClock.now < deadline ? true : nil, "Expected real view state did not appear.")
            try await Task.sleep(for: .milliseconds(10))
        }
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(60))
    }

    func snapshot(_ name: String, file: StaticString = #filePath, testName: String = #function) throws {
        freezeSpinners(in: window)
        var captured = false
        let renderer = makeRenderer()
        let image = renderer.image { _ in
            captured = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        _ = try XCTUnwrap(captured ? true : nil, "UIKit must capture the current hosted window without reparenting it.")
        let png = try XCTUnwrap(image.pngData())
        let format = try XCTUnwrap(renderer.format as? UIGraphicsImageRendererFormat)
        XCTContext.runActivity(named: "Snapshot diagnostics: \(name)") { activity in
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = "actual-\(name).png"
            attachment.lifetime = .keepAlways
            activity.add(attachment)
            let traits = XCTAttachment(string: """
            OS: \(ProcessInfo.processInfo.operatingSystemVersionString)
            Bounds: \(window.bounds), safe area: \(window.safeAreaInsets)
            Display scale: \(window.traitCollection.displayScale), gamut: \(window.traitCollection.displayGamut.rawValue)
            Interface style: \(window.traitCollection.userInterfaceStyle.rawValue), contrast: \(window.traitCollection.accessibilityContrast.rawValue)
            Content size: \(window.traitCollection.preferredContentSizeCategory.rawValue)
            Reduce motion: \(UIAccessibility.isReduceMotionEnabled), reduce transparency: \(UIAccessibility.isReduceTransparencyEnabled)
            Darker colors: \(UIAccessibility.isDarkerSystemColorsEnabled), bold text: \(UIAccessibility.isBoldTextEnabled)
            Renderer scale: \(format.scale), range: \(format.preferredRange.rawValue)
            Image pixels: \(image.cgImage?.width ?? 0)x\(image.cgImage?.height ?? 0), bits: \(image.cgImage?.bitsPerComponent ?? 0)
            Color space: \(String(describing: image.cgImage?.colorSpace))
            """)
            traits.name = "rendering-traits-\(name)"
            traits.lifetime = .keepAlways
            activity.add(traits)
        }
        assertSnapshot(of: image, as: .image, named: name, file: file, testName: testName)
        assertSnapshot(of: accessibility, as: .lines, named: "\(name)-accessibility", file: file, testName: testName)
    }

    func preparePresentedMaterials() async throws {
        // Prime the presented native materials before taking the comparison image.
        // Discard the preparatory render and let the next run loop draw settle.
        var rendered = false
        _ = makeRenderer().image { _ in
            rendered = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        _ = try XCTUnwrap(rendered ? true : nil, "UIKit must prepare the presented sheet's materials.")
        await Task.yield()
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(60))
    }

    private func makeRenderer() -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat(for: window.traitCollection)
        // Fix the capture's color range before exact pixel comparison.
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(bounds: window.bounds, format: format)
    }

    private func freezeSpinners(in view: UIView) {
        if let indicator = view as? UIActivityIndicatorView {
            // Keep exact references independent of the native spinner's animation phase.
            indicator.layer.speed = 0
            indicator.layer.timeOffset = 0
        }
        for child in view.subviews { freezeSpinners(in: child) }
    }

    func finish(_ operation: StoreTask) async throws {
        let completion = XCTestExpectation(description: "The real store effect must finish after its reply or timer ends")
        let waiter = Task { await operation.finish(); completion.fulfill() }
        defer { waiter.cancel() }
        let result = await XCTWaiter.fulfillment(of: [completion], timeout: 3)
        _ = try XCTUnwrap(result == .completed ? true : nil, "The store effect did not finish.")
    }

    func close() {
        controller.dismiss(animated: false)
        window.isHidden = true
        window.rootViewController = nil
        UIPasteboard.general.items = []
        UIView.setAnimationsEnabled(previousAnimations)
    }
}

@MainActor
final class PrivacyRootFixture {
    static let share = "0123456789abcdef0123456789abcdef"
    let environment = PrivacyEnvironment()
    let probe = PrivacyClientProbe()
    let clock = TestClock<Duration>()
    let profile: ServerProfile
    let fragment = ShareComparisonFragment(validatedShare: share)
    let store: StoreOf<AppFeature>
    let host: PrivacyViewHost
    var authorizations: [StoreTask] = []

    @discardableResult
    func start(_ action: AppFeature.Action) -> StoreTask {
        let operation = store.send(action)
        authorizations.append(operation)
        return operation
    }

    init() throws {
        profile = try ServerProfile(id: UUID(), name: "P1 Synthetic Vault", address: "https://bao.example.com", product: .openBao)
        var initial = AppFeature.State()
        initial.isLoading = false
        initial.didLoad = true
        initial.privacy.phase = .active
        initial.home = HomeFeature.State(profile: profile, status: Self.status)
        let probe = probe
        let clock = clock
        store = Store(initialState: initial) { AppFeature() } withDependencies: {
            $0.sealbreakClient = Self.client(probe)
            $0.continuousClock = clock
        }
        let store = store
        let environment = environment
        host = try PrivacyViewHost { SealbreakRootView(store: store).privacyTestEnvironment(environment) }
    }

    static let status = SealStatus(type: "shamir", initialized: true, sealed: true, t: 3, n: 5, progress: 1, migration: false, recoverySeal: false)

    static func client(_ probe: PrivacyClientProbe) -> SealbreakClient {
        var client = SealbreakClient.testValue
        let status = Self.status
        client.status = { _ in status }
        client.waitForForeground = {}
        client.requireForeground = {}
        client.cancelSensitiveOperation = { await probe.cancel() }
        client.readShareFragment = { _, _ in try await probe.authorizeFragment() }
        client.replaceShare = { _, _, _ in try await probe.authorizeReplacement() }
        client.readShare = { _, _ in await probe.forbidden("readShare"); throw AppFailure("Forbidden synthetic access") }
        client.submit = { _ in await probe.forbidden("submit"); throw AppFailure("Forbidden synthetic access") }
        client.protectNewProfile = { _, _, _ in await probe.forbidden("protectNewProfile"); throw AppFailure("Forbidden synthetic access") }
        client.removeLocalProfile = { _, _ in await probe.forbidden("removeLocalProfile"); throw AppFailure("Forbidden synthetic access") }
        client.resetLocalData = { await probe.forbidden("resetLocalData"); throw AppFailure("Forbidden synthetic access") }
        return client
    }

    func present(_ sheet: PrivacySheet) async throws {
        try await host.waitUntil { host.accessibility.contains(profile.name) }
        store.send(.home(sheet == .details ? .serverDetailsTapped : .replaceShareTapped))
        try await host.waitUntil { host.controller.presentedViewController != nil && host.accessibility.contains(sheet.visibleLabel) }
        try await host.waitUntil { host.controller.presentedViewController?.transitionCoordinator == nil }
        if sheet == .replacement { try await host.waitUntil { host.pasteControlIsEnabled } }
        try await host.preparePresentedMaterials()
    }

    func waitForPendingFragment() async throws {
        try await host.waitUntil {
            let accessibility = host.accessibility
            return probe.pendingCount == 1
                && accessibility.contains("Done. Dimmed. Button.")
                && accessibility.contains("Show stored share fragment: Hidden. Dimmed. Button.")
                && !accessibility.contains(fragment.displayValue)
        }
        // Commit the actual disabled, concealed view before releasing authorization.
        try await host.preparePresentedMaterials()
    }

    func close() {
        store.send(.home(.privacyInterrupted))
        for operation in authorizations { operation.cancel() }
        probe.close()
        XCTAssertTrue(probe.forbiddenCalls.isEmpty)
        host.close()
    }
}

@MainActor
final class PrivacyClientProbe {
    private var fragmentReply: CheckedContinuation<ShareComparisonFragment, Error>?
    private var replacementReply: CheckedContinuation<Void, Error>?
    private(set) var requestCount = 0
    private(set) var cancelCount = 0
    private(set) var forbiddenCalls: [String] = []
    private let fragmentCancellation = CancellationReceipt()
    private let replacementCancellation = CancellationReceipt()
    var fragmentWasCancelled: Bool { fragmentCancellation.received }
    var replacementWasCancelled: Bool { replacementCancellation.received }
    var pendingCount: Int { fragmentReply == nil ? 0 : 1 }
    var pendingReplacementCount: Int { replacementReply == nil ? 0 : 1 }

    func authorizeFragment() async throws -> ShareComparisonFragment {
        requestCount += 1
        let cancellation = fragmentCancellation
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { fragmentReply = $0 }
        } onCancel: {
            cancellation.record()
        }
    }
    func authorizeReplacement() async throws {
        let cancellation = replacementCancellation
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { replacementReply = $0 }
        } onCancel: {
            cancellation.record()
        }
    }
    func succeed(_ fragment: ShareComparisonFragment) {
        let reply = fragmentReply
        fragmentReply = nil
        reply?.resume(returning: fragment)
    }
    func fail() {
        let reply = fragmentReply
        fragmentReply = nil
        reply?.resume(throwing: AppFailure("Synthetic authorization denied"))
    }
    func completeReplacement() {
        let reply = replacementReply
        replacementReply = nil
        reply?.resume()
    }
    func forbidden(_ operation: String) {
        forbiddenCalls.append(operation)
    }
    func cancel() { cancelCount += 1 }
    func close() {
        fail()
        let reply = replacementReply
        replacementReply = nil
        reply?.resume(throwing: CancellationError())
    }
}

private final class CancellationReceipt: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var received: Bool { lock.withLock { value } }
    func record() { lock.withLock { value = true } }
}
