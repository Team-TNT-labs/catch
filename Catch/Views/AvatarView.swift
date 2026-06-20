import SwiftUI

/// 프로필 아바타 — avatar_url(스토리지 경로)을 로드해 원형으로. 없으면 이니셜/아이콘 폴백.
struct AvatarView: View {
    let path: String?           // profiles.avatar_url (스토리지 경로)
    var fallbackText: String?   // 이니셜용(username 등)
    var size: CGFloat = 64

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Circle().fill(Theme.surface)
                if let ch = fallbackText?.trimmingCharacters(in: .whitespaces).first {
                    Text(String(ch).uppercased())
                        .font(.system(size: size * 0.42, weight: .heavy))
                        .foregroundStyle(Theme.grape)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.45)).foregroundStyle(Theme.grape)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: path) {
            image = nil
            guard let path, !path.isEmpty else { return }
            image = await ProfileRepository.shared.avatarImage(path: path)
        }
    }
}
