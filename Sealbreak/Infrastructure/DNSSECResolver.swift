import Foundation
import Network

package struct DNSSECResolver: Sendable {
    private let resolveHost: @Sendable (String) async -> DNSSECStatus

    package init(
        resolveHost: @escaping @Sendable (String) async -> DNSSECStatus
    ) {
        self.resolveHost = resolveHost
    }

    package func status(for host: String) async -> DNSSECStatus {
        let normalized = host
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .lowercased()

        guard !normalized.isEmpty else {
            return .unavailable
        }
        guard !isIPAddress(normalized),
              !normalized.hasSuffix(".local") else {
            return .notApplicable
        }

        return await resolveHost(normalized)
    }

    private func isIPAddress(_ host: String) -> Bool {
        IPv4Address(host) != nil || IPv6Address(host) != nil
    }
}
