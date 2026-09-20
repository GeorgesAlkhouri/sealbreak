func replaceShareIfBound(
    expectedProfile: ServerProfile,
    replacement: ShareRecord,
    readExisting: () throws -> ShareRecord,
    beforeReplace: () throws -> Void,
    replace: (ShareRecord) throws -> Void
) throws {
    var existing = try readExisting()
    defer { existing.share.removeAll(keepingCapacity: false) }

    guard existing.boundOrigin == expectedProfile.origin,
          replacement.boundOrigin == expectedProfile.origin else {
        throw AppFailure("Target binding mismatch. Reconfigure the local share for this server before retrying.")
    }

    try beforeReplace()
    try replace(replacement)
}
