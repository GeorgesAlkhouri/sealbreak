import AccessibilitySnapshotParser
import ComposableArchitecture
import Foundation
import SwiftUI
import UIKit
import XCTest

@testable import SealbreakAppModule
@testable import SealbreakCore

@MainActor
final class ButtonLayoutTests: XCTestCase {
  func testAnimationCaptureDoesNotRenderFutureFrames() async throws {
    let host = try PrivacyViewHost(animationsEnabled: true) {
      Color.blue.ignoresSafeArea()
    }
    let marker = UIView(frame: CGRect(x: 40, y: 100, width: 20, height: 20))
    marker.backgroundColor = .white
    host.window.addSubview(marker)
    defer {
      marker.layer.removeAllAnimations()
      host.close()
    }
    try await host.waitUntil { marker.layer.presentation() != nil }

    // A slow UIKit animation leaves time to sample even on a busy simulator.
    // The model immediately reaches x=250; the presentation moves from x=50.
    let duration: TimeInterval = 10
    let animationStart = CACurrentMediaTime()
    UIView.animate(withDuration: duration, delay: 0, options: .curveLinear) {
      marker.center.x = 250
    }
    var sampledAnimation = false
    var capturedMovement = false
    for _ in 0..<20 {
      let image = try captureWindow(in: host)
      let elapsed = CACurrentMediaTime() - animationStart
      let latestPossibleX = CGFloat(50 + 200 * min(elapsed / duration, 1))
      let visibleX = try XCTUnwrap(marker.layer.presentation()).position.x
      let bounds = try renderedIconBounds(try XCTUnwrap(image.cgImage))
      XCTAssertFalse(bounds.isNull, "The visible marker must be captured.")
      // The presentation layer can lag the render server on a busy simulator.
      // Bound the captured frame by the linear animation's elapsed media time.
      // Starting the clock before UIKit commits makes this a conservative bound;
      // keep the same two-pixel allowance for rasterization.
      XCTAssertLessThanOrEqual(
        bounds.midX, latestPossibleX + 2, "The snapshot must not render a future animation frame.")
      sampledAnimation = sampledAnimation || (visibleX > 50 && visibleX < 250)
      capturedMovement = capturedMovement || bounds.midX > 52
      try await Task.sleep(for: .milliseconds(20))
    }
    XCTAssertTrue(sampledAnimation, "The capture must observe an animation in progress.")
    XCTAssertTrue(capturedMovement, "The snapshots must include the marker's visible movement.")
  }

  func testDetailsControlsKeepTheirBoundsDuringAuthorization() async throws {
    let fixture = try PrivacyRootFixture()
    defer { fixture.close() }
    try await fixture.present(.details)
    let fragment = try buttonFrame(
      in: fixture.host, identifier: nil, label: "Show stored share fragment")
    let done = try buttonFrame(in: fixture.host, identifier: nil, label: "Done")
    let authorization = fixture.start(.home(.serverDetails(.presented(.shareFragmentTapped))))
    try await fixture.waitForPendingFragment()
    assertSameBounds(
      fragment,
      try buttonFrame(in: fixture.host, identifier: nil, label: "Show stored share fragment"))
    assertSameBounds(done, try buttonFrame(in: fixture.host, identifier: nil, label: "Done"))
    fixture.probe.fail()
    try await fixture.host.finish(authorization)
    try await fixture.host.waitUntil {
      fixture.store.home?.serverDetails?.isRevealingShare == false
    }
    assertSameBounds(
      fragment,
      try buttonFrame(in: fixture.host, identifier: nil, label: "Show stored share fragment"))
  }

  func testReplacementControlsKeepTheirBoundsDuringAuthorization() async throws {
    let fixture = try PrivacyRootFixture()
    defer { fixture.close() }
    try await fixture.present(.replacement)
    let cancel = try buttonFrame(in: fixture.host, identifier: nil, label: "Cancel")
    let paste = try buttonFrame(in: fixture.host, identifier: nil, label: "Paste")
    let replacement = fixture.start(
      .home(.replaceShare(.presented(.saveTapped(share: PrivacyRootFixture.share)))))
    try await fixture.host.waitUntil {
      fixture.probe.pendingReplacementCount == 1 && !fixture.host.pasteControlIsEnabled
    }
    assertSameBounds(cancel, try buttonFrame(in: fixture.host, identifier: nil, label: "Cancel"))
    assertSameBounds(paste, try buttonFrame(in: fixture.host, identifier: nil, label: "Paste"))
    fixture.probe.completeReplacement()
    try await fixture.host.finish(replacement)
  }

  func testLocalResetKeepsPrimaryActionPositionWhileWorkingAndAfterFailure() async throws {
    let reply = DelayedOfflineStatus()
    var client = SealbreakClient.testValue
    client.resetLocalData = { _ = try await reply.check() }
    let store = Store(
      initialState: WelcomeFeature.State(
        feedback: AppFailure("Local Sealbreak configuration could not be read.").feedback,
        requiresLocalReset: true
      )
    ) {
      WelcomeFeature()
    } withDependencies: {
      $0.sealbreakClient = client
    }
    let host = try PrivacyViewHost(animationsEnabled: true) {
      NavigationStack { WelcomeView(store: store) }
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.dynamicTypeSize, .large)
    }
    defer { host.close() }
    let identifier = "welcome-primary-action"
    try await host.waitUntil { host.accessibility.contains("Reset local Sealbreak data") }
    let before = try buttonFrame(in: host, identifier: identifier)
    try assertRenderedIcon(in: host, button: before, attachment: "reset-before")

    let operation = store.send(.confirmResetLocalDataTapped, animation: .easeInOut(duration: 0.3))
    try await host.waitUntil { host.accessibility.contains("Resetting") }
    let pending = try buttonFrame(in: host, identifier: identifier)
    assertSameBounds(before, pending)
    try assertRenderedIcon(in: host, button: pending, attachment: "reset-pending")

    await reply.fail()
    try await host.finish(operation)
    try await host.waitUntil {
      !store.isResetting && host.accessibility.contains("Connection failed")
    }
    let after = try buttonFrame(in: host, identifier: identifier)
    assertSameBounds(before, after)
    try assertRenderedIcon(in: host, button: after, attachment: "reset-failed")
  }

  func testConnectionCheckKeepsPrimaryActionPositionForFailureAndContinue() async throws {
    for succeeds in [false, true] {
      let reply = DelayedOfflineStatus()
      var client = SealbreakClient.testValue
      client.dnssecStatus = { _ in .notApplicable }
      client.status = { _ in try await reply.check() }
      client.detectProduct = { _ in .openBao }
      var state = SetupFeature.State()
      state.instance.address = "https://bao.example.com"
      state.instance.feedback = AppFailure("Connection failed or timed out.").feedback
      let store = Store(initialState: state) {
        SetupFeature()
      } withDependencies: {
        $0.sealbreakClient = client
        $0.uuid = .incrementing
      }
      let host = try PrivacyViewHost(animationsEnabled: true) {
        NavigationStack { SetupView(store: store) }
          .environment(\.locale, Locale(identifier: "en_US"))
          .environment(\.dynamicTypeSize, .large)
      }
      defer { host.close() }
      let identifier = "instance-primary-action"
      try await host.waitUntil { host.accessibility.contains("Check connection") }
      let before = try buttonFrame(in: host, identifier: identifier)
      let cancel = try buttonFrame(in: host, identifier: nil, label: "Cancel")
      try assertRenderedIcon(
        in: host, button: before, backOffset: 5, attachment: "connection-before")

      let operation = store.send(
        .instance(.checkConnectionTapped), animation: .easeInOut(duration: 0.3))
      try await host.waitUntil { host.accessibility.contains("Checking connection") }
      let pending = try buttonFrame(in: host, identifier: identifier)
      assertSameBounds(before, pending)
      assertSameBounds(cancel, try buttonFrame(in: host, identifier: nil, label: "Cancel"))
      try assertRenderedIcon(
        in: host, button: pending, backOffset: 5, attachment: "connection-pending")

      if succeeds { await reply.succeed(PrivacyRootFixture.status) } else { await reply.fail() }
      try await host.finish(operation)
      try await host.waitUntil {
        !store.instance.isCheckingConnection
          && host.accessibility.contains(succeeds ? "Continue" : "Connection failed")
      }
      let after = try buttonFrame(in: host, identifier: identifier)
      assertSameBounds(before, after)
      assertSameBounds(cancel, try buttonFrame(in: host, identifier: nil, label: "Cancel"))
      try assertRenderedIcon(in: host, button: after, backOffset: 5, attachment: "connection-after")
    }
  }

  func testOfflineStatusRefreshKeepsPrimaryActionPositionForEveryStatus() async throws {
    let sealed = SealStatus(
      type: "shamir",
      initialized: true,
      sealed: true,
      quorum: .init(threshold: 3, totalShares: 5, progress: 0),
      migration: false,
      recoverySeal: false
    )
    let unsealed = SealStatus(
      type: "shamir",
      initialized: true,
      sealed: false,
      quorum: .init(threshold: 3, totalShares: 5, progress: 0),
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
    let host = try PrivacyViewHost(animationsEnabled: true) {
      NavigationStack {
        HomeView(store: homeStore, privacyStore: privacyStore)
      }
      .environment(\.locale, Locale(identifier: "en_US"))
      .environment(\.dynamicTypeSize, .large)
    }
    defer { host.close() }

    let initialLabel = initialStatus?.sealed == true ? "Unseal with Face ID" : "Check status"
    try await host.waitUntil {
      host.accessibility.contains(initialLabel)
        && host.accessibility.contains("Connection failed or timed out")
    }
    let before = try buttonFrame(in: host, label: initialLabel)
    try assertRenderedIcon(in: host, button: before, attachment: "offline-before")

    // The reducer removes the error message while the network request is pending.
    let refresh = homeStore.send(.refreshTapped, animation: .easeInOut(duration: 0.3))
    try await assertTransition(in: host, expected: before)
    try await host.waitUntil {
      homeStore.operation == .checkingStatus
        && host.accessibility.contains("Checking seal status")
        && !host.accessibility.contains("Connection failed or timed out")
    }
    let pending = try buttonFrame(in: host, label: "Checking seal status…")
    try assertRenderedIcon(in: host, button: pending, attachment: "offline-checking")

    await offline.fail()
    try await assertTransition(in: host, expected: before)
    await refresh.finish()
    try await host.waitUntil {
      homeStore.operation == nil
        && host.accessibility.contains("Check status")
        && host.accessibility.contains("Connection failed or timed out")
    }
    let after = try buttonFrame(in: host, label: "Check status")
    try assertRenderedIcon(in: host, button: after, attachment: "offline-after")

    // A VoiceOver activation point is not guaranteed to be the element's center.
    // Verify the accessibility frame, which represents the rendered control's bounds.
    assertSameBounds(before, pending)
    assertSameBounds(before, after)
  }

  private func assertTransition(in host: PrivacyViewHost, expected: CGRect) async throws {
    // Keep UIKit/SwiftUI animations enabled and sample during the 300 ms transaction,
    // rather than only comparing layouts after animations have settled.
    for _ in 0..<20 {
      host.window.layoutIfNeeded()
      let frame = try buttonFrame(in: host)
      assertSameBounds(expected, frame)
      // Observe the visible frame without flushing and retiming the animation.
      try assertRenderedIcon(in: host, button: expected, afterScreenUpdates: false)
      try await Task.sleep(for: .milliseconds(20))
    }
  }

  private func assertSameBounds(
    _ expected: CGRect, _ actual: CGRect, file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertEqual(expected.minX, actual.minX, accuracy: 1, file: file, line: line)
    XCTAssertEqual(
      expected.minY, actual.minY, accuracy: 1, "Action moved: \(expected) -> \(actual)", file: file,
      line: line)
    XCTAssertEqual(expected.width, actual.width, accuracy: 1, file: file, line: line)
    XCTAssertEqual(expected.height, actual.height, accuracy: 1, file: file, line: line)
  }

  private func assertRenderedIcon(
    in host: PrivacyViewHost, button: CGRect, backOffset: CGFloat = 6, attachment: String? = nil,
    afterScreenUpdates: Bool = true
  ) throws {
    let image = try captureWindow(in: host, afterScreenUpdates: afterScreenUpdates)
    if let attachment {
      let screenshot = XCTAttachment(image: image)
      screenshot.name = attachment
      screenshot.lifetime = .keepAlways
      add(screenshot)
    }

    // Inspect rendered pixels in the leading column, not the VoiceOver activation
    // point. SF Symbols must remain centered in the same 30 pt column.
    // Accessibility includes the decorative back layer's bottom offset.
    // Exclude that layer when finding the center of the actual action surface,
    // and include a 4 pt margin on either side to catch a clipped/moving icon.
    let column = CGRect(
      x: button.minX + 12, y: button.minY, width: 38, height: button.height - backOffset)
    let source = try XCTUnwrap(image.cgImage)
    let crop = try XCTUnwrap(source.cropping(to: column.integral))
    let width = crop.width
    let height = crop.height
    let bounds = try renderedIconBounds(crop)
    XCTAssertFalse(bounds.isNull, "The rendered icon must be present in its fixed column.")
    guard !bounds.isNull else { return }
    XCTAssertGreaterThan(bounds.width, 10)
    XCTAssertGreaterThan(bounds.height, 10)
    XCTAssertLessThanOrEqual(bounds.width, 30)
    XCTAssertLessThanOrEqual(bounds.height, 30, "The icon must remain inside the button.")
    // Accept up to 3 pt of horizontal glyph movement during symbol changes.
    // CI captured a 2.5 pt shift; the 1x renderer maps pixels to points.
    // The button's layout bounds are checked separately with 1 pt accuracy.
    XCTAssertEqual(bounds.midX, CGFloat(width) / 2, accuracy: 3)
    XCTAssertEqual(
      bounds.midY, CGFloat(height) / 2, accuracy: 2, "The rendered icon must not jump vertically.")
  }

  private func captureWindow(in host: PrivacyViewHost, afterScreenUpdates: Bool = false) throws
    -> UIImage
  {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.preferredRange = .standard
    var rendered = false
    let image = UIGraphicsImageRenderer(size: host.window.bounds.size, format: format).image { _ in
      rendered = host.window.drawHierarchy(
        in: host.window.bounds, afterScreenUpdates: afterScreenUpdates)
    }
    _ = try XCTUnwrap(rendered ? true : nil, "The hosted window must render successfully.")
    return image
  }

  private func renderedIconBounds(_ crop: CGImage) throws -> CGRect {
    let width = crop.width
    let height = crop.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
    return try pixels.withUnsafeMutableBytes { buffer in
      let context = try XCTUnwrap(
        CGContext(
          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
          bytesPerRow: width * 4, space: colorSpace,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        ))
      context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
      let values = buffer.bindMemory(to: UInt8.self)
      let backgroundOffset = ((height - 10) * width + width / 2) * 4
      let backgroundRed = Int(values[backgroundOffset])
      let backgroundGreen = Int(values[backgroundOffset + 1])
      var bounds = CGRect.null
      for y in 0..<height {
        for x in 0..<width {
          let offset = (y * width + x) * 4
          let red = Int(values[offset])
          let green = Int(values[offset + 1])
          // UIKit also dims disabled labels. Compare the glyph's contrast
          // with the rendered blue surface instead of requiring its original color.
          if red - backgroundRed >= 40, green - backgroundGreen >= 25 {
            bounds = bounds.union(CGRect(x: x, y: y, width: 1, height: 1))
          }
        }
      }
      return bounds
    }
  }

  private func buttonFrame(
    in host: PrivacyViewHost, identifier: String? = "home-primary-action", label: String? = nil
  ) throws -> CGRect {
    let button = try XCTUnwrap(
      host.accessibilityElements.first(where: { element in
        (identifier == nil || element.identifier == identifier)
          && (label.map { element.label?.contains($0) == true } ?? true)
      }),
      "Expected action \(identifier ?? label ?? "any state")."
    )
    // SwiftUI exposes rounded buttons as paths. The parser's UIKit bridge
    // supports both paths and rectangular frames without losing curve bounds.
    let resolved = button.shape.bezierPath.bounds
    XCTAssertFalse(resolved.isEmpty)
    return resolved
  }
}

private actor DelayedOfflineStatus {
  private var continuation: CheckedContinuation<SealStatus, Error>?
  private var result: Result<SealStatus, Error>?

  func check() async throws -> SealStatus {
    if let result { return try result.get() }
    return try await withCheckedThrowingContinuation { continuation = $0 }
  }

  func fail() {
    complete(
      .failure(
        AppFailure(
          "Connection failed or timed out. Check the network, VPN, DNS, and the configured server endpoint."
        )))
  }

  func succeed(_ status: SealStatus) {
    complete(.success(status))
  }

  private func complete(_ result: Result<SealStatus, Error>) {
    self.result = result
    continuation?.resume(with: result)
    continuation = nil
  }
}
