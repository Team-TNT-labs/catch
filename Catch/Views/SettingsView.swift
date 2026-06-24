import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import StoreKit

/// 백업 파일(JSON) 래퍼.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

/// 설정 — took식 Form 구조(업그레이드 배너 행 / 꾸미기 / 백업 / 개발자 소개).
struct SettingsView: View {
    var onRestore: () -> Void = {}
    var onBackgroundChange: () -> Void = {}

    @EnvironmentObject private var pro: ProStore
    @EnvironmentObject private var locales: LocaleManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showPaywall = false
    @State private var showExport = false
    @State private var showImport = false
    @State private var exportData: Data?
    @State private var backupWorking = false

    var body: some View {
        NavigationStack {
            ZStack {
                background
                Form {
                    // ── Pro 업그레이드 / 사용 중 (전체 폭 행, took식)
                    Section {
                        if pro.isPro {
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.seal.fill").font(.title2).foregroundStyle(Theme.lime)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Catch Pro 사용 중").font(.headline).foregroundStyle(Theme.ink)
                                    Text("모든 기능이 열려 있어요").font(.caption).foregroundStyle(Theme.muted)
                                }
                            }
                            .padding(.vertical, 4)
                            Button("구독 관리") { Task { await openManageSubscriptions() } }
                                .foregroundStyle(Theme.lime)
                        } else {
                            Button { showPaywall = true } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "sparkles").font(.title2).foregroundStyle(Theme.lime)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Catch Pro로 업그레이드").font(.headline).foregroundStyle(Theme.ink)
                                        Text("사진 가져오기 · 폴더 무제한 · 배경 꾸미기").font(.caption).foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Theme.muted)
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowBackground(Theme.surface.opacity(0.5))

                    // ── 일반 (프로 배너 바로 아래)
                    Section {
                        NavigationLink {
                            LanguagePickerView(locales: locales)
                        } label: {
                            HStack {
                                Label("언어", systemImage: "globe").foregroundStyle(Theme.ink)
                                Spacer()
                                Text(LanguagePickerView.displayName(for: locales.languageCode)).foregroundStyle(Theme.muted)
                            }
                        }
                        .listRowBackground(Theme.surface.opacity(0.5))
                    } header: { Text("일반").foregroundStyle(Theme.muted) }

                    // ── 꾸미기 (Pro 전용: 무료는 진입 불가 → 페이월)
                    Section {
                        if pro.isPro {
                            NavigationLink {
                                JarBackgroundView(onBackgroundChange: onBackgroundChange).environmentObject(pro)
                            } label: { Label("배경 꾸미기", systemImage: "paintbrush").foregroundStyle(Theme.ink) }
                                .listRowBackground(Theme.surface.opacity(0.5))
                        } else {
                            Button { showPaywall = true } label: {
                                HStack {
                                    Label("배경 꾸미기", systemImage: "paintbrush").foregroundStyle(Theme.muted)
                                    Spacer()
                                    Image(systemName: "lock.fill").font(.caption).foregroundStyle(Theme.muted)
                                }
                            }
                            .listRowBackground(Theme.surface.opacity(0.5))
                        }
                    } header: { Text("꾸미기").foregroundStyle(Theme.muted) } footer: {
                        if !pro.isPro {
                            Label("배경 꾸미기는 Catch Pro 전용이에요", systemImage: "lock.fill").foregroundStyle(Theme.muted)
                        }
                    }

                    // ── 백업(무료에서도 표시, 비활성)
                    Section {
                        Button {
                            backupWorking = true
                            Task { exportData = await CatchRepository.shared.exportBackup(); backupWorking = false; showExport = true }
                        } label: { backupRow("백업 내보내기", icon: "square.and.arrow.up") }
                            .disabled(!pro.isPro || backupWorking).listRowBackground(Theme.surface.opacity(0.5))
                        Button { showImport = true } label: { backupRow("백업 불러오기", icon: "square.and.arrow.down") }
                            .disabled(!pro.isPro).listRowBackground(Theme.surface.opacity(0.5))
                    } header: { Text("백업").foregroundStyle(Theme.muted) } footer: {
                        if !pro.isPro {
                            Label("백업 & 복원은 Catch Pro 전용이에요", systemImage: "lock.fill").foregroundStyle(Theme.muted)
                        }
                    }

                    // ── 개발자 소개
                    Section {
                        NavigationLink {
                            DeveloperView().environmentObject(pro)
                        } label: { Label("개발자 소개", systemImage: "person.crop.circle").foregroundStyle(Theme.ink) }
                            .listRowBackground(Theme.surface.opacity(0.5))
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }.foregroundStyle(Theme.lime)
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView().environmentObject(pro).environment(\.locale, locales.locale).id(locales.refresh)
            }
            .fileExporter(isPresented: $showExport,
                          document: BackupDocument(data: exportData ?? Data()),
                          contentType: .json, defaultFilename: "Catch-backup") { _ in }
            .fileImporter(isPresented: $showImport, allowedContentTypes: [.json]) { result in
                guard case .success(let url) = result else { return }
                Task {
                    let ok = url.startAccessingSecurityScopedResource()
                    defer { if ok { url.stopAccessingSecurityScopedResource() } }
                    if let data = try? Data(contentsOf: url), await CatchRepository.shared.importBackup(data) {
                        onRestore(); dismiss()
                    }
                }
            }
        }
    }

    private var background: some View {
        ZStack {
            Color.black
            LinearGradient(colors: [Theme.lime.opacity(0.14), .clear], startPoint: .top, endPoint: .center)
        }
        .ignoresSafeArea()
    }

    /// 백업 행 — 무료면 자물쇠를 덧붙여 비활성 의미를 명확히.
    private func backupRow(_ title: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon).foregroundStyle(pro.isPro ? Theme.ink : Theme.muted)
            Spacer()
            if !pro.isPro { Image(systemName: "lock.fill").font(.caption).foregroundStyle(Theme.muted) }
        }
    }

    /// `.manageSubscriptionsSheet`는 컨텍스트 없을 때 조용히 실패 — API 직접 호출 후 App Store로 폴백.
    private func openManageSubscriptions() async {
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) {
            if (try? await AppStore.showManageSubscriptions(in: scene)) != nil { return }
        }
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") { openURL(url) }
    }
}

/// 개발자 소개 — 사진(이스터에그: 5탭 Pro 토글) + 링크.
struct DeveloperView: View {
    @EnvironmentObject private var pro: ProStore
    @Environment(\.openURL) private var openURL
    @State private var taps = 0
    @State private var devOn = false
    @State private var showDevAlert = false

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image("DevPhoto")
                .resizable().scaledToFill()
                .frame(width: 130, height: 130)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                .contentShape(Circle())
                .onTapGesture {   // 이스터에그: 5번 탭마다 Pro 활성 ↔ 비활성 토글 (디버그 전용)
                    #if DEBUG
                    taps += 1
                    if taps >= 5 {
                        taps = 0
                        devOn = pro.toggleDevPro()
                        showDevAlert = true
                    }
                    #endif
                }
                .sensoryFeedback(.impact, trigger: taps)
            Text("Gojaehyun").font(.title.bold()).foregroundStyle(Theme.ink)
            Text("CEO @tntlabs\nProject Manager @Savetokip")
                .font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            HStack(spacing: 10) {
                link("GitHub", icon: "chevron.left.forwardslash.chevron.right", url: "https://github.com/Gojaehyeon")
                link("Instagram", icon: "play.rectangle.fill", url: "https://www.instagram.com/reel/DZJ4CA6vyLz/?igsh=MTR5aHF5eTVxNHpxcA==")
            }
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("개발자 소개")
        .navigationBarTitleDisplayMode(.inline)
        .alert("개발자 모드", isPresented: $showDevAlert) {
            Button("확인", role: .cancel) {}
        } message: { Text(devOn ? "Catch Pro가 잠금 해제됐어요. (테스트)" : "Catch Pro 잠금이 해제 취소됐어요.") }
    }

    private func link(_ title: String, icon: String, url: String) -> some View {
        Button { if let u = URL(string: url) { openURL(u) } } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                .padding(.vertical, 10).padding(.horizontal, 18)
                .background(Theme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// 항아리 배경(Pro) — 기본/단색/사진.
struct JarBackgroundView: View {
    var onBackgroundChange: () -> Void = {}
    @EnvironmentObject private var pro: ProStore
    @EnvironmentObject private var locales: LocaleManager
    @ObservedObject private var jarBg = JarBackgroundStore.shared
    @State private var bgPhotoItem: PhotosPickerItem?
    @State private var showPaywall = false

    var body: some View {
        Group {
            if pro.isPro { picker } else { locked }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("배경 꾸미기")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(pro).environment(\.locale, locales.locale).id(locales.refresh)
        }
        .onChange(of: bgPhotoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    jarBg.setPhoto(img.resized(maxDimension: 1400)); onBackgroundChange()
                }
                bgPhotoItem = nil
            }
        }
    }

    private var locked: some View {
        VStack(spacing: 16) {
            Image(systemName: "crown.fill").font(.system(size: 44)).foregroundStyle(Theme.lime)
            Text("배경 꾸미기는 Catch Pro 기능이에요").font(.headline).foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Button { showPaywall = true } label: {
                Text("Catch Pro 시작하기").font(.headline).foregroundStyle(.black)
                    .padding(.horizontal, 22).frame(height: 50).background(Theme.lime, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
    }

    private var picker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("색").font(.headline).foregroundStyle(Theme.ink)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 14) {
                    swatch(selected: jarBg.colorHex == nil && !jarBg.hasPhoto, fill: AnyView(defaultIcon)) {
                        jarBg.reset(); onBackgroundChange()
                    }
                    ForEach(JarBackgroundStore.palette, id: \.self) { hex in
                        swatch(selected: jarBg.colorHex == String(format: "%06X", Int(hex)),
                               fill: AnyView(Circle().fill(Color(hex: hex)))) {
                            jarBg.setColor(hex); onBackgroundChange()
                        }
                    }
                }
                Text("사진").font(.headline).foregroundStyle(Theme.ink).padding(.top, 6)
                PhotosPicker(selection: $bgPhotoItem, matching: .images) {
                    Label("앨범에서 사진 고르기", systemImage: "photo")
                        .font(.subheadline.bold()).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Theme.lime, in: Capsule())
                }
                if jarBg.hasPhoto {
                    Text("현재 사진 배경 사용 중").font(.caption).foregroundStyle(Theme.muted)
                }
            }
            .padding(20)
        }
    }

    private var defaultIcon: some View {
        ZStack { Circle().fill(Theme.surface); Image(systemName: "circle.lefthalf.filled").foregroundStyle(.white) }
    }

    private func swatch(selected: Bool, fill: AnyView, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            fill.frame(height: 52)
                .overlay(Circle().strokeBorder(Theme.lime, lineWidth: selected ? 3 : 0))
        }
        .buttonStyle(.plain)
    }
}
