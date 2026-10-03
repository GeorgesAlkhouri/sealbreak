import Foundation
import SealbreakCore

enum ProfileCatalogState: String, Codable, Equatable {
    case active
    case resetting
}

private struct ProfileCatalog: Codable {
    static let currentVersion = 3

    let version: Int
    let state: ProfileCatalogState
    var profiles: [StoredProfile]
}

package struct ProfileStore {
    private let baseDirectory: URL

    package init() {
        self.init(baseDirectory: nil)
    }

    init(baseDirectory: URL? = nil) {
        self.baseDirectory = baseDirectory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
    }

    private var directory: URL {
        baseDirectory.appendingPathComponent("Sealbreak", isDirectory: true)
    }

    private var file: URL {
        directory.appendingPathComponent("profiles.json")
    }

    package func loadAll() throws -> [StoredProfile] {
        guard FileManager.default.fileExists(atPath: file.path) else {
            return []
        }

        let handle = try FileHandle(forReadingFrom: file)
        defer {
            try? handle.close()
        }
        let data = try handle.read(upToCount: StorageLimits.maxProfileCatalogBytes + 1) ?? Data()
        guard data.count <= StorageLimits.maxProfileCatalogBytes else {
            throw AppFailure(
                LocalizedStringResource("Invalid profile catalog. Reset local Sealbreak data before setting up again using your independent share copies.", bundle: .module)
            )
        }

        let catalog: ProfileCatalog
        do {
            catalog = try JSONDecoder().decode(ProfileCatalog.self, from: data)
        } catch {
            throw AppFailure(
                LocalizedStringResource("Invalid profile catalog. Reset local Sealbreak data before setting up again using your independent share copies.", bundle: .module)
            )
        }
        guard catalog.version == ProfileCatalog.currentVersion else {
            throw AppFailure(
                LocalizedStringResource("Unsupported profile catalog version. Reset local Sealbreak data before setting up again using your independent share copies.", bundle: .module)
            )
        }
        guard catalog.state == .active else {
            throw AppFailure(
                LocalizedStringResource("Local Sealbreak reset did not finish. Reset local data to continue.", bundle: .module)
            )
        }

        var ids = Set<UUID>()
        var origins = Set<String>()
        var validated: [StoredProfile] = []
        validated.reserveCapacity(catalog.profiles.count)

        for entry in catalog.profiles {
            let profile = try entry.profile.validated()
            try StorageLimits.validateEncodedSize(JSONEncoder().encode(profile))
            guard ids.insert(profile.id).inserted else {
                throw AppFailure(LocalizedStringResource("The profile catalog contains a duplicate profile identifier.", bundle: .module))
            }
            guard origins.insert(profile.origin).inserted else {
                throw AppFailure(LocalizedStringResource("The profile catalog contains the same server origin more than once.", bundle: .module))
            }
            validated.append(
                StoredProfile(
                    profile: profile,
                    state: entry.state
                )
            )
        }

        return validated
    }

    package func begin(_ profile: ServerProfile) throws {
        let profile = try profile.validated()
        try StorageLimits.validateEncodedSize(JSONEncoder().encode(profile))

        var entries = try loadAll()
        guard entries.isEmpty else {
            throw AppFailure(
                LocalizedStringResource("Local profile data already exists. Reset local Sealbreak data before continuing.", bundle: .module)
            )
        }
        entries.append(
            StoredProfile(
                profile: profile,
                state: .creating
            )
        )
        try write(entries)
    }

    package func commit(id: UUID) throws {
        var entries = try loadAll()
        guard entries.count == 1,
              entries[0].profile.id == id,
              entries[0].state == .creating else {
            throw AppFailure(
                LocalizedStringResource("Local setup state cannot be committed. Reset local Sealbreak data before continuing.", bundle: .module)
            )
        }

        entries[0].state = .ready
        try write(entries)
    }

    package func beginRemoval(id: UUID) throws {
        var entries = try loadAll()
        guard entries.count == 1,
              entries[0].profile.id == id,
              entries[0].state == .ready else {
            throw AppFailure(
                LocalizedStringResource("Local removal state cannot be started. Reset local Sealbreak data before continuing.", bundle: .module)
            )
        }

        entries[0].state = .removing
        try write(entries)
    }

    package func delete(id: UUID) throws {
        var entries = try loadAll()
        entries.removeAll { $0.profile.id == id }

        if entries.isEmpty {
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
            return
        }

        try write(entries)
    }

    package func prepareForReset() throws {
        try writeCatalog(
            ProfileCatalog(
                version: ProfileCatalog.currentVersion,
                state: .resetting,
                profiles: []
            )
        )
    }

    package func reset() throws {
        guard FileManager.default.fileExists(atPath: file.path) else {
            return
        }
        try FileManager.default.removeItem(at: file)
    }

    private func write(_ profiles: [StoredProfile]) throws {
        try writeCatalog(
            ProfileCatalog(
                version: ProfileCatalog.currentVersion,
                state: .active,
                profiles: profiles
            )
        )
    }

    private func writeCatalog(_ catalog: ProfileCatalog) throws {
        let data = try JSONEncoder().encode(catalog)
        try StorageLimits.validateProfileCatalogSize(data)

        var folder = directory
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        try data.write(
            to: file,
            options: [.atomic, .completeFileProtection]
        )
    }
}
