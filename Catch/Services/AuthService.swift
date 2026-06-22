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
        // 로컬 앱: 로그인 없이 즉시 사용. 로컬 식별자 + 캐시/기본 프로필.
        profile = Self.cachedProfile() ?? Profile(id: Self.localUserId, username: nil,
                                                  displayName: nil, avatarUrl: nil, bio: nil)
        state = .ready
        Task { await restore() }
    }

    /// 로컬 사용자 식별자(로그인 없이 스티커 소유자/경로에 사용). 한 번 생성해 영속.
    private static let localKey = "local_user_id"
    static let localUserId: UUID = {
        if let s = UserDefaults.standard.string(forKey: localKey), let id = UUID(uuidString: s) { return id }
        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: localKey)
        return id
    }()

    private static let cacheKey = "cached_profile"
    static func cachedProfile() -> Profile? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(Profile.self, from: data)
    }
    static func cache(_ p: Profile?) {
        if let p, let data = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        } else {
            UserDefaults.standard.removeObject(forKey: cacheKey)
        }
    }

    func restore() async {
        // 로컬 앱: 세션 없으면 그대로 로컬 사용(.ready 유지). 세션 있으면 프로필 갱신.
        guard let session = Supa.client.auth.currentSession else { return }
        await loadProfile(userId: session.user.id)
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
            errorMessage = String(localized: "로그인에 실패했어요. 다시 시도해주세요.")
            state = .signedOut
        }
    }

    private func loadProfile(userId: UUID) async {
        do {
            let p: Profile = try await Supa.client
                .from("profiles").select().eq("id", value: userId).single()
                .execute().value
            profile = p
            Self.cache(p)
            state = p.hasUsername ? .ready : .needsUsername
        } catch {
            // 네트워크 실패: 이미 들어가 있으면(.ready) 유지, 아니면 온보딩
            Log.auth.error("loadProfile failed: \(error.localizedDescription, privacy: .public)")
            if state != .ready { state = .needsUsername }
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
            errorMessage = String(localized: "사용자명 저장에 실패했어요.")
            return false
        }
    }

    /// 아바타 경로 변경을 로컬 프로필/캐시에 즉시 반영.
    func setAvatarPath(_ path: String?) {
        guard var p = profile else { return }
        p.avatarUrl = path
        profile = p
        Self.cache(p)
    }

    func signOut() async {
        try? await Supa.client.auth.signOut()
        Self.cache(nil)
        profile = nil
        state = .signedOut
    }

    func deleteAccount() async {
        _ = try? await Supa.client.rpc("delete_my_account").execute()
        await signOut()
    }
}
