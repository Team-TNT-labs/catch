import SwiftUI

/// SETLOG 터미널 톤 — username 설정.
struct OnboardingUsernameView: View {
    @EnvironmentObject private var auth: AuthService
    @State private var username = ""
    @State private var status: Status = .idle
    @State private var saving = false
    @State private var checkTask: Task<Void, Never>?

    enum Status: Equatable { case idle, checking, available, taken, invalid }

    private var normalized: String { username.lowercased() }
    private var formatValid: Bool { normalized.range(of: "^[a-z0-9_]{2,20}$", options: .regularExpression) != nil }
    private var canSubmit: Bool { status == .available && !saving }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("→ username")
                .font(.mono(22, .bold))
                .foregroundStyle(Theme.ink)

            Text("사용할 이름을 정해주세요.")
                .foregroundStyle(Theme.muted)

            HStack(spacing: 4) {
                Text("@").font(.mono(20)).foregroundStyle(Theme.coral)
                TextField("", text: $username, prompt: Text("username").foregroundColor(Theme.muted.opacity(0.6)))
                    .font(.mono(20))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(Theme.ink)
                    .onChange(of: username) { _, _ in scheduleCheck() }
                statusIcon
            }
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) {
                Rectangle().fill(underlineColor).frame(height: 1.5)
            }

            statusText

            Spacer()

            Button {
                saving = true
                Task { _ = await auth.setUsername(normalized); saving = false }
            } label: {
                Text(saving ? "saving…" : "continue →")
                    .font(.mono(17, .semibold))
                    .underline()
                    .foregroundStyle(canSubmit ? Theme.ink : Theme.muted.opacity(0.5))
            }
            .disabled(!canSubmit || saving)
            .padding(.bottom, 24)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.ignoresSafeArea())
    }

    private var underlineColor: Color {
        switch status {
        case .available: return Theme.coral
        case .taken, .invalid: return .red
        default: return Theme.surface
        }
    }

    @ViewBuilder private var statusIcon: some View {
        switch status {
        case .checking: ProgressView().tint(Theme.coral)
        case .available: Image(systemName: "checkmark").foregroundStyle(Theme.coral)
        case .taken, .invalid: Image(systemName: "xmark").foregroundStyle(.red)
        case .idle: EmptyView()
        }
    }

    @ViewBuilder private var statusText: some View {
        switch status {
        case .invalid: Text("a-z, 0-9, _ · 2–20자").font(.mono(12)).foregroundStyle(.red)
        case .taken: Text("이미 사용 중이에요").font(.mono(12)).foregroundStyle(.red)
        case .available: Text("사용 가능 ✓").font(.mono(12)).foregroundStyle(Theme.coral)
        default: Text("a-z, 0-9, _ · 2–20자").font(.mono(12)).foregroundStyle(Theme.muted)
        }
    }

    private func scheduleCheck() {
        checkTask?.cancel()
        guard !username.isEmpty else { status = .idle; return }
        guard formatValid else { status = .invalid; return }
        status = .checking
        checkTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            let ok = await auth.isUsernameAvailable(normalized)
            if Task.isCancelled { return }
            status = ok ? .available : .taken
        }
    }
}
