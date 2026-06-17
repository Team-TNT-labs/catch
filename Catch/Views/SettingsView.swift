import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var working = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 44)).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(auth.profile?.displayName ?? "Catch 사용자")
                                .font(.headline)
                            Text("@\(auth.profile?.username ?? "")")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    Button(role: .destructive) {
                        working = true
                        Task { await auth.signOut(); working = false; dismiss() }
                    } label: { Label("로그아웃", systemImage: "rectangle.portrait.and.arrow.right") }

                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: { Label("계정 삭제", systemImage: "trash") }
                }

                Section {
                    Link(destination: URL(string: "https://github.com/Gojaehyeon/catch")!) {
                        Label("정보", systemImage: "info.circle")
                    }
                } footer: {
                    Text("Catch")
                }
            }
            .navigationTitle("프로필")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } } }
            .disabled(working)
            .alert("계정을 삭제할까요?", isPresented: $confirmDelete) {
                Button("취소", role: .cancel) {}
                Button("삭제", role: .destructive) {
                    working = true
                    Task { await auth.deleteAccount(); working = false; dismiss() }
                }
            } message: {
                Text("프로필과 모든 수집이 영구 삭제되며 되돌릴 수 없어요.")
            }
        }
    }
}
