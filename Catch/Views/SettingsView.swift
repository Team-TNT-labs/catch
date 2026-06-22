import SwiftUI
import UniformTypeIdentifiers

/// 백업 파일(JSON) 래퍼.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct SettingsView: View {
    var onRestore: () -> Void = {}

    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var pro: ProStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showPaywall = false
    @State private var devTaps = 0
    @State private var showExport = false
    @State private var showImport = false
    @State private var exportData: Data?
    @State private var backupWorking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    developerIntro
                    proCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Catch!")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showPaywall) { PaywallView().environmentObject(pro) }
            .fileExporter(isPresented: $showExport,
                          document: BackupDocument(data: exportData ?? Data()),
                          contentType: .json,
                          defaultFilename: "Catch-backup") { _ in }
            .fileImporter(isPresented: $showImport, allowedContentTypes: [.json]) { result in
                guard case .success(let url) = result else { return }
                Task {
                    let ok = url.startAccessingSecurityScopedResource()
                    defer { if ok { url.stopAccessingSecurityScopedResource() } }
                    if let data = try? Data(contentsOf: url),
                       await CatchRepository.shared.importBackup(data) {
                        onRestore()
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - 개발자 소개

    private var developerIntro: some View {
        VStack(spacing: 12) {
            Image("DevPhoto")
                .resizable().scaledToFill()
                .frame(width: 120, height: 120)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                .onTapGesture {   // 숨은 개발자 토글: 5번 탭하면 Pro 잠금 해제(테스트용)
                    devTaps += 1
                    if devTaps >= 5 { devTaps = 0; pro.toggleDevPro() }
                }

            Text("Gojaehyun").font(.title2.bold()).foregroundStyle(.white)
            Text("CEO @tntlabs\nProject Manager @Savetokip")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                linkButton("GitHub", icon: "chevron.left.forwardslash.chevron.right",
                           url: "https://github.com/Gojaehyeon")
                linkButton("Instagram", icon: "play.rectangle.fill",
                           url: "https://www.instagram.com/reel/DZJ4CA6vyLz/?igsh=MTR5aHF5eTVxNHpxcA==")
            }
            .padding(.top, 4)
        }
    }

    private func linkButton(_ title: String, icon: String, url: String) -> some View {
        Button {
            if let u = URL(string: url) { openURL(u) }
        } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                .padding(.vertical, 10).padding(.horizontal, 18)
                .background(Theme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Catch Pro

    private var proCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "crown.fill").foregroundStyle(Theme.lime)
                Text("Catch Pro").font(.title3.bold()).foregroundStyle(Theme.ink)
                Spacer()
                if pro.isPro {
                    Text("사용 중").font(.caption.bold()).foregroundStyle(.black)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Theme.lime, in: Capsule())
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                proPerk("photo.on.rectangle", "사진앨범에서 불러오기")
                proPerk("folder.fill.badge.plus", "폴더 무제한 (무료 7개까지)")
                proPerk("icloud.and.arrow.up.fill", "수집 백업 & 복원")
            }
            if pro.isPro {
                HStack(spacing: 10) {
                    Button {
                        backupWorking = true
                        Task { exportData = await CatchRepository.shared.exportBackup(); backupWorking = false; showExport = true }
                    } label: { backupLabel("백업 내보내기", "square.and.arrow.up") }
                    .disabled(backupWorking)
                    Button { showImport = true } label: { backupLabel("백업 불러오기", "square.and.arrow.down") }
                }
                .padding(.top, 2)
            } else {
                Button { showPaywall = true } label: {
                    Text("Catch Pro 시작하기").font(.headline).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(Theme.lime, in: Capsule())
                }
                .padding(.top, 2)
            }
        }
        .padding(20)
        .background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.lime.opacity(0.5), lineWidth: 1.5))
    }

    private func backupLabel(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity).frame(height: 44)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func proPerk(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(Theme.lime).frame(width: 26)
            Text(text).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
            Spacer()
        }
    }
}
