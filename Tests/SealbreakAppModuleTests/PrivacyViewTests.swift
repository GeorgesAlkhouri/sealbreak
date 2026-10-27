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
    withMainSerialExecutor {
      withSnapshotTesting(record: recording ? .all : .never) { super.invokeTest() }
    }
  }

  func testImmediateHideCancelsExpiryBeforeItsSleepStarts() async throws {
    let fixture = try PrivacyRootFixture()
    defer { fixture.close() }
    try await fixture.present(.details)
    fixture.start(.home(.serverDetails(.presented(.shareFragmentTapped))))
    try await fixture.host.waitUntil { fixture.probe.pendingCount == 1 }
    fixture.probe.succeed(fixture.fragment)
    // Hide on publication, before the expiry task gets a chance to sleep.
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while fixture.store.home?.serverDetails?.shareFragment == nil {
      if ContinuousClock.now >= deadline {
        XCTFail("Fragment did not appear")
        return
      }
      await Task.yield()
    }
    fixture.store.send(.home(.serverDetails(.presented(.shareFragmentTapped))))
    XCTAssertNil(fixture.store.home?.serverDetails?.shareFragment)
    await fixture.clock.advance()
    do {
      try await fixture.clock.checkSuspension()
    } catch {
      XCTFail(
        "Hiding the fragment must leave no expiry sleep: \(String(reflecting: type(of: error)))")
    }
  }

  func testPrivacyGateMapsPhaseAndCaptureEnvironmentToConcealment() async throws {
    let environment = PrivacyEnvironment()
    environment.phase = .inactive
    let store = Store(initialState: PrivacyFeature.State()) { PrivacyFeature() }
    let button = UIButton(type: .system)
    button.setTitle("Synthetic protected action", for: .normal)
    let host = try PrivacyViewHost {
      PrivacyGate(store: store) {
        NativeButtonProbe(button: button).frame(width: 240, height: 60)
      }.privacyTestEnvironment(environment)
    }
    defer { host.close() }
    try await host.waitUntil {
      host.visibleWindow !== host.window && host.accessibility.contains("Sealbreak locked")
    }
    environment.captured = true
    try await host.waitUntil { host.accessibility.contains("Screen capture blocked") }
    environment.captured = false
    environment.phase = .active
    try await host.waitUntil {
      !store.isConcealed && host.accessibility.contains("Synthetic protected action")
    }
    let point = button.convert(
      CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: host.window)
    XCTAssertTrue(host.window.hitTest(point, with: nil)?.isDescendant(of: button) == true)
    try host.snapshot("gate-visible")

    environment.phase = .inactive
    try await host.waitUntil {
      store.isConcealed && host.accessibility.contains("Sealbreak locked")
    }
    XCTAssertTrue(!host.accessibility.contains("Synthetic protected action"))
    for window in [host.window, host.visibleWindow] {
      XCTAssertFalse(window.hitTest(point, with: nil)?.isDescendant(of: button) == true)
      XCTAssertFalse(host.accessibility(in: window).contains("Synthetic protected action"))
    }
    try host.snapshot("gate-inactive")

    environment.phase = .active
    try await host.waitUntil {
      !store.isConcealed && host.accessibility.contains("Synthetic protected action")
    }
    XCTAssertTrue(host.window.hitTest(point, with: nil)?.isDescendant(of: button) == true)
    environment.captured = true
    try await host.waitUntil {
      store.isCaptured && host.accessibility.contains("Screen capture blocked")
    }
    XCTAssertTrue(!host.accessibility.contains("Synthetic protected action"))
    for window in [host.window, host.visibleWindow] {
      XCTAssertFalse(window.hitTest(point, with: nil)?.isDescendant(of: button) == true)
      XCTAssertFalse(host.accessibility(in: window).contains("Synthetic protected action"))
    }
    try host.snapshot("gate-captured")
  }

  func testRootHomeIsVisiblyConcealedAndReturnsWithPositiveContent() async throws {
    let fixture = try PrivacyRootFixture()
    defer { fixture.close() }
    let host = fixture.host
    try await host.waitUntil { host.accessibility.contains(fixture.profile.name) }
    XCTAssertTrue(host.accessibility.contains("Unseal"))
    try host.snapshot("root-home-visible")
    let scene = try XCTUnwrap(host.window.windowScene)
    let keyWindow = scene.keyWindow
    let dialog = UIAlertController(
      title: "Synthetic private dialog", message: nil, preferredStyle: .actionSheet)
    dialog.addAction(UIAlertAction(title: "Synthetic protected action", style: .default))
    dialog.popoverPresentationController?.sourceView = host.controller.view
    host.controller.present(dialog, animated: false)
    try await host.waitUntil {
      dialog.viewIfLoaded?.window != nil && dialog.transitionCoordinator == nil
    }
    let overlay = UIWindow(windowScene: scene)
    overlay.windowLevel = .alert + 1
    overlay.rootViewController = UIHostingController(rootView: Text("Synthetic overlay action"))
    overlay.isHidden = false
    defer {
      overlay.isHidden = true
      overlay.rootViewController = nil
    }
    for captured in [false, true] {
      fixture.environment.phase = captured ? .active : .inactive
      fixture.environment.captured = captured
      try await host.waitUntil {
        host.visibleWindow !== host.window && fixture.store.privacy.isConcealed
      }
      let shield = host.visibleWindow
      XCTAssertGreaterThan(shield.windowLevel, overlay.windowLevel)
      XCTAssertEqual(shield.bounds, scene.effectiveGeometry.coordinateSpace.bounds)
      XCTAssertIdentical(scene.keyWindow, keyWindow)
      XCTAssertFalse(shield.canBecomeKey)
      XCTAssertTrue(shield.rootViewController?.view.accessibilityViewIsModal == true)
      XCTAssertNotNil(
        shield.hitTest(CGPoint(x: shield.bounds.midX, y: shield.bounds.midY), with: nil))
      XCTAssertTrue(
        host.accessibility.contains(captured ? "Screen capture blocked" : "Sealbreak locked"))
      for protected in [
        fixture.profile.name, "Unseal", "Synthetic protected action", "Synthetic overlay action",
      ] {
        XCTAssertFalse(host.accessibility.contains(protected))
      }
      try host.assertOpaque(shield)
      if !captured { try host.snapshot("root-home-inactive") }
      fixture.environment.phase = .active
      fixture.environment.captured = false
      try await host.waitUntil { !fixture.store.privacy.isConcealed && shield.isHidden }
      XCTAssertIdentical(scene.keyWindow, keyWindow)
      XCTAssertIdentical(host.controller.presentedViewController, dialog)
    }
    fixture.environment.phase = .inactive
    try await host.waitUntil { host.visibleWindow !== host.window }
    let shield = host.visibleWindow
    host.controller.rootView = AnyView(Text("Replacement root"))
    try await host.waitUntil { shield.isHidden }
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
        try await fixture.host.waitUntil {
          fixture.host.accessibility.contains(fixture.fragment.displayValue)
        }
      }
      try fixture.host.snapshot("\(sheet)-visible")

      fixture.environment.phase = .inactive
      try await fixture.host.waitUntil {
        fixture.store.privacy.isConcealed && fixture.host.accessibility.contains("Sealbreak locked")
      }
      XCTAssertTrue(fixture.host.controller.presentedViewController === presented)
      XCTAssertTrue(
        sheet == .details
          ? fixture.store.home?.serverDetails != nil : fixture.store.home?.replaceShare != nil)
      XCTAssertTrue(!fixture.host.accessibility.contains(sheet.visibleLabel))
      XCTAssertTrue(!fixture.host.accessibility.contains(fixture.fragment.displayValue))
      try fixture.host.snapshot("\(sheet)-inactive")

      fixture.environment.phase = .active
      try await fixture.host.waitUntil { fixture.host.accessibility.contains(sheet.visibleLabel) }
      XCTAssertTrue(fixture.host.controller.presentedViewController === presented)
      XCTAssertTrue(!fixture.store.privacy.isConcealed)
      if sheet == .details {
        XCTAssertTrue(fixture.host.accessibility.contains(fixture.fragment.displayValue))
      }
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
    try await fixture.host.waitUntil {
      fixture.probe.pendingCount == 1 && fixture.store.home?.serverDetails?.isRevealingShare == true
    }
    XCTAssertTrue(!fixture.host.accessibility.contains(fixture.fragment.displayValue))
    XCTAssertTrue(!fixture.host.accessibility.contains(PrivacyRootFixture.share))
    try fixture.host.snapshot("fragment-pending")
    fixture.probe.fail()
    try await fixture.host.finish(deniedAuthorization)
    try await fixture.host.waitUntil {
      fixture.store.home?.serverDetails?.isRevealingShare == false
        && fixture.host.accessibility.contains("Hidden")
    }
    try fixture.host.snapshot("fragment-denied-hidden")

    let firstAuthorization = fixture.start(.home(.serverDetails(.presented(.shareFragmentTapped))))
    try await fixture.host.waitUntil { fixture.probe.pendingCount == 1 }
    fixture.probe.succeed(fixture.fragment)
    try await fixture.host.waitUntil {
      fixture.host.accessibility.contains(fixture.fragment.displayValue)
    }
    XCTAssertTrue(fixture.fragment.displayValue == "012 … def")
    XCTAssertTrue(!fixture.host.accessibility.contains(PrivacyRootFixture.share))
    try fixture.host.snapshot("fragment-authorized")
    fixture.store.send(.home(.serverDetails(.presented(.shareFragmentTapped))))
    try await fixture.host.finish(firstAuthorization)
    try await fixture.host.waitUntil { fixture.host.accessibility.contains("Hidden") }
    try fixture.host.snapshot("fragment-manually-hidden")

    let repeatedAuthorization = fixture.start(
      .home(.serverDetails(.presented(.shareFragmentTapped))))
    try await fixture.host.waitUntil { fixture.probe.pendingCount == 1 }
    XCTAssertTrue(fixture.probe.requestCount == 3)
    XCTAssertTrue(!fixture.host.accessibility.contains(fixture.fragment.displayValue))
    fixture.probe.succeed(fixture.fragment)
    try await fixture.host.waitUntil {
      fixture.host.accessibility.contains(fixture.fragment.displayValue)
    }
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
          try await fixture.host.waitUntil {
            fixture.host.accessibility.contains(fixture.fragment.displayValue)
          }
          try fixture.host.snapshot("details-authorized-before-interruption")
          fixture.environment.phase = .inactive
          try await fixture.host.waitUntil { fixture.store.privacy.phase == .inactive }
          XCTAssertEqual(fixture.store.home?.serverDetails?.shareFragment, fixture.fragment)
        }
        if interruption == .background {
          fixture.environment.phase = .background
        } else {
          fixture.environment.captured = true
        }
        try await fixture.host.waitUntil {
          fixture.store.home?.serverDetails == nil && fixture.probe.cancelCount > 0
        }
        try await fixture.host.waitUntil { fixture.host.controller.presentedViewController == nil }
        if !alreadyAuthorized {
          try await fixture.host.waitUntil { fixture.probe.fragmentWasCancelled }
          fixture.probe.succeed(fixture.fragment)
        }
        await fixture.clock.advance(by: .seconds(20))
        try await fixture.host.finish(authorization)
        XCTAssertTrue(fixture.store.home?.serverDetails == nil)
        XCTAssertEqual(fixture.probe.cancelCount, 1)
        XCTAssertNil(fixture.store.home?.status)
        XCTAssertTrue(fixture.store.privacy.isConcealed, "The environment still requests privacy.")
        try await fixture.host.waitUntil {
          fixture.host.accessibility.contains(
            interruption == .capture ? "Screen capture blocked" : "Sealbreak locked")
        }
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
      let authorization = fixture.start(
        .home(.replaceShare(.presented(.saveTapped(share: PrivacyRootFixture.share)))))
      try await fixture.host.waitUntil { fixture.probe.pendingReplacementCount == 1 }
      if interruption == .background {
        fixture.environment.phase = .background
      } else {
        fixture.environment.captured = true
      }
      try await fixture.host.waitUntil {
        fixture.store.home?.replaceShare == nil && fixture.probe.cancelCount > 0
      }
      try await fixture.host.waitUntil {
        fixture.host.controller.presentedViewController == nil
          && fixture.probe.replacementWasCancelled
      }
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

extension View {
  fileprivate func privacyTestEnvironment(_ environment: PrivacyEnvironment) -> some View {
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
      .transaction {
        $0.animation = nil
        $0.disablesAnimations = true
      }
  }
}

private struct NativeButtonProbe: UIViewRepresentable {
  let button: UIButton
  func makeUIView(context _: Context) -> UIButton { button }
  func updateUIView(_: UIButton, context _: Context) {}
}

@MainActor
final class PrivacyViewHost {
  // SnapshotTesting documents 98–99% perceptual precision for small color variations.
  // Keep every pixel within that limit, including when waiting for glass to settle.
  static let imageStrategy: Snapshotting<UIImage, UIImage> = .image(
    precision: 1, perceptualPrecision: 0.98)

  let window: UIWindow
  let controller: UIHostingController<AnyView>
  private let previousAnimations = UIView.areAnimationsEnabled

  init<Content: View>(animationsEnabled: Bool = false, @ViewBuilder content: () -> Content) throws {
    let scene = try XCTUnwrap(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    window = UIWindow(windowScene: scene)
    window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
    window.overrideUserInterfaceStyle = .light
    controller = UIHostingController(rootView: AnyView(content()))
    window.rootViewController = controller
    UIView.setAnimationsEnabled(animationsEnabled)
    UIPasteboard.general.string = PrivacyRootFixture.share
    window.makeKeyAndVisible()
    controller.view.layoutIfNeeded()
  }

  var accessibilityElements: [AccessibilityElement] {
    AccessibilityHierarchyParser().parseAccessibilityHierarchy(in: visibleWindow)
      .flattenToElements()
  }

  var visibleWindow: UIWindow {
    window.windowScene?.windows.first { $0 is PrivacyShieldWindow && !$0.isHidden } ?? window
  }

  var accessibility: String { accessibility(in: visibleWindow) }

  func accessibility(in window: UIWindow) -> String {
    AccessibilityHierarchyParser().parseAccessibilityHierarchy(in: window).flattenToElements()
      .map(\.description).joined(separator: "\n") + "\n"
  }

  var pasteControlIsEnabled: Bool {
    guard let paste = accessibilityElements.first(where: { $0.label == "Paste" }) else {
      return false
    }
    // Read the real UIKit control at the parser's public activation point.
    // This is a readiness check; it does not activate the accessibility element.
    var view = window.hitTest(
      CGPoint(x: paste.activationPoint.x, y: paste.activationPoint.y), with: nil)
    while let candidate = view {
      if let control = candidate as? UIPasteControl { return control.isEnabled }
      view = candidate.superview
    }
    return false
  }

  func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line)
    async throws
  {
    // The gate reacts in one synchronous pass (shield, store, then one queued
    // cancel job), so this only bounds how long a loaded CI simulator takes to
    // deliver the environment change. A stalled main thread can spend the whole
    // budget before that work runs; check once more after it had a turn.
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while !condition() {
      if ContinuousClock.now >= deadline {
        try await Task.sleep(for: .milliseconds(10))
        _ = try XCTUnwrap(
          condition() ? true : nil,
          "Expected real view state did not appear. Accessibility: \(accessibility)",
          file: file, line: line
        )
        break
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    window.layoutIfNeeded()
    try await Task.sleep(for: .milliseconds(60))
  }

  func snapshot(_ name: String, file: StaticString = #filePath, testName: String = #function) throws
  {
    assertSnapshot(
      of: try renderImage(in: visibleWindow), as: Self.imageStrategy, named: name, file: file,
      testName: testName)
    assertSnapshot(
      of: accessibility, as: .lines, named: "\(name)-accessibility", file: file, testName: testName)
  }

  private func renderImage(in window: UIWindow) throws -> UIImage {
    freezeSpinners(in: window)
    let format = UIGraphicsImageRendererFormat(for: window.traitCollection)
    format.preferredRange = .standard
    var rendered = false
    let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
      rendered = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
    }
    _ = try XCTUnwrap(
      rendered ? true : nil, "UIKit must capture the hosted window without reparenting it.")
    return image
  }

  func assertOpaque(_ window: UIWindow) throws {
    let image = try XCTUnwrap(renderImage(in: window).cgImage)
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    try pixels.withUnsafeMutableBytes { buffer in
      let context = try XCTUnwrap(
        CGContext(
          data: buffer.baseAddress, width: image.width, height: image.height,
          bitsPerComponent: 8, bytesPerRow: image.width * 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    XCTAssertTrue(stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 255 })
  }

  func preparePresentedMaterials() async throws {
    // Native toolbar text can finish rasterizing after the sheet transition.
    // A single warm-up and fixed delay are insufficient on a busy CI simulator.
    // Use the same perceptual comparison as the snapshot assertion: harmless
    // glass color variations must not keep the preparation loop running.
    var previous: UIImage?
    var matchingCaptures = 0
    for capture in 0..<8 {
      window.layoutIfNeeded()
      let image = try renderImage(in: window)
      let matchesPrevious =
        previous.map { Self.imageStrategy.diffing.diffV2($0, image) == nil } ?? false
      matchingCaptures = matchesPrevious ? matchingCaptures + 1 : 0
      previous = image
      if capture >= 3, matchingCaptures >= 2 { return }
      await Task.yield()
      try await Task.sleep(for: .milliseconds(60))
    }
    XCTFail("Presented sheet rendering did not settle within eight captures.")
    throw NSError(domain: "PrivacyViewHost", code: 1)
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
    let completion = XCTestExpectation(
      description: "The real store effect must finish after its reply or timer ends")
    let waiter = Task {
      await operation.finish()
      completion.fulfill()
    }
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
    profile = try ServerProfile(
      id: UUID(), name: "P1 Synthetic Vault", address: "https://bao.example.com", product: .openBao)
    var initial = AppFeature.State()
    initial.didLoad = true
    initial.privacy.phase = .active
    initial.home = HomeFeature.State(profile: profile, status: Self.status)
    let probe = probe
    let clock = clock
    store = Store(initialState: initial) {
      AppFeature()
    } withDependencies: {
      $0.sealbreakClient = Self.client(probe)
      $0.continuousClock = clock
    }
    let store = store
    let environment = environment
    host = try PrivacyViewHost {
      SealbreakRootView(store: store).privacyTestEnvironment(environment)
    }
  }

  static let status = SealStatus(
    type: "shamir", initialized: true, sealed: true,
    quorum: .init(threshold: 3, totalShares: 5, progress: 1), migration: false,
    recoverySeal: false)

  static func client(_ probe: PrivacyClientProbe) -> SealbreakClient {
    var client = SealbreakClient.testValue
    let status = Self.status
    client.status = { _ in status }
    client.waitForForeground = {}
    client.requireForeground = {}
    client.cancelSensitiveOperation = { await probe.cancel() }
    client.readShareFragment = { _, _ in try await probe.authorizeFragment() }
    client.replaceShare = { _, _, _ in try await probe.authorizeReplacement() }
    client.readShare = { _, _ in
      await probe.forbidden("readShare")
      throw AppFailure("Forbidden synthetic access")
    }
    client.submit = { _ in
      await probe.forbidden("submit")
      throw AppFailure("Forbidden synthetic access")
    }
    client.protectNewProfile = { _, _, _ in
      await probe.forbidden("protectNewProfile")
      throw AppFailure("Forbidden synthetic access")
    }
    client.removeLocalProfile = { _, _ in
      await probe.forbidden("removeLocalProfile")
      throw AppFailure("Forbidden synthetic access")
    }
    client.resetLocalData = {
      await probe.forbidden("resetLocalData")
      throw AppFailure("Forbidden synthetic access")
    }
    return client
  }

  func present(_ sheet: PrivacySheet) async throws {
    try await host.waitUntil { host.accessibility.contains(profile.name) }
    store.send(.home(sheet == .details ? .serverDetailsTapped : .replaceShareTapped))
    try await host.waitUntil {
      host.controller.presentedViewController != nil
        && host.accessibility.contains(sheet.visibleLabel)
    }
    try await host.waitUntil {
      host.controller.presentedViewController?.transitionCoordinator == nil
    }
    if sheet == .replacement { try await host.waitUntil { host.pasteControlIsEnabled } }
    try await host.preparePresentedMaterials()
  }

  func waitForPendingFragment() async throws {
    try await host.waitUntil {
      let elements = host.accessibilityElements
      let done = elements.first { $0.label == "Done" }
      let reveal = elements.first { $0.label?.contains("Show stored share fragment") == true }
      return probe.pendingCount == 1
        && store.home?.serverDetails?.isRevealingShare == true
        && done?.traits.contains([.button, .notEnabled]) == true
        && reveal?.traits.contains([.button, .notEnabled]) == true
        && reveal?.value == "Hidden"
        && !elements.contains { $0.description.contains(fragment.displayValue) }
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
