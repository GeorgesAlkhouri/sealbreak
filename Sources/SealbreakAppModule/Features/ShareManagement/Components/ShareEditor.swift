import Foundation
import SealbreakCore
import SwiftUI
import UIKit

struct SharePasteControl: View {
    @Environment(\.isSceneCaptured) private var isSceneCaptured
    @Environment(\.scenePhase) private var scenePhase
    @State private var privacyEpoch = UUID()

    let disabled: Bool
    let onPaste: (Result<String, AppFailure>) -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .fill(PapercutPalette.buttonBack)
                .offset(x: 2, y: 5)

            SystemSharePasteControl(
                disabled: disabled,
                privacyEpoch: privacyEpoch,
                onPaste: onPaste
            )
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 62)
        .shadow(color: .black.opacity(0.30), radius: 8, y: 8)
        .opacity(disabled ? 0.5 : 1)
        .onAppear {
            if isSceneCaptured {
                privacyEpoch = UUID()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                privacyEpoch = UUID()
            }
        }
        .onChange(of: isSceneCaptured) { _, isCaptured in
            if isCaptured {
                privacyEpoch = UUID()
            }
        }
    }
}

private struct SystemSharePasteControl: UIViewRepresentable {
    let disabled: Bool
    let privacyEpoch: UUID
    let onPaste: (Result<String, AppFailure>) -> Void

    func makeUIView(context: Context) -> SharePasteTargetView {
        let view = SharePasteTargetView()
        view.onPaste = onPaste
        view.update(externallyDisabled: disabled, privacyEpoch: privacyEpoch)
        return view
    }

    func updateUIView(_ uiView: SharePasteTargetView, context: Context) {
        uiView.onPaste = onPaste
        uiView.update(externallyDisabled: disabled, privacyEpoch: privacyEpoch)
    }

    static func dismantleUIView(_ uiView: SharePasteTargetView, coordinator _: ()) {
        uiView.invalidatePaste()
    }
}

@MainActor
final class SharePasteLoadCoordinator {
    typealias Loader = (@escaping (NSString?, Error?) -> Void) -> Progress

    private struct InvalidProviderResult: Error {}

    private var activePasteID: UUID?
    private var activeLoad: Progress?
    private var onResult: ((Result<String, AppFailure>) -> Void)?

    func start(
        using loader: Loader,
        onResult: @escaping (Result<String, AppFailure>) -> Void
    ) {
        invalidate()

        let pasteID = UUID()
        activePasteID = pasteID
        self.onResult = onResult
        activeLoad = loader { [weak self] string, error in
            Task { @MainActor [weak self] in
                self?.finish(pasteID: pasteID, string: string, error: error)
            }
        }
    }

    func invalidate() {
        activePasteID = nil
        onResult = nil
        activeLoad?.cancel()
        activeLoad = nil
    }

    private func finish(
        pasteID: UUID,
        string: NSString?,
        error: Error?
    ) {
        guard activePasteID == pasteID else {
            return
        }

        activePasteID = nil
        activeLoad = nil
        let resultHandler = onResult
        onResult = nil

        if let string {
            resultHandler?(.success(string as String))
            return
        }

        let failure = error.map(normalizedAppFailure)
            ?? normalizedAppFailure(InvalidProviderResult())
        resultHandler?(.failure(failure))
    }
}

@MainActor
private final class SharePasteTargetView: UIView {
    var onPaste: ((Result<String, AppFailure>) -> Void)?

    private let pasteControl: UIPasteControl
    private let loadCoordinator = SharePasteLoadCoordinator()
    private var privacyEpoch: UUID?

    override init(frame: CGRect) {
        let configuration = UIPasteControl.Configuration()
        configuration.displayMode = .iconAndLabel
        configuration.baseBackgroundColor = UIColor(PapercutPalette.button)
        configuration.baseForegroundColor = UIColor(PapercutPalette.cream)
        configuration.cornerStyle = .fixed
        configuration.cornerRadius = 21

        pasteControl = UIPasteControl(configuration: configuration)

        super.init(frame: frame)

        pasteConfiguration = UIPasteConfiguration(forAccepting: NSString.self)
        pasteControl.target = self
        pasteControl.translatesAutoresizingMaskIntoConstraints = false

        addSubview(pasteControl)
        NSLayoutConstraint.activate([
            pasteControl.leadingAnchor.constraint(equalTo: leadingAnchor),
            pasteControl.trailingAnchor.constraint(equalTo: trailingAnchor),
            pasteControl.topAnchor.constraint(equalTo: topAnchor),
            pasteControl.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(externallyDisabled disabled: Bool, privacyEpoch: UUID) {
        if self.privacyEpoch != privacyEpoch {
            self.privacyEpoch = privacyEpoch
            invalidatePaste()
        }
        isUserInteractionEnabled = !disabled
    }

    func invalidatePaste() {
        loadCoordinator.invalidate()
    }

    override func paste(itemProviders: [NSItemProvider]) {
        loadCoordinator.invalidate()

        guard let provider = itemProviders.first(where: {
            $0.canLoadObject(ofClass: NSString.self)
        }) else {
            return
        }

        loadCoordinator.start(
            using: { completion in
                provider.loadObject(ofClass: NSString.self) { object, error in
                    completion(object as? NSString, error)
                }
            },
            onResult: { [weak self] result in
                switch result {
                case .success(let candidate):
                    self?.handlePaste(candidate)
                case .failure(let failure):
                    self?.onPaste?(.failure(failure))
                }
            }
        )
    }

    private func handlePaste(_ candidate: String) {
        do {
            var share = try ShareRecord.validateShare(candidate)
            defer {
                share.removeAll(keepingCapacity: false)
            }

            UIPasteboard.general.items = []
            onPaste?(.success(share))
        } catch {
            onPaste?(.failure(normalizedAppFailure(error)))
        }
    }
}
