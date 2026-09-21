enum IntegrationFixture {
    static let serverURL = ""
    static let serverProduct = ""
    static let firstShare = ""
    static let secondShare = ""

    static var isConfigured: Bool {
        !serverURL.isEmpty
            && !serverProduct.isEmpty
            && !firstShare.isEmpty
            && !secondShare.isEmpty
    }

    static var expectedProduct: ServerProduct {
        switch serverProduct {
        case "openbao":
            return .openBao
        case "vault":
            return .vault
        default:
            return .generic
        }
    }
}
