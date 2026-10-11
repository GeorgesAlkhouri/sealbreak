import Foundation
import Security
import Testing
@testable import SealbreakInfrastructure

struct KeychainAccessControlTests {
    @Test
    func systemAccessControlRequiresCurrentBiometryAndThisDevicePasscodeClass() throws {
        let actual = try #require(SystemKeychainAccess().makeBiometricAccessControl())
        let expected = try #require(SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            .biometryCurrentSet,
            nil
        ))
        #expect(CFEqual(actual, expected))
    }

    @Test(arguments: WeakerAccessControl.allCases)
    func systemAccessControlDiffersFromWeakerPolicies(policy: WeakerAccessControl) throws {
        let actual = try #require(SystemKeychainAccess().makeBiometricAccessControl())
        let weaker = try #require(SecAccessControlCreateWithFlags(nil, policy.protection, policy.flags, nil))
        #expect(!CFEqual(actual, weaker))
    }
}

enum WeakerAccessControl: CaseIterable {
    case anyBiometry, userPresence, migratableClass

    var flags: SecAccessControlCreateFlags {
        switch self {
        case .anyBiometry: .biometryAny
        case .userPresence: .userPresence
        case .migratableClass: .biometryCurrentSet
        }
    }

    var protection: CFString {
        self == .migratableClass ? kSecAttrAccessibleWhenUnlocked : kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
    }
}
