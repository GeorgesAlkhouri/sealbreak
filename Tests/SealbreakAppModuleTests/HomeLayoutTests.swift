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
        XCTAssertEqual(before.minX, pending.minX, accuracy: 1)
        XCTAssertEqual(before.minY, pending.minY, accuracy: 1, "Hiding feedback must not move the button: before=\(before), pending=\(pending)")
        XCTAssertEqual(before.width, pending.width, accuracy: 1)
        XCTAssertEqual(before.height, pending.height, accuracy: 1)
        XCTAssertEqual(before.minX, after.minX, accuracy: 1)
        XCTAssertEqual(before.minY, after.minY, accuracy: 1, "Restoring feedback must not move the button: before=\(before), after=\(after)")
        XCTAssertEqual(before.width, after.width, accuracy: 1)
        XCTAssertEqual(before.height, after.height, accuracy: 1)
    }

    private func assertTransition(in host: PrivacyViewHost, expected: CGRect) async throws {
        // Keep UIKit/SwiftUI animations enabled and sample during the 300 ms transaction,
        // rather than only comparing layouts after animations have settled.
        for _ in 0..<20 {
            host.window.layoutIfNeeded()
            let frame = try buttonFrame(in: host)
            XCTAssertEqual(frame.minX, expected.minX, accuracy: 1)
            XCTAssertEqual(frame.minY, expected.minY, accuracy: 1)
            XCTAssertEqual(frame.width, expected.width, accuracy: 1)
            XCTAssertEqual(frame.height, expected.height, accuracy: 1)
            try assertRenderedIcon(in: host, button: expected)
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func assertRenderedIcon(in host: PrivacyViewHost, button: CGRect, attachment: String? = nil) throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        var rendered = false
        let image = UIGraphicsImageRenderer(size: host.window.bounds.size, format: format).image { _ in
            rendered = host.window.drawHierarchy(in: host.window.bounds, afterScreenUpdates: true)
        }
        _ = try XCTUnwrap(rendered ? true : nil, "The hosted window must render successfully.")
        if let attachment {
            let screenshot = XCTAttachment(image: image)
            screenshot.name = attachment
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }

        // Inspect rendered pixels in the leading column, not the VoiceOver activation
        // point. All three SF Symbols must remain centered in the same 30 pt column.
        // Accessibility includes the decorative back layer's 6 pt bottom offset.
        // Exclude that layer when finding the center of the actual action surface,
        // and include a 4 pt margin on either side to catch a clipped/moving icon.
        let column = CGRect(x: button.minX + 12, y: button.minY, width: 38, height: button.height - 6)
        let source = try XCTUnwrap(image.cgImage)
        let crop = try XCTUnwrap(source.cropping(to: column.integral))
        let width = crop.width
        let height = crop.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let bounds = try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
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
        XCTAssertFalse(bounds.isNull, "The rendered icon must be present in its fixed column.")
        guard !bounds.isNull else { return }
        XCTAssertGreaterThan(bounds.width, 10)
        XCTAssertGreaterThan(bounds.height, 10)
        XCTAssertLessThanOrEqual(bounds.width, 30)
        XCTAssertLessThanOrEqual(bounds.height, 30, "The icon must remain inside the button.")
        XCTAssertEqual(bounds.midX, CGFloat(width) / 2, accuracy: 2)
        XCTAssertEqual(bounds.midY, CGFloat(height) / 2, accuracy: 2, "The rendered icon must not jump vertically.")
        if let attachment { print("HOME_ICON: \(attachment): rendered bounds=\(bounds)") }
    }

    private func buttonFrame(in host: PrivacyViewHost, label: String? = nil) throws -> CGRect {
        let elements = AccessibilityHierarchyParser()
            .parseAccessibilityHierarchy(in: host.window)
            .flattenToElements()
        let button = try XCTUnwrap(
            elements.first(where: { $0.identifier == "home-primary-action" && (label == nil || $0.label == label) }),
            "Expected primary home action labeled \(label ?? "any state")."
        )
        // SwiftUI exposes rounded buttons as paths. The parser's UIKit bridge
        // supports both paths and rectangular frames without losing curve bounds.
        let resolved = button.shape.bezierPath.bounds
        XCTAssertFalse(resolved.isEmpty)
        if let label { print("HOME_LAYOUT: \(label): frame=\(resolved)") }
        return resolved
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
