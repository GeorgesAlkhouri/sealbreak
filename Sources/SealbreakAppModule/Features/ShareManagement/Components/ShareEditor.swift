import Foundation
import SealbreakCore
import SwiftUI
import UIKit

struct SharePasteControl: View {
    let disabled: Bool
    let onPaste: (Result<String, AppFailure>) -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .fill(PapercutPalette.buttonBack)
                .offset(x: 2, y: 5)

            SystemSharePasteControl(
                disabled: disabled,
                onPaste: onPaste
            )
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 62)
        .shadow(color: .black.opacity(0.30), radius: 8, y: 8)
        .opacity(disabled ? 0.5 : 1)
    }
}

private struct SystemSharePasteControl: UIViewRepresentable {
    let disabled: Bool
    let onPaste: (Result<String, AppFailure>) -> Void

    func makeUIView(context: Context) -> SharePasteTargetView {
        let view = SharePasteTargetView()
        view.onPaste = onPaste
        view.setExternallyDisabled(disabled)
        return view
    }

    func updateUIView(_ uiView: SharePasteTargetView, context: Context) {
        uiView.onPaste = onPaste
        uiView.setExternallyDisabled(disabled)
    }
}

@MainActor
private final class SharePasteTargetView: UIView {
    var onPaste: ((Result<String, AppFailure>) -> Void)?

    private let pasteControl: UIPasteControl

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

    func setExternallyDisabled(_ disabled: Bool) {
        isUserInteractionEnabled = !disabled
    }

    override func paste(itemProviders: [NSItemProvider]) {
        guard let provider = itemProviders.first(where: {
            $0.canLoadObject(ofClass: NSString.self)
        }) else {
            return
        }

        provider.loadObject(ofClass: NSString.self) { [weak self] object, _ in
            guard let string = object as? NSString else {
                return
            }

            Task { @MainActor [weak self] in
                self?.handlePaste(string as String)
            }
        }
    }

    private func handlePaste(_ candidate: String) {
        do {
            var share = try validatedSharePaste(candidate)
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
