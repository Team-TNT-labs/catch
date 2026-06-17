import Foundation
import Supabase

/// 인증·세션·프로필 상태를 관리한다.
@MainActor
final class AuthService: ObservableObject {
    enum State: Equatable {
        case loading        // 세션 복원 중
        case signedOut      // 미로그인
        case needsUsername  // 로그인됐으나 username 미설정(온보딩)
        case ready          // 사용 가능
    }

    @Published var state: State = .loading
    @Published var profile: Profile?
    @Published var errorMessage: String?

    private let apple = AppleSignInCoordinator()

    init() {
        Task { await restore() }
    }

    func restore() async {
        do {
            let session = try await Supa.client.auth.session
            await loadProfile(userId: session.user.id)
        } catch {
            state = .signedOut
        }
    }

    func signInWithApple() async {
        do {
            let (idToken, nonce) = try await apple.signIn()
            let session = try await Supa.client.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
            )
            await loadProfile(userId: session.user.id)
        } catch is CancellationError {
            // 사용자가 취소
        } catch {
            errorMessage = "로그인에 실패했어요. 다시 시도해주세요."
            state = .signedOut
        }
    }

    private func loadProfile(userId: UUID) async {
        do {
            let p: Profile = try await Supa.client
                .from("profiles").select().eq("id", value: userId).single()
                .execute().value
            profile = p
            state = p.hasUsername ? .ready : .needsUsername
        } catch {
            // 트리거 지연 등으로 행이 아직 없으면 온보딩으로
            state = .needsUsername
        }
    }

    func isUsernameAvailable(_ name: String) async -> Bool {
        do {
            let ok: Bool = try await Supa.client
                .rpc("username_available", params: ["name": name])
                .execute().value
            return ok
        } catch {
            return false
        }
    }

    func setUsername(_ name: String) async -> Bool {
        do {
            let userId = try await Supa.client.auth.session.user.id
            try await Supa.client.from("profiles")
                .update(["username": name])
                .eq("id", value: userId)
                .execute()
            await loadProfile(userId: userId)
            return state == .ready
        } catch {
            errorMessage = "사용자명 저장에 실패했어요."
            return false
        }
    }

    func signOut() async {
        try? await Supa.client.auth.signOut()
        profile = nil
        state = .signedOut
    }

    func deleteAccount() async {
        _ = try? await Supa.client.rpc("delete_my_account").execute()
        await signOut()
    }
}
