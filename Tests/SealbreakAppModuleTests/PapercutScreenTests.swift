import AccessibilitySnapshotParser
import ComposableArchitecture
import Foundation
import SwiftUI
import UIKit
import XCTest

@testable import SealbreakAppModule
@testable import SealbreakCore

@MainActor
final class PapercutScreenTests: XCTestCase {
  func testWelcomePrimaryActionsSendTheirFeatureActions() async throws {
    for requiresLocalReset in [false, true] {
      var actions = [WelcomeFeature.Action]()
      let store = Store(
        initialState: WelcomeFeature.State(requiresLocalReset: requiresLocalReset)
      ) {
        WelcomeFeature()
        Reduce { _, action in
          actions.append(action)
          return .none
        }
      }
      let host = try makeHost(size: CGSize(width: 402, height: 874)) {
        WelcomeView(store: store)
      }
      defer { host.close() }
      try await host.waitUntil {
        host.accessibilityElements.contains { $0.identifier == "welcome-primary-action" }
      }

      try activate(identifier: "welcome-primary-action", in: host)

      let expected: WelcomeFeature.Action =
        requiresLocalReset ? .resetLocalDataTapped : .setUpTapped
      try await host.waitUntil { actions.contains(expected) }
      XCTAssertEqual(actions.first, expected)
      XCTAssertEqual(store.confirmReset, requiresLocalReset)
      if !requiresLocalReset { XCTAssertTrue(actions.contains(.delegate(.setUp))) }
    }
  }

  func testHomePrimaryActionsRequestConfirmationOrRefresh() async throws {
    let profile = try makeProfile()
    let checkedStatus = PrivacyRootFixture.status
    for status in [checkedStatus, nil] {
      var actions = [HomeFeature.Action]()
      let store = Store(initialState: HomeFeature.State(profile: profile, status: status)) {
        HomeFeature()
        Reduce { _, action in
          actions.append(action)
          return .none
        }
      } withDependencies: {
        $0.sealbreakClient.waitForForeground = {}
        $0.sealbreakClient.status = { _ in checkedStatus }
      }
      let privacy = Store(initialState: PrivacyFeature.State()) { PrivacyFeature() }
      let host = try makeHost(size: CGSize(width: 402, height: 874)) {
        HomeView(store: store, privacyStore: privacy)
      }
      defer { host.close() }
      try await host.waitUntil {
        host.accessibilityElements.contains { $0.identifier == "home-primary-action" }
      }

      try activate(identifier: "home-primary-action", in: host)

      let expected: HomeFeature.Action = status == nil ? .refreshTapped : .unsealTapped
      try await host.waitUntil { actions.contains(expected) }
      XCTAssertEqual(actions.first, expected)
      if status == nil {
        try await host.waitUntil { store.operation == nil && store.status != nil }
        XCTAssertNil(store.confirmation)
      } else {
        XCTAssertEqual(store.confirmation, .unseal)
        XCTAssertNil(store.operation, "Unseal must await explicit confirmation.")
      }
    }
  }

  func testAppBundlesThirdPartyNotices() {
    let notices = ThirdPartyNoticesView.bundledNotices()

    XCTAssertTrue(notices.contains("Attribution: OpenBao project"))
    XCTAssertTrue(notices.contains("Vault and the Vault logo are trademarks of HashiCorp."))
    XCTAssertTrue(notices.contains("swift-composable-architecture"))
  }

  func testThirdPartyNoticesSheetShowsNoticesAndCloses() async throws {
    let profile = try makeProfile()
    let checkedStatus = PrivacyRootFixture.status
    let store = Store(
      initialState: HomeFeature.State(profile: profile, status: checkedStatus)
    ) {
      HomeFeature()
    } withDependencies: {
      $0.sealbreakClient.waitForForeground = {}
      $0.sealbreakClient.status = { _ in checkedStatus }
    }
    let privacy = Store(initialState: PrivacyFeature.State()) { PrivacyFeature() }
    let host = try makeHost(size: CGSize(width: 402, height: 874)) {
      HomeView(store: store, privacyStore: privacy, isShowingThirdPartyNotices: true)
    }
    defer { host.close() }
    try await host.waitUntil {
      host.controller.presentedViewController != nil
        && host.controller.presentedViewController?.transitionCoordinator == nil
        && host.accessibilityElements.contains { $0.label == "Done" }
    }

    try activate(label: "Done", in: host)

    try await host.waitUntil { host.controller.presentedViewController == nil }
  }

  func testHomeHeaderOpensThirdPartyNotices() throws {
    let profile = try makeProfile()
    let store = Store(initialState: HomeFeature.State(profile: profile, status: nil)) {
      HomeFeature()
    }
    let privacy = Store(initialState: PrivacyFeature.State()) { PrivacyFeature() }
    var isShowing = false
    let header = HomeView(store: store, privacyStore: privacy).header(
      interactionTrigger: .constant(0), showThirdPartyNotices: { isShowing = true })

    header.onAction(.thirdPartyNotices)

    XCTAssertTrue(isShowing)
  }

  func testHomeHeaderCallbacksSendTheirFeatureActions() throws {
    let profile = try makeProfile()
    let checkedStatus = PrivacyRootFixture.status
    let commands: [(HomeMenuAction, HomeFeature.Action)] = [
      (.refresh, .refreshTapped),
      (.serverDetails, .serverDetailsTapped),
      (.replaceShare, .replaceShareTapped),
      (.removeLocalData, .removeLocalDataTapped),
    ]
    for (command, expected) in commands {
      var actions = [HomeFeature.Action]()
      let store = Store(
        initialState: HomeFeature.State(profile: profile, status: checkedStatus)
      ) {
        HomeFeature()
        Reduce { _, action in
          actions.append(action)
          return .none
        }
      } withDependencies: {
        $0.sealbreakClient.waitForForeground = {}
        $0.sealbreakClient.status = { _ in checkedStatus }
      }
      let privacy = Store(initialState: PrivacyFeature.State()) { PrivacyFeature() }
      let view = HomeView(store: store, privacyStore: privacy)
      var trigger = 0
      let header = view.header(
        interactionTrigger: Binding(get: { trigger }, set: { trigger = $0 }),
        showThirdPartyNotices: {})

      header.onAction(command)

      XCTAssertEqual(actions.first, expected)
      XCTAssertEqual(trigger, expected == .refreshTapped ? 1 : 0)
      XCTAssertFalse(header.isBusy)
      switch expected {
      case .refreshTapped:
        XCTAssertEqual(store.operation, .checkingStatus)
      case .serverDetailsTapped:
        XCTAssertEqual(store.serverDetails?.profile, profile)
      case .replaceShareTapped:
        XCTAssertEqual(store.replaceShare?.profile, profile)
      case .removeLocalDataTapped:
        XCTAssertEqual(store.confirmation, .removeLocalData)
        XCTAssertNil(store.operation, "Removal must await explicit confirmation.")
      default:
        XCTFail("Unexpected header menu command.")
      }
    }
  }

  func testHomePrimaryButtonUpdatesInteractionOnlyForAvailableActions() throws {
    let profile = try makeProfile()
    let cases: [(SealStatus?, HomeFeature.State.Operation?, HomeFeature.Action?)] = [
      (PrivacyRootFixture.status, nil, .unsealTapped),
      (nil, nil, .refreshTapped),
      (PrivacyRootFixture.status, .checkingStatus, nil),
    ]
    for (status, operation, expected) in cases {
      var state = HomeFeature.State(profile: profile, status: status)
      state.operation = operation
      var actions = [HomeFeature.Action]()
      let store = Store(initialState: state) {
        Reduce<HomeFeature.State, HomeFeature.Action> { _, action in
          actions.append(action)
          return .none
        }
      }
      let privacy = Store(initialState: PrivacyFeature.State()) { PrivacyFeature() }
      let view = HomeView(store: store, privacyStore: privacy)
      var trigger = 0
      let button = view.primaryButton(
        interactionTrigger: Binding(get: { trigger }, set: { trigger = $0 }))

      button.action()

      XCTAssertEqual(actions, expected.map { [$0] } ?? [])
      XCTAssertEqual(trigger, expected == nil ? 0 : 1)
      XCTAssertEqual(button.state.enabled, expected != nil)
      XCTAssertEqual(store.operation, operation)
    }
  }

  func testWelcomeAndHomeKeepTheirHeadersWhileContentScrolls() async throws {
    let welcome = Store(initialState: WelcomeFeature.State()) { WelcomeFeature() }
    let profile = try makeProfile()
    let home = Store(
      initialState: HomeFeature.State(profile: profile, status: PrivacyRootFixture.status)
    ) { HomeFeature() }
    let privacy = Store(initialState: PrivacyFeature.State()) { PrivacyFeature() }
    let views = [
      AnyView(WelcomeView(store: welcome)),
      AnyView(HomeView(store: home, privacyStore: privacy)),
    ]
    for (index, view) in views.enumerated() {
      let host = try makeHost(size: CGSize(width: 320, height: 568)) { view }
      defer { host.close() }
      try await host.waitUntil { host.accessibility.contains("Sealbreak") }
      let before = try frame("Sealbreak", in: host)
      let menu = index == 1 ? try frame("More options", in: host) : nil
      let scroll = try scrollView(in: host)
      let initial = scroll.contentOffset.y
      try await scrollDown(scroll, in: host)
      XCTAssertGreaterThan(scroll.contentOffset.y, initial + 20)
      assertSameFrame(before, try frame("Sealbreak", in: host))
      if let menu { assertSameFrame(menu, try frame("More options", in: host)) }
      attach(host, name: index == 0 ? "welcome-scrolled" : "home-scrolled")
    }
  }

  func testSetupProgressScrollsAndStepChangesResetOnlyTheBody() async throws {
    let profile = try makeProfile()
    var state = SetupFeature.State()
    state.instance.checkedProfile = profile
    state.instance.address = profile.origin
    let store = Store(initialState: state) { SetupFeature() }
    let host = try makeHost(size: CGSize(width: 320, height: 568)) {
      SetupView(store: store)
    }
    defer { host.close() }
    try await host.waitUntil { host.accessibility.contains("Step 1 of 2") }
    let title = try frame("Setup", in: host)
    let cancel = try frame("Cancel", in: host)
    let progress = try frame("Step 1 of 2: Instance", in: host)
    let scroll = try scrollView(in: host)
    try await scrollDown(scroll, in: host)
    assertSameFrame(title, try frame("Setup", in: host))
    assertSameFrame(cancel, try frame("Cancel", in: host))
    if let moved = elementFrame("Step 1 of 2: Instance", in: host) {
      XCTAssertLessThan(moved.minY, progress.minY - 40)
    }
    attach(host, name: "setup-instance-scrolled")

    await store.send(.instance(.continueTapped)).finish()
    try await host.waitUntil { host.accessibility.contains("Protect your share") }
    let shareScroll = try scrollView(in: host)
    XCTAssertEqual(
      shareScroll.contentOffset.y + shareScroll.adjustedContentInset.top, 0, accuracy: 1)
    assertSameFrame(title, try frame("Setup", in: host))
    assertSameFrame(cancel, try frame("Cancel", in: host))
    XCTAssertGreaterThanOrEqual(try frame("Back", in: host).height, 44)
    try await scrollDown(shareScroll, in: host)
    attach(host, name: "setup-share-scrolled")

    store.send(.backTapped)
    try await host.waitUntil { host.accessibility.contains("Connect your instance") }
    let instanceScroll = try scrollView(in: host)
    XCTAssertEqual(
      instanceScroll.contentOffset.y + instanceScroll.adjustedContentInset.top, 0, accuracy: 1)
    assertSameFrame(cancel, try frame("Cancel", in: host))
  }

  func testLargestTextKeepsSetupActionsAndTitleInsideNarrowScreen() async throws {
    let profile = try makeProfile()
    var state = SetupFeature.State()
    state.step = .share
    state.share = ShareSetupFeature.State(profile: profile)
    let store = Store(initialState: state) { SetupFeature() }
    let host = try makeHost(size: CGSize(width: 320, height: 568), typeSize: .accessibility5) {
      SetupView(store: store)
    }
    defer { host.close() }
    try await host.waitUntil { host.accessibility.contains("Cancel") }
    let title = try frame("Setup", in: host)
    for label in ["Back", "Cancel"] {
      let action = try frame(label, in: host)
      XCTAssertGreaterThanOrEqual(action.width, 44)
      XCTAssertGreaterThanOrEqual(action.height, 44)
      XCTAssertGreaterThanOrEqual(action.minX, 0)
      XCTAssertLessThanOrEqual(action.maxX, host.window.bounds.width)
      XCTAssertGreaterThanOrEqual(action.minY, host.window.safeAreaInsets.top)
      XCTAssertFalse(action.intersects(title))
    }
    XCTAssertGreaterThanOrEqual(title.minX, 0)
    XCTAssertLessThanOrEqual(title.maxX, host.window.bounds.width)
    let scroll = try scrollView(in: host)
    try await scrollDown(scroll, in: host)
    assertSameFrame(title, try frame("Setup", in: host))
    attach(host, name: "setup-largest-text")
  }

  func testWaveIsTheVisibleScrollBoundary() async throws {
    let host = try makeHost(size: CGSize(width: 320, height: 568)) {
      PapercutScreen {
        Text(verbatim: "Fixed header").frame(minHeight: 44)
      } content: {
        Color(red: 1, green: 0, blue: 1).frame(height: 1_000)
      }
    }
    defer { host.close() }
    try await host.waitUntil { host.accessibility.contains("Fixed header") }
    let header = try frame("Fixed header", in: host)
    let scroll = try scrollView(in: host)
    try await scrollDown(scroll, in: host)

    let image = capture(host)
    let first = try firstMagentaRow(in: image, xFraction: 0.2)
    let second = try firstMagentaRow(in: image, xFraction: 0.5)
    XCTAssertGreaterThan(first, header.maxY)
    XCTAssertGreaterThan(second, header.maxY)
    XCTAssertGreaterThan(
      abs(first - second), 3, "Content must disappear at a curved edge, not a rectangular clip.")
    attach(host, name: "wave-occlusion")
  }

  func testKeyboardKeepsSetupHeaderFixedAndFocusedFieldVisible() async throws {
    let store = Store(initialState: SetupFeature.State()) { SetupFeature() }
    let host = try makeHost(size: CGSize(width: 402, height: 874)) {
      SetupView(store: store)
    }
    defer { host.close() }
    try await host.waitUntil {
      host.accessibility.contains("Cancel")
        && UIApplication.shared.applicationState == .active
        && host.window.windowScene?.activationState == .foregroundActive
    }
    let title = try frame("Setup", in: host)
    let cancel = try frame("Cancel", in: host)
    func fields(in view: UIView) -> [UITextField] {
      if let field = view as? UITextField { return [field] }
      return view.subviews.flatMap { fields(in: $0) }
    }
    let address = try XCTUnwrap(fields(in: host.controller.view).last)
    let keyboard = KeyboardFrameProbe()
    XCTAssertTrue(address.becomeFirstResponder())
    defer { address.resignFirstResponder() }
    guard await keyboard.waitForVisibleFrame(in: host.window) else {
      // Distinguish a simulator keyboard limitation from a Setup regression.
      address.resignFirstResponder()
      let nativeController = UIViewController()
      let nativeField = UITextField(frame: CGRect(x: 24, y: 120, width: 250, height: 50))
      nativeController.view.addSubview(nativeField)
      host.window.rootViewController = nativeController
      host.window.makeKeyAndVisible()
      XCTAssertTrue(nativeField.becomeFirstResponder())
      defer { nativeField.resignFirstResponder() }
      if await keyboard.waitForVisibleFrame(in: host.window) {
        XCTFail("Setup did not present the keyboard, but a plain native text field did.")
        return
      }
      throw XCTSkip(
        "This simulator also omits the software keyboard for a plain native text field.")
    }
    let scroll = try scrollView(in: host)
    let keyboardFrame = host.window.convert(try XCTUnwrap(keyboard.frame), from: nil)
    try await host.waitUntil {
      let field = address.convert(address.bounds, to: host.window)
      let viewport = scroll.convert(
        scroll.bounds.inset(by: scroll.adjustedContentInset), to: host.window)
      return address.isFirstResponder
        && field.minY >= viewport.minY && field.maxY <= viewport.maxY
        && viewport.maxY <= keyboardFrame.minY + 1
    }
    assertSameFrame(title, try frame("Setup", in: host))
    assertSameFrame(cancel, try frame("Cancel", in: host))
    let fieldFrame = address.convert(address.bounds, to: host.window)
    let viewport = scroll.convert(
      scroll.bounds.inset(by: scroll.adjustedContentInset), to: host.window)
    XCTAssertGreaterThanOrEqual(fieldFrame.minY, viewport.minY)
    XCTAssertLessThanOrEqual(fieldFrame.maxY, viewport.maxY)
    XCTAssertLessThanOrEqual(viewport.maxY, keyboardFrame.minY + 1)
    attach(host, name: "setup-keyboard")
  }

  private func makeHost<Content: View>(
    size: CGSize, typeSize: DynamicTypeSize = .large, @ViewBuilder content: () -> Content
  ) throws -> PrivacyViewHost {
    let host = try PrivacyViewHost {
      NavigationStack { content() }
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.dynamicTypeSize, typeSize)
    }
    host.window.frame.size = size
    host.controller.view.frame = host.window.bounds
    host.window.layoutIfNeeded()
    return host
  }

  private func makeProfile() throws -> ServerProfile {
    try ServerProfile(
      id: UUID(), name: "Synthetic server", address: "https://bao.example.com", product: .openBao)
  }

  private func activate(identifier: String, in host: PrivacyViewHost) throws {
    try activate(in: host) { $0.identifier == identifier }
  }

  private func activate(label: String, in host: PrivacyViewHost) throws {
    try activate(in: host) { $0.label == label }
  }

  private func activate(
    in host: PrivacyViewHost, where isMatch: (AccessibilityElement) -> Bool
  ) throws {
    let matches: [[(AccessibilityElement, NSObject)]] = AccessibilityHierarchyParser()
      .parseAccessibilityHierarchy(
        in: host.visibleWindow,
        makeElement: { element, _, source in
          isMatch(element) ? [(element, source)] : []
        },
        makeContainer: { _, children, _ in children.flatMap { $0 } }
      )
    let (element, source) = try XCTUnwrap(matches.flatMap { $0 }.first)
    _ = try XCTUnwrap(
      element.traits.contains(.notEnabled) ? nil : true, "The requested control must be enabled.")
    XCTAssertTrue(source.accessibilityActivate(), "The visible button must handle activation.")
  }

  private func scrollView(in host: PrivacyViewHost) throws -> UIScrollView {
    func find(in view: UIView) -> UIScrollView? {
      if let scroll = view as? UIScrollView { return scroll }
      return view.subviews.lazy.compactMap { find(in: $0) }.first
    }
    return try XCTUnwrap(find(in: host.controller.view))
  }

  private func scrollDown(_ scroll: UIScrollView, in host: PrivacyViewHost) async throws {
    let initial = scroll.contentOffset.y
    let bottom =
      scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom
    XCTAssertGreaterThan(bottom - initial, 20, "The fixture must contain scrollable content.")
    scroll.setContentOffset(CGPoint(x: 0, y: min(initial + 180, bottom)), animated: false)
    try await host.waitUntil { scroll.contentOffset.y > initial + 20 }
  }

  private func elementFrame(_ label: String, in host: PrivacyViewHost) -> CGRect? {
    host.accessibilityElements.first { $0.label == label }?.shape.bezierPath.bounds
  }

  private func frame(_ label: String, in host: PrivacyViewHost) throws -> CGRect {
    try XCTUnwrap(elementFrame(label, in: host), "Missing accessible element: \(label)")
  }

  private func assertSameFrame(
    _ before: CGRect, _ after: CGRect, file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertEqual(before.minX, after.minX, accuracy: 1, file: file, line: line)
    XCTAssertEqual(before.minY, after.minY, accuracy: 1, file: file, line: line)
    XCTAssertEqual(before.width, after.width, accuracy: 1, file: file, line: line)
    XCTAssertEqual(before.height, after.height, accuracy: 1, file: file, line: line)
  }

  private func capture(_ host: PrivacyViewHost) -> UIImage {
    let format = UIGraphicsImageRendererFormat(for: host.window.traitCollection)
    format.preferredRange = .standard
    return UIGraphicsImageRenderer(bounds: host.window.bounds, format: format).image { _ in
      host.window.drawHierarchy(in: host.window.bounds, afterScreenUpdates: true)
    }
  }

  private func attach(_ host: PrivacyViewHost, name: String) {
    let attachment = XCTAttachment(image: capture(host))
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func firstMagentaRow(in image: UIImage, xFraction: CGFloat) throws -> CGFloat {
    let cgImage = try XCTUnwrap(image.cgImage)
    let width = cgImage.width
    let height = cgImage.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    try pixels.withUnsafeMutableBytes { buffer in
      let context = try XCTUnwrap(
        CGContext(
          data: buffer.baseAddress, width: width, height: height,
          bitsPerComponent: 8, bytesPerRow: width * 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
      context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    let x = Int(CGFloat(width) * xFraction)
    let row = try XCTUnwrap(
      (0..<height).first { y in
        let offset = (y * width + x) * 4
        return pixels[offset] > 200 && pixels[offset + 1] < 50 && pixels[offset + 2] > 200
      })
    return CGFloat(row) / image.scale
  }
}

@MainActor
private final class KeyboardFrameProbe: NSObject {
  var frame: CGRect?

  override init() {
    super.init()
    for notification in [
      UIResponder.keyboardWillChangeFrameNotification,
      UIResponder.keyboardDidChangeFrameNotification,
    ] {
      NotificationCenter.default.addObserver(
        self, selector: #selector(didChange(_:)), name: notification, object: nil)
    }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  func waitForVisibleFrame(in window: UIWindow) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while ContinuousClock.now < deadline {
      if let frame, frame.intersection(window.frame).height > 100 { return true }
      try? await Task.sleep(for: .milliseconds(10))
    }
    return false
  }

  @objc private func didChange(_ notification: Notification) {
    frame =
      (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
  }
}
