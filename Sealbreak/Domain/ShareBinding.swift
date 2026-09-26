func applySharePaste(_ candidate: String?, to draft: inout String) throws {
    draft.removeAll(keepingCapacity: false)
    draft = try ShareRecord.validateShare(candidate ?? "")
}

func replaceShareIfBound(
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
        throw AppFailure("Target binding mismatch. Reconfigure the local share for this server before retrying.")
    }

    try beforeReplace()
    try replace(replacement)
}
