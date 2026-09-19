func replaceShareIfBound(
    expectedProfile: ServerProfile,
    replacement: ShareRecord,
    readExisting: () throws -> ShareRecord,
    beforeReplace: () throws -> Void,
    replace: (ShareRecord) throws -> Void
) throws {
    var existing = try readExisting()
    defer { existing.share.removeAll(keepingCapacity: false) }

    guard existing.profile == expectedProfile,
          replacement.profile == expectedProfile else {
        throw AppFailure("Target binding mismatch. Restore the protected profile first.")
    }

    try beforeReplace()
    try replace(replacement)
}
