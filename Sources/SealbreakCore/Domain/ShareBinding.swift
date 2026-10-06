import Foundation
package func validatedSharePaste(_ candidate: String?) throws -> String {
    try ShareRecord.validateShare(candidate ?? "")
}

package func replaceShareIfBound(
    expectedProfile: ServerProfile,
    replacement: ShareRecord,
    readExisting: () throws -> ShareRecord,
    beforeReplace: () throws -> Void,
    replace: (ShareRecord) throws -> Void
) throws {
    var existing = try readExisting()
    defer { existing.share.removeAll(keepingCapacity: false) }

    guard existing.profileID == expectedProfile.id,
          replacement.profileID == expectedProfile.id,
          existing.boundOrigin == expectedProfile.origin,
          replacement.boundOrigin == expectedProfile.origin else {
        throw AppFailure(LocalizedStringResource("Target binding mismatch. Reconfigure the local share for this server before retrying.", bundle: .module))
    }

    try beforeReplace()
    try replace(replacement)
}
