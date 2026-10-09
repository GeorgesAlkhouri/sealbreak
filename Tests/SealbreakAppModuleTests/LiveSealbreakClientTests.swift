import ComposableArchitecture
import Foundation
import LocalAuthentication
import Security
import Testing
import UIKit
import XCTest
@testable import SealbreakAppModule
@testable import SealbreakCore
@testable import SealbreakInfrastructure

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct LiveSealbreakClientTests {
    @Test(arguments: ProtectedAction.allCases)
    func protectedActionsWaitForFreshFaceIDBeforeStorage(action: ProtectedAction) async throws {
        let fixture = try ControllerFixture(ready: action.requiresReadyProfile)
        defer { fixture.cleanUp() }
        let context = fixture.factory.next
        let task = fixture.start { try await fixture.perform(action) }
        try await context.waitForEvaluation()

        #expect(fixture.access.calls.isEmpty)
        #expect(context.availabilityPolicies == [.deviceOwnerAuthenticationWithBiometrics])
        #expect(context.evaluationPolicies == [.deviceOwnerAuthenticationWithBiometrics])
        #expect(context.reasons == ["Synthetic authorization"])
        #expect(context.localizedFallbackTitle == "")
        #expect(context.touchIDAuthenticationAllowableReuseDuration == 0)
        #expect(context.invalidationCount == 0)
        if !action.requiresReadyProfile {
            #expect(try fixture.profiles.loadAll().isEmpty)
        }

        context.complete(success: true)
        try await task.value

        #expect(fixture.access.calls.map(\.operation) == action.expectedCalls)
        #expect(fixture.access.calls.allSatisfy { $0.context === context && $0.interactionNotAllowed })
        #expect(context.invalidationCount == 1)
        if action == .create {
            #expect(fixture.lastOutcome == .completed)
            #expect(try fixture.profiles.loadAll().map(\.state) == [.ready])
        } else if action == .remove {
            #expect(fixture.lastOutcome == .completed)
            #expect(try fixture.profiles.loadAll().isEmpty)
        }
        fixture.controller.cancelSensitiveOperation()
        #expect(context.invalidationCount == 1, "Completed context must no longer be active.")
    }

    @Test
    func eachProtectedReadUsesANewContextAndFragmentIsMinimized() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let first = fixture.factory.next
        let read = fixture.start {
            try await fixture.controller.readShare(profileID: fixture.profile.id, reason: ControllerFixture.reason)
        }
        try await first.waitForEvaluation()
        first.complete(success: true)
        #expect(try await read.value == fixture.record)

        let second = fixture.factory.next
        let reveal = fixture.start {
            try await fixture.controller.readShareFragment(profileID: fixture.profile.id, reason: ControllerFixture.reason)
        }
        try await second.waitForEvaluation()
        #expect(first !== second)
        #expect(first.invalidationCount == 1)
        #expect(fixture.access.calls.count == 1)
        second.complete(success: true)
        #expect(try await reveal.value == ShareComparisonFragment(validatedShare: fixture.record.share))
        #expect(second.invalidationCount == 1)
        #expect(fixture.access.calls.map(\.context) == [first, second])
    }

    @Test(arguments: AvailabilityFailure.allCases)
    func unavailableOrNonFaceIDCannotAccessStorage(failure: AvailabilityFailure) async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let context = fixture.factory.next
        context.available = failure == .touchID
        context.availabilityError = failure.error
        context.biometry = failure == .touchID ? .touchID : .faceID

        let task = fixture.start { try await fixture.perform(.read) }
        let error = await #expect(throws: AppFailure.self) { try await task.value }
        #expect(error?.feedback.level == .error)
        #expect(String(localized: try #require(error).feedback.text).contains(failure.expectedMessage))
        #expect(context.evaluationPolicies.isEmpty)
        #expect(context.invalidationCount == 1)
        #expect(fixture.access.calls.isEmpty)
    }

    @Test(arguments: EvaluationFailure.allCases)
    func unsuccessfulEvaluationNeverAccessesStorage(failure: EvaluationFailure) async throws {
        let fixture = try ControllerFixture(ready: true)
        defer { fixture.cleanUp() }
        let context = fixture.factory.next
        let task = fixture.start { try await fixture.perform(.replace) }
        try await context.waitForEvaluation()
        context.complete(success: false, error: failure.error)

        let error = await #expect(throws: AppFailure.self) { try await task.value }
        #expect(error?.feedback.level == failure.expectedLevel)
        #expect(context.invalidationCount == 1)
        #expect(fixture.access.calls.isEmpty)
        #expect(try fixture.profiles.loadAll().map(\.state) == [.ready])
    }

    @Test(arguments: PlatformGate.allCases, [false, true])
    func platformGatesPreventStorageBeforeAndAfterAuthorization(gate: PlatformGate, afterAuthorization: Bool) async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let context = fixture.factory.next
        if !afterAuthorization { fixture.platform.block(gate) }
        let task = fixture.start { try await fixture.perform(.create) }
        if afterAuthorization {
            try await context.waitForEvaluation()
            fixture.platform.block(gate)
            context.complete(success: true)
            await fixture.clock.advance(by: .seconds(5))
        }

        await #expect(throws: AppFailure.self) { try await task.value }
        #expect(fixture.access.calls.isEmpty)
        #expect(try fixture.profiles.loadAll().isEmpty)
        #expect(fixture.factory.created.count == (afterAuthorization ? 1 : 0))
        #expect(context.invalidationCount == (afterAuthorization ? 1 : 0))
    }

    @Test
    func replacementRechecksPrivacyAfterReadingBeforeUpdating() async throws {
        let fixture = try ControllerFixture(ready: true)
        defer { fixture.cleanUp() }
        fixture.access.beforeCall = { operation in
            if operation == "read" { fixture.platform.captured = true }
        }
        let context = fixture.factory.next
        let task = fixture.start { try await fixture.perform(.replace) }
        try await context.waitForEvaluation()
        context.complete(success: true)
        await #expect(throws: AppFailure.self) { try await task.value }
        #expect(fixture.access.calls.map(\.operation) == ["read"])
        #expect(context.invalidationCount == 1)
    }

    @Test
    func cancellationBeforeStartingDoesNotCreateAContext() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let task = fixture.start { try await fixture.perform(.read) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(fixture.factory.created.isEmpty)
        #expect(fixture.access.calls.isEmpty)
    }

    @Test
    func taskCancellationDuringEvaluationBlocksStorageAndInvalidatesContext() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let context = fixture.factory.next
        let task = fixture.start { try await fixture.perform(.fragment) }
        try await context.waitForEvaluation()
        task.cancel()
        #expect(fixture.access.calls.isEmpty)
        context.complete(success: true)
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(context.invalidationCount == 1)
        #expect(fixture.access.calls.isEmpty)
    }

    @Test
    func explicitlyInvalidatedLateSuccessCannotAccessStorage() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let context = fixture.factory.next
        let task = fixture.start { try await fixture.perform(.read) }
        try await context.waitForEvaluation()
        fixture.controller.cancelSensitiveOperation()
        #expect(context.invalidationCount == 1)
        context.complete(success: true)
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(fixture.access.calls.isEmpty)
    }

    @Test
    func replacedLateSuccessCannotAccessStorageOrClearTheNewerContext() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let older = fixture.factory.next
        let oldTask = fixture.start { try await fixture.perform(.read) }
        try await older.waitForEvaluation()
        let newer = fixture.factory.next
        let newTask = fixture.start { try await fixture.perform(.fragment) }
        try await newer.waitForEvaluation()

        older.complete(success: true)
        await #expect(throws: CancellationError.self) { try await oldTask.value }
        #expect(older.invalidationCount == 1)
        #expect(newer.invalidationCount == 0)
        #expect(fixture.access.calls.isEmpty)
        newer.complete(success: true)
        try await newTask.value
        #expect(fixture.access.calls.map(\.context) == [newer])
        #expect(newer.invalidationCount == 1)
    }

    @Test
    func transientInactivityWaitsAndThenUsesTheAuthorizedContext() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let context = fixture.factory.next
        let task = fixture.start { try await fixture.perform(.read) }
        try await context.waitForEvaluation()
        fixture.platform.state = .inactive
        context.complete(success: true)
        await fixture.clock.advance(by: .milliseconds(400))
        #expect(fixture.access.calls.isEmpty)
        #expect(context.invalidationCount == 0)
        fixture.platform.state = .active
        await fixture.clock.advance(by: .milliseconds(100))
        try await task.value
        #expect(fixture.access.calls.map(\.context) == [context])
    }

    @Test
    func foregroundWaitHasABoundedTimeout() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let task = fixture.start { try await fixture.controller.waitForForeground() }
        fixture.platform.state = .inactive
        await fixture.clock.advance(by: .milliseconds(4900))
        #expect(fixture.platform.sleepCount == 50)
        #expect(fixture.access.calls.isEmpty)
        await fixture.clock.advance(by: .milliseconds(100))
        await #expect(throws: AppFailure.self) { try await task.value }
        #expect(fixture.platform.sleepCount == 50)
    }

    @Test
    func cancellationWhileWaitingForForegroundStopsWithoutStorage() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let context = fixture.factory.next
        let task = fixture.start { try await fixture.perform(.read) }
        try await context.waitForEvaluation()
        fixture.platform.state = .inactive
        context.complete(success: true)
        await fixture.clock.advance(by: .milliseconds(100))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(context.invalidationCount == 1)
        #expect(fixture.access.calls.isEmpty)
        try await fixture.clock.checkSuspension()
    }

    @Test(arguments: [ProtectedAction.read, .replace, .create, .remove])
    func storageFailureInvalidatesAndTransactionsRemainInRecovery(action: ProtectedAction) async throws {
        let fixture = try ControllerFixture(ready: action.requiresReadyProfile)
        defer { fixture.cleanUp() }
        fixture.access.status = errSecAuthFailed
        let context = fixture.factory.next
        let task = fixture.start { try await fixture.perform(action) }
        try await context.waitForEvaluation()
        context.complete(success: true)
        if action == .create || action == .remove {
            try await task.value
            #expect(fixture.lastOutcome?.requiresRecovery == true)
            #expect(try fixture.profiles.loadAll().map(\.state) == [action == .create ? .creating : .removing])
        } else {
            await #expect(throws: AppFailure.self) { try await task.value }
        }
        #expect(context.invalidationCount == 1)
        #expect(fixture.access.calls.count == 1)
    }
}

enum ProtectedAction: CaseIterable {
    case read, fragment, create, replace, remove

    var requiresReadyProfile: Bool { self == .replace || self == .remove }
    var expectedCalls: [String] {
        switch self {
        case .read, .fragment: ["read"]
        case .create: ["insert"]
        case .replace: ["read", "update"]
        case .remove: ["delete"]
        }
    }
}

enum AvailabilityFailure: CaseIterable {
    case denied, unenrolled, lockout, noPasscode, unavailable, touchID

    var error: NSError? {
        let code: LAError.Code
        switch self {
        case .denied: code = .authenticationFailed
        case .unenrolled: code = .biometryNotEnrolled
        case .lockout: code = .biometryLockout
        case .noPasscode: code = .passcodeNotSet
        case .unavailable: code = .biometryNotAvailable
        case .touchID: return nil
        }
        return NSError(domain: LAError.errorDomain, code: code.rawValue)
    }

    var expectedMessage: String {
        switch self {
        case .denied: "did not authorize"
        case .unenrolled: "isn’t set up"
        case .lockout: "is locked"
        case .noPasscode: "passcode is required"
        case .unavailable, .touchID: "isn’t available"
        }
    }
}

enum EvaluationFailure: CaseIterable {
    case falseResult, denied, userCancel, systemCancel, appCancel, unknownError

    var error: Error? {
        switch self {
        case .falseResult: nil
        case .denied: NSError(domain: LAError.errorDomain, code: LAError.authenticationFailed.rawValue)
        case .userCancel: NSError(domain: LAError.errorDomain, code: LAError.userCancel.rawValue)
        case .systemCancel: NSError(domain: LAError.errorDomain, code: LAError.systemCancel.rawValue)
        case .appCancel: NSError(domain: LAError.errorDomain, code: LAError.appCancel.rawValue)
        case .unknownError: NSError(domain: "synthetic-error", code: 999)
        }
    }

    var expectedLevel: FeedbackLevel {
        switch self {
        case .userCancel, .systemCancel, .appCancel: .warning
        default: .error
        }
    }
}

enum PlatformGate: CaseIterable {
    case inactive, background, locked, captured
}

@MainActor
final class ControllerPlatform {
    var state: UIApplication.State = .active
    var protectedDataAvailable = true
    var captured = false
    var sleepCount = 0

    func block(_ gate: PlatformGate) {
        switch gate {
        case .inactive: state = .inactive
        case .background: state = .background
        case .locked: protectedDataAvailable = false
        case .captured: captured = true
        }
    }
}

@MainActor
final class ControllerFixture {
    static let reason = LocalizedStringResource("Synthetic authorization")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("SealbreakControllerTests-\(UUID())")
    let platform = ControllerPlatform()
    let factory = ContextFactory()
    let access = ControllerKeychainSpy()
    let clock = TestClock<Duration>()
    let profile: ServerProfile
    let record: ShareRecord
    let profiles: ProfileStore
    let controller: LiveSealbreakClientController
    var lastOutcome: LocalPersistenceOutcome?
    private var cancelTasks: [() -> Void] = []

    init(ready: Bool = false, client: SealServerClient = SealServerClient()) throws {
        profile = try ServerProfile(id: UUID(), name: "Synthetic", address: "https://bao.example.com", product: .openBao)
        record = try ShareRecord(profile: profile, input: "0123456789abcdef0123456789abcdef")
        profiles = ProfileStore(baseDirectory: root)
        if ready {
            try profiles.begin(profile)
            try profiles.commit(id: profile.id)
        }
        access.data = try JSONEncoder().encode(record)
        let platform = platform
        let factory = factory
        let clock = clock
        controller = LiveSealbreakClientController(
            keychain: KeychainStore(access: access),
            profiles: profiles,
            client: client,
            makeContext: { factory.make() },
            applicationState: { platform.state },
            protectedDataAvailable: { platform.protectedDataAvailable },
            sceneCaptured: { platform.captured },
            sleep: {
                platform.sleepCount += 1
                try await clock.sleep(for: $0)
            }
        )
    }

    func perform(_ action: ProtectedAction) async throws {
        switch action {
        case .read: _ = try await controller.readShare(profileID: profile.id, reason: Self.reason)
        case .fragment: _ = try await controller.readShareFragment(profileID: profile.id, reason: Self.reason)
        case .create: lastOutcome = try await controller.protectNewProfile(profile: profile, record: record, reason: Self.reason)
        case .replace: try await controller.replaceShare(expectedProfile: profile, replacement: record, reason: Self.reason)
        case .remove: lastOutcome = try await controller.removeLocalProfile(profileID: profile.id, reason: Self.reason)
        }
    }

    func start<Value: Sendable>(_ operation: @escaping @MainActor () async throws -> Value) -> ControllerTestTask<Value> {
        let task = ControllerTestTask(operation: operation)
        cancelTasks.append { task.cancel() }
        return task
    }

    func cleanUp() {
        cancelTasks.forEach { $0() }
        controller.cancelSensitiveOperation()
        for context in factory.created {
            context.complete(success: false, error: NSError(domain: LAError.errorDomain, code: LAError.appCancel.rawValue))
        }
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
struct ControllerTestTask<Value: Sendable> {
    private let task: Task<Value, Error>
    private let completion: XCTestExpectation

    init(operation: @escaping @MainActor () async throws -> Value) {
        let completion = XCTestExpectation(description: "Controller operation completes")
        self.completion = completion
        task = Task {
            defer { completion.fulfill() }
            return try await operation()
        }
    }

    var value: Value {
        get async throws {
            let result = await XCTWaiter.fulfillment(of: [completion], timeout: 3)
            try #require(result == .completed, "Controller operation did not complete after the controlled reply or clock advance.")
            return try await task.value
        }
    }

    func cancel() { task.cancel() }
}

@MainActor
final class ContextFactory {
    var next = ControlledLAContext()
    var created: [ControlledLAContext] = []

    func make() -> LAContext {
        let context = next
        created.append(context)
        next = ControlledLAContext()
        return context
    }
}

// Control only the system authentication reply, including replies after invalidation.
// The controller's authorization, transaction and cancellation flow runs unchanged.
final class ControlledLAContext: LAContext, @unchecked Sendable {
    private struct State {
        var available = true
        var biometry: LABiometryType = .faceID
        var availabilityError: NSError?
        var availabilityPolicies: [LAPolicy] = []
        var evaluationPolicies: [LAPolicy] = []
        var reasons: [String] = []
        var invalidationCount = 0
        var reply: ((Bool, Error?) -> Void)?
    }

    private let lock = NSLock()
    private let evaluationStarted = XCTestExpectation(description: "Controller requests Face ID evaluation")
    private var state = State()
    var available: Bool {
        get { withState { $0.available } }
        set { withState { $0.available = newValue } }
    }
    var biometry: LABiometryType {
        get { withState { $0.biometry } }
        set { withState { $0.biometry = newValue } }
    }
    var availabilityError: NSError? {
        get { withState { $0.availabilityError } }
        set { withState { $0.availabilityError = newValue } }
    }
    var availabilityPolicies: [LAPolicy] { withState { $0.availabilityPolicies } }
    var evaluationPolicies: [LAPolicy] { withState { $0.evaluationPolicies } }
    var reasons: [String] { withState { $0.reasons } }
    var invalidationCount: Int { withState { $0.invalidationCount } }

    override var biometryType: LABiometryType { biometry }

    override func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool {
        withState {
            $0.availabilityPolicies.append(policy)
            error?.pointee = $0.availabilityError
            return $0.available
        }
    }

    override func evaluatePolicy(_ policy: LAPolicy, localizedReason: String, reply: @escaping @Sendable (Bool, Error?) -> Void) {
        withState {
            $0.evaluationPolicies.append(policy)
            $0.reasons.append(localizedReason)
            $0.reply = reply
        }
        evaluationStarted.fulfill()
    }

    override func invalidate() { withState { $0.invalidationCount += 1 } }

    func waitForEvaluation() async throws {
        let result = await XCTWaiter.fulfillment(of: [evaluationStarted], timeout: 3)
        try #require(result == .completed, "Controller did not request Face ID evaluation.")
    }

    func complete(success: Bool, error: Error? = nil) {
        let completion = withState {
            let completion = $0.reply
            $0.reply = nil
            return completion
        }
        completion?(success, error)
    }

    private func withState<Value>(_ operation: (inout State) -> Value) -> Value {
        lock.withLock { operation(&state) }
    }
}

final class ControllerKeychainSpy: KeychainAccessing {
    struct Call {
        let operation: String
        let request: [String: Any]
        let context: LAContext?
        let interactionNotAllowed: Bool
    }

    var status: OSStatus = errSecSuccess
    var data: Data?
    var beforeCall: ((String) -> Void)?
    private(set) var calls: [Call] = []

    func makeBiometricAccessControl() -> SecAccessControl? {
        SystemKeychainAccess().makeBiometricAccessControl()
    }

    func copyMatching(_ request: [String: Any]) -> (OSStatus, Data?) {
        record("read", request)
        return (status, data)
    }

    func add(_ request: [String: Any]) -> OSStatus {
        record("insert", request)
        return status
    }

    func update(_ request: [String: Any], attributes: [String: Any]) -> OSStatus {
        record("update", request)
        return status
    }

    func delete(_ request: [String: Any]) -> OSStatus {
        record("delete", request)
        return status
    }

    private func record(_ operation: String, _ request: [String: Any]) {
        let context = request[kSecUseAuthenticationContext as String] as? LAContext
        calls.append(Call(operation: operation, request: request, context: context, interactionNotAllowed: context?.interactionNotAllowed == true))
        beforeCall?(operation)
    }
}

private extension LocalPersistenceOutcome {
    var requiresRecovery: Bool {
        if case .recoveryRequired = self { return true }
        return false
    }
}
