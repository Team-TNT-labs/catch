import SwiftUI

/// 최초 로그인 시 username 설정. 형식·중복·예약어를 실시간 확인.
struct OnboardingUsernameView: View {
    @EnvironmentObject private var auth: AuthService
    @State private var username = ""
    @State private var status: Status = .idle
    @State private var saving = false
    @State private var checkTask: Task<Void, Never>?

    enum Status: Equatable { case idle, checking, available, taken, invalid }

    private var normalized: String { username.lowercased() }
    private var formatValid: Bool { normalized.range(of: "^[a-z0-9_]{3,20}$", options: .regularExpression) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("사용자명을 정해주세요")
                .font(.title.bold())
                .foregroundStyle(.white)
            Text("영문 소문자·숫자·밑줄(_) 3~20자")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))

            HStack(spacing: 6) {
                Text("@").foregroundStyle(.white.opacity(0.5))
                TextField("", text: $username, prompt: Text("username").foregroundColor(.white.opacity(0.3)))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(.white)
                    .onChange(of: username) { _, _ in scheduleCheck() }
                statusIcon
            }
            .padding(.horizontal, 16).frame(height: 52)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

            statusText

            Spacer()

            Button {
                saving = true
                Task {
                    _ = await auth.setUsername(normalized)
                    saving = false
                }
            } label: {
                Text("시작하기").font(.headline).foregroundStyle(.black)
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(canSubmit ? Color.white : Color.white.opacity(0.3),
                                in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!canSubmit || saving)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.ignoresSafeArea())
    }

    private var canSubmit: Bool { status == .available && !saving }

    @ViewBuilder private var statusIcon: some View {
        switch status {
        case .checking: ProgressView().tint(.white)
        case .available: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .taken, .invalid: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .idle: EmptyView()
        }
    }

    @ViewBuilder private var statusText: some View {
        switch status {
        case .invalid: Text("형식이 올바르지 않아요").foregroundStyle(.red).font(.caption)
        case .taken: Text("이미 사용 중이거나 사용할 수 없어요").foregroundStyle(.red).font(.caption)
        case .available: Text("사용 가능해요").foregroundStyle(.green).font(.caption)
        default: EmptyView()
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
