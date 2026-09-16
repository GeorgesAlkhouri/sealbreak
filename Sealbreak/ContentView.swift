import SwiftUI
import UIKit

@MainActor
struct ContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var name = "OpenBao"
    @State private var address = ""
    @State private var share = ""
    @State private var recoveryConfirmed = false
    @State private var confirmUnseal = false
    @State private var confirmDelete = false
    @State private var showDetails = false
    @State private var showReplacement = false
    @State private var captured = UIScreen.main.isCaptured

    private var concealed: Bool {
        scenePhase != .active || captured
    }

    var body: some View {
        ZStack {
            NavigationStack {
                Group {
                    if let profile = model.profile {
                        home(profile: profile)
                    } else {
                        setup
                    }
                }
                .disabled(captured)
                .confirmationDialog(
                    "Send a share to this target?",
                    isPresented: $confirmUnseal,
                    titleVisibility: .visible
                ) {
                    Button("Authorize with Face ID") {
                        clearDraft()
                        model.unseal()
                    }
                } message: {
                    Text("\(model.profile?.origin ?? "")\nA trusted certificate does not prove the server is uncompromised. Only proceed when you trust this node and any TLS proxy.")
                }
                .confirmationDialog(
                    "Remove the local share?",
                    isPresented: $confirmDelete,
                    titleVisibility: .visible
                ) {
                    Button("I have recovery — remove local data", role: .destructive) {
                        clearDraft()
                        showReplacement = false
                        model.removeLocalData()
                    }
                } message: {
                    Text("Requires fresh Face ID. This cannot be undone and does not revoke copies elsewhere. After Face ID changes, removal deletes any remaining old record; it cannot recover that record.")
                }
                .sheet(isPresented: $showDetails) {
                    details
                }
                .sheet(isPresented: $showReplacement) {
                    replacement
                }
            }

            if concealed {
                Color(.systemBackground)
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield")
                        .font(.largeTitle)
                    Text(captured ? "Stop screen capture to continue" : "Sealbreak locked")
                }
                .accessibilityElement(children: .combine)
            }
        }
        .onAppear {
            if scenePhase == .active, model.profile != nil {
                model.refresh()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                clearDraft()
            }
            if phase == .background {
                model.cancelForPrivacy()
            }
            if phase == .active, model.profile != nil, !model.busy {
                model.refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
            captured = UIScreen.main.isCaptured
            if captured {
                clearDraft()
                model.cancelForPrivacy()
            }
        }
        .onChange(of: model.profile) { _, _ in
            clearDraft()
            showReplacement = false
        }
        .onChange(of: model.busy) { wasBusy, busy in
            if wasBusy && !busy {
                clearDraft()
                showReplacement = false
            }
        }
    }

    private func home(profile: ServerProfile) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                PapercutPalette.sky
                    .ignoresSafeArea()

                HeaderWaveShape()
                    .fill(PapercutPalette.mountainNear)
                    .frame(height: 165)
                    .shadow(color: .black.opacity(0.25), radius: 7, y: 6)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea(edges: .top)

                PapercutLandscape()
                    .frame(height: 170)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 0) {
                    homeHeader
                        .padding(.horizontal, 24)

                    Spacer(minLength: 28)

                    statusCard(profile: profile)
                        .frame(maxWidth: 335)
                        .padding(.horizontal, 29)

                    Spacer(minLength: 26)

                    primaryAction
                        .frame(maxWidth: 335)
                        .padding(.horizontal, 29)

                    if model.status == nil, !model.busy {
                        Text(model.notice)
                            .font(.caption)
                            .foregroundStyle(PapercutPalette.cream.opacity(0.86))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 38)
                            .padding(.top, 10)
                    }

                    Spacer(minLength: max(118, proxy.safeAreaInsets.bottom + 90))
                }
                .padding(.top, 10)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(PapercutPalette.sky)
    }

    private var homeHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "shield")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(PapercutPalette.cream)
                .shadow(color: .black.opacity(0.35), radius: 4, y: 4)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: -1) {
                Text("Sealbreak")
                    .font(.system(size: 31, weight: .bold, design: .default))
                    .foregroundStyle(PapercutPalette.cream)

                Text("S E C U R E   A C C E S S")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(PapercutPalette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            Menu {
                Button("Check status", systemImage: "arrow.clockwise", action: model.refresh)
                    .disabled(model.busy)

                Button("Server details", systemImage: "info.circle") {
                    showDetails = true
                }

                Button("Replace local share", systemImage: "key.horizontal") {
                    clearDraft()
                    showReplacement = true
                }
                .disabled(model.busy)

                Button("Restore profile from Keychain", systemImage: "arrow.uturn.backward") {
                    model.restoreProfile()
                }
                .disabled(model.busy)

                Divider()

                Button("Remove local data", systemImage: "trash", role: .destructive) {
                    confirmDelete = true
                }
                .disabled(model.busy)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(PapercutPalette.cream)
                    .frame(width: 44, height: 44)
                    .background(PapercutPalette.menu)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.30), radius: 9, y: 8)
            }
            .accessibilityLabel("More options")
        }
        .frame(maxWidth: 345)
    }

    private func statusCard(profile: ServerProfile) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(PapercutPalette.cardBack2)
                .offset(x: 8, y: 11)
                .shadow(color: .black.opacity(0.30), radius: 9, y: 8)

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(PapercutPalette.cardBack1)
                .offset(x: 4, y: 6)
                .shadow(color: .black.opacity(0.24), radius: 7, y: 5)

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(PapercutPalette.card)
                .shadow(color: .black.opacity(0.36), radius: 11, y: 10)

            VStack(spacing: 0) {
                Text(profile.name)
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(PapercutPalette.cream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, alignment: .center)

                Text(displayOrigin(profile.origin))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(PapercutPalette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)

                Spacer(minLength: 18)

                statusIndicator

                Spacer(minLength: 10)

                Text(statusTitle)
                    .font(.system(size: statusTitle == "UNSEALING" ? 34 : 40, weight: .bold))
                    .foregroundStyle(statusAccent)
                    .shadow(color: .black.opacity(0.28), radius: 4, y: 4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, alignment: .center)

                Text(statusPrimaryDetail)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(PapercutPalette.cream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 7)

                Text(statusSecondaryDetail)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(PapercutPalette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        }
        .frame(height: 460)
        .accessibilityElement(children: .combine)
    }

    private var statusIndicator: some View {
        ZStack {
            Circle()
                .stroke(PapercutPalette.ring, lineWidth: 18)

            Circle()
                .trim(from: 0, to: statusProgress)
                .stroke(
                    statusAccent,
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Image(systemName: statusIcon)
                .font(.system(size: 66, weight: .bold))
                .foregroundStyle(statusAccent)
                .shadow(color: .black.opacity(0.38), radius: 6, y: 8)
        }
        .frame(width: 170, height: 170)
        .shadow(color: .black.opacity(0.30), radius: 6, y: 7)
        .accessibilityHidden(true)
    }

    private var primaryAction: some View {
        Button {
            if model.status?.sealed == false || model.status == nil {
                model.refresh()
            } else {
                confirmUnseal = true
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: model.status?.sealed == true ? "faceid" : "arrow.clockwise")
                    .font(.system(size: 26, weight: .medium))

                Text(primaryActionTitle)
                    .font(.system(size: 20, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(PapercutPalette.cream)
            .frame(maxWidth: .infinity)
            .frame(height: 74)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(PapercutPalette.buttonBack)
                        .offset(x: 2, y: 6)

                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(PapercutPalette.button)
                }
            }
            .shadow(color: .black.opacity(0.38), radius: 10, y: 10)
        }
        .buttonStyle(.plain)
        .disabled(model.busy || (model.status?.sealed == true && !model.canUnseal))
        .opacity(model.busy || (model.status?.sealed == true && !model.canUnseal) ? 0.58 : 1)
    }

    private var primaryActionTitle: String {
        if model.busy {
            return model.activity.isEmpty ? "Working…" : model.activity
        }
        if model.status?.sealed == false || model.status == nil {
            return "Check status"
        }
        return "Unseal with Face ID"
    }

    private var statusTitle: String {
        if model.busy {
            let lower = model.activity.lowercased()
            if lower.contains("submitting") || lower.contains("verifying") || lower.contains("face id") || lower.contains("target") {
                return "UNSEALING"
            }
            return "CHECKING"
        }

        guard let status = model.status else {
            return "UNKNOWN"
        }
        return status.sealed ? "SEALED" : "UNSEALED"
    }

    private var statusAccent: Color {
        if model.busy {
            return PapercutPalette.button
        }
        guard let status = model.status else {
            return PapercutPalette.secondaryText
        }
        return status.sealed ? PapercutPalette.sealed : PapercutPalette.unsealed
    }

    private var statusIcon: String {
        if model.busy {
            return "lock"
        }
        guard let status = model.status else {
            return "questionmark.circle"
        }
        return status.sealed ? "lock.fill" : "lock.open.fill"
    }

    private var statusProgress: Double {
        if model.busy {
            return 0.66
        }
        guard let status = model.status else {
            return 0.20
        }
        guard status.sealed else {
            return 1
        }
        guard status.t > 0 else {
            return 0
        }
        return min(1, max(0, Double(status.progress) / Double(status.t)))
    }

    private var statusPrimaryDetail: String {
        if model.busy {
            return model.activity.isEmpty ? "Working…" : model.activity
        }
        guard let status = model.status else {
            return "Status unknown"
        }
        if status.sealed {
            return "\(status.progress) of \(status.t) shares submitted"
        }
        return "OpenBao is available"
    }

    private var statusSecondaryDetail: String {
        if model.busy {
            return "Please keep the app open"
        }
        guard let status = model.status else {
            return "Check status before sending"
        }
        if status.sealed {
            return status.supportsUnseal ? "Shamir seal" : "Manual unseal unavailable"
        }
        return "Status checked"
    }

    private func displayOrigin(_ origin: String) -> String {
        origin
            .replacingOccurrences(of: "https://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private var setup: some View {
        Form {
            Section {
                TextField("Server name", text: $name)
                TextField("OpenBao HTTPS origin", text: $address)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                secretEditor(replacing: false)
            } header: {
                Text("Add one OpenBao node")
            } footer: {
                Text("Configure the direct HTTPS origin of one node, not a load balancer distributing requests among nodes. The server must be initialized separately.")
            }

            Section("Recovery and local data") {
                Button("Restore profile from Keychain", action: model.restoreProfile)
                    .disabled(model.busy)
                Button("Remove local data", role: .destructive) {
                    confirmDelete = true
                }
                .disabled(model.busy)
                Text("Keep an independent recovery copy. Face ID changes, device loss, or passcode removal can make the saved share inaccessible. Deleting the app is not a reliable Keychain wipe.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Result") {
                if model.busy {
                    ProgressView(model.activity)
                }
                Text(model.notice)
                    .font(.callout)
            }
        }
        .navigationTitle("Sealbreak")
    }

    private var details: some View {
        NavigationStack {
            Form {
                if let profile = model.profile {
                    Section("Target") {
                        LabeledContent("Name", value: profile.name)
                        LabeledContent("Origin", value: profile.origin)
                    }
                }

                Section("Seal status") {
                    if let status = model.status {
                        LabeledContent("Initialized", value: status.initialized ? "Yes" : "No")
                        LabeledContent("Seal", value: status.sealed ? "Sealed" : "Unsealed")
                        LabeledContent("Type", value: status.type)
                        LabeledContent("Threshold / shares", value: "\(status.t) / \(status.n)")
                        LabeledContent("Progress", value: "\(status.progress) / \(status.t)")
                    } else {
                        Text("Status unknown — check before sending.")
                            .foregroundStyle(.secondary)
                    }

                    Button("Check status", systemImage: "arrow.clockwise", action: model.refresh)
                        .disabled(model.busy)
                }

                Section("Result") {
                    if model.busy {
                        ProgressView(model.activity)
                    }
                    Text(model.notice)
                        .font(.callout)
                }
            }
            .navigationTitle("Server details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showDetails = false
                    }
                }
            }
        }
    }

    private var replacement: some View {
        NavigationStack {
            Form {
                Section("Replace local share") {
                    secretEditor(replacing: true)
                } footer: {
                    Text("This replaces only the locally stored share. It does not rotate OpenBao keys or change the configured target.")
                }
            }
            .navigationTitle("Local share")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        clearDraft()
                        showReplacement = false
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func secretEditor(replacing: Bool) -> some View {
        SecureField("One Shamir share", text: $share)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.asciiCapable)
            .privacySensitive()
            .onChange(of: share) { _, value in
                if value.utf8.count > 1024 {
                    share = ""
                }
            }

        Toggle("I have an independent recovery copy", isOn: $recoveryConfirmed)

        Text("Paste is explicit. Existing clipboard/password-manager copies cannot be erased by this app. The share is never displayed or exported after saving.")
            .font(.footnote)
            .foregroundStyle(.secondary)

        Button(replacing ? "Save replacement with Face ID" : "Save share with Face ID") {
            let value = share
            let recovery = recoveryConfirmed
            clearDraft()
            if replacing {
                model.replaceShare(input: value, recoveryConfirmed: recovery)
            } else {
                model.importShare(
                    name: name,
                    address: address,
                    input: value,
                    recoveryConfirmed: recovery
                )
            }
        }
        .disabled(model.busy || share.isEmpty || !recoveryConfirmed)
    }

    private func clearDraft() {
        share.removeAll(keepingCapacity: false)
        recoveryConfirmed = false
    }
}

private enum PapercutPalette {
    static let sky = Color(red: 17 / 255, green: 50 / 255, blue: 79 / 255)
    static let mountainFar = Color(red: 72 / 255, green: 103 / 255, blue: 129 / 255)
    static let mountainMid = Color(red: 44 / 255, green: 81 / 255, blue: 110 / 255)
    static let mountainNear = Color(red: 20 / 255, green: 59 / 255, blue: 90 / 255)
    static let water = Color(red: 28 / 255, green: 67 / 255, blue: 95 / 255)
    static let forestMid = Color(red: 13 / 255, green: 43 / 255, blue: 66 / 255)
    static let forestFront = Color(red: 4 / 255, green: 26 / 255, blue: 44 / 255)
    static let cardBack2 = Color(red: 9 / 255, green: 46 / 255, blue: 84 / 255)
    static let cardBack1 = Color(red: 11 / 255, green: 54 / 255, blue: 97 / 255)
    static let card = Color(red: 14 / 255, green: 64 / 255, blue: 112 / 255)
    static let ring = Color(red: 55 / 255, green: 100 / 255, blue: 132 / 255)
    static let menu = Color(red: 11 / 255, green: 56 / 255, blue: 102 / 255)
    static let buttonBack = Color(red: 6 / 255, green: 61 / 255, blue: 145 / 255)
    static let button = Color(red: 10 / 255, green: 122 / 255, blue: 250 / 255)
    static let sealed = Color(red: 255 / 255, green: 79 / 255, blue: 56 / 255)
    static let unsealed = Color(red: 49 / 255, green: 208 / 255, blue: 170 / 255)
    static let sun = Color(red: 255 / 255, green: 89 / 255, blue: 64 / 255)
    static let cream = Color(red: 245 / 255, green: 232 / 255, blue: 204 / 255)
    static let secondaryText = Color(red: 150 / 255, green: 184 / 255, blue: 214 / 255)
}

private struct HeaderWaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 393
        let sy = rect.height / 165
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 393 * sx, y: 0))
        path.addLine(to: CGPoint(x: 393 * sx, y: 130 * sy))
        path.addCurve(
            to: CGPoint(x: 240 * sx, y: 124 * sy),
            control1: CGPoint(x: 339 * sx, y: 152 * sy),
            control2: CGPoint(x: 290 * sx, y: 141 * sy)
        )
        path.addCurve(
            to: CGPoint(x: 0, y: 127 * sy),
            control1: CGPoint(x: 167 * sx, y: 99 * sy),
            control2: CGPoint(x: 105 * sx, y: 155 * sy)
        )
        path.closeSubpath()
        return path
    }
}

private struct PapercutLandscape: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                MountainBackShape()
                    .fill(PapercutPalette.mountainFar)
                    .shadow(color: .black.opacity(0.22), radius: 5, y: 5)
                    .frame(height: 170)

                MountainMidShape()
                    .fill(PapercutPalette.mountainMid)
                    .shadow(color: .black.opacity(0.22), radius: 5, y: 5)
                    .frame(height: 145)

                Circle()
                    .fill(PapercutPalette.sun)
                    .frame(width: 84, height: 84)
                    .shadow(color: .black.opacity(0.22), radius: 5, y: 5)
                    .offset(y: 44)

                WaterShape()
                    .fill(PapercutPalette.water)
                    .shadow(color: .black.opacity(0.22), radius: 5, y: 5)
                    .frame(height: 92)

                SunReflectionShape()
                    .fill(PapercutPalette.sun)
                    .frame(width: 128, height: 38)
                    .offset(y: -15)

                HStack {
                    ForestLeftShape()
                        .frame(width: 95, height: 150)
                        .shadow(color: .black.opacity(0.22), radius: 5, y: 5)

                    Spacer(minLength: max(0, proxy.size.width - 190))

                    ForestRightShape()
                        .frame(width: 95, height: 150)
                        .shadow(color: .black.opacity(0.22), radius: 5, y: 5)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct MountainBackShape: Shape {
    func path(in rect: CGRect) -> Path {
        polygon(
            points: [
                (0, 110), (55, 60), (97, 90), (152, 36), (198, 82),
                (243, 45), (307, 106), (353, 76), (393, 110),
                (393, 170), (0, 170)
            ],
            source: CGSize(width: 393, height: 170),
            rect: rect
        )
    }
}

private struct MountainMidShape: Shape {
    func path(in rect: CGRect) -> Path {
        polygon(
            points: [
                (0, 90), (52, 59), (91, 80), (143, 38), (187, 80),
                (230, 49), (294, 95), (338, 75), (393, 105),
                (393, 145), (0, 145)
            ],
            source: CGSize(width: 393, height: 145),
            rect: rect
        )
    }
}

private struct WaterShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 393
        let sy = rect.height / 92
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 18 * sy))
        path.addCurve(
            to: CGPoint(x: 190 * sx, y: 20 * sy),
            control1: CGPoint(x: 62 * sx, y: 30 * sy),
            control2: CGPoint(x: 119 * sx, y: 10 * sy)
        )
        path.addCurve(
            to: CGPoint(x: 393 * sx, y: 30 * sy),
            control1: CGPoint(x: 263 * sx, y: 31 * sy),
            control2: CGPoint(x: 319 * sx, y: 19 * sy)
        )
        path.addLine(to: CGPoint(x: 393 * sx, y: 92 * sy))
        path.addLine(to: CGPoint(x: 0, y: 92 * sy))
        path.closeSubpath()
        return path
    }
}

private struct SunReflectionShape: Shape {
    func path(in rect: CGRect) -> Path {
        let source = CGSize(width: 128, height: 38)
        var result = Path()
        for points in [
            [(0.0, 0.0), (128.0, 0.0), (108.0, 9.0), (17.0, 9.0)],
            [(28.0, 18.0), (108.0, 18.0), (94.0, 25.0), (38.0, 25.0)],
            [(48.0, 33.0), (91.0, 33.0), (81.0, 38.0), (56.0, 38.0)]
        ] {
            result.addPath(polygon(points: points, source: source, rect: rect))
        }
        return result
    }
}

private struct ForestLeftShape: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                TreeShape(points: [(18, 25), (4, 67), (15, 67), (0, 107), (15, 107), (15, 150), (24, 150), (24, 107), (39, 107), (24, 67), (35, 67)], sourceWidth: 76)
                    .fill(PapercutPalette.forestMid)
                    .frame(width: 76, height: proxy.size.height)

                TreeShape(points: [(55, 8), (39, 60), (52, 60), (35, 112), (51, 112), (51, 150), (60, 150), (60, 112), (76, 112), (59, 60), (72, 60)], sourceWidth: 76)
                    .fill(PapercutPalette.forestFront)
                    .frame(width: 76, height: proxy.size.height)
            }
        }
    }
}

private struct ForestRightShape: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                TreeShape(points: [(70, 22), (56, 65), (67, 65), (52, 107), (67, 107), (67, 150), (76, 150), (76, 107), (91, 107), (76, 65), (87, 65)], sourceWidth: 95)
                    .fill(PapercutPalette.forestMid)

                TreeShape(points: [(35, 5), (19, 58), (32, 58), (15, 111), (31, 111), (31, 150), (40, 150), (40, 111), (56, 111), (39, 58), (52, 58)], sourceWidth: 95)
                    .fill(PapercutPalette.forestFront)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct TreeShape: Shape {
    let points: [(Double, Double)]
    let sourceWidth: Double

    func path(in rect: CGRect) -> Path {
        polygon(points: points, source: CGSize(width: sourceWidth, height: 150), rect: rect)
    }
}

private func polygon(
    points: [(Double, Double)],
    source: CGSize,
    rect: CGRect
) -> Path {
    var path = Path()
    guard let first = points.first else {
        return path
    }
    let sx = rect.width / source.width
    let sy = rect.height / source.height
    path.move(to: CGPoint(x: first.0 * sx, y: first.1 * sy))
    for point in points.dropFirst() {
        path.addLine(to: CGPoint(x: point.0 * sx, y: point.1 * sy))
    }
    path.closeSubpath()
    return path
}
