import Foundation
import SwiftUI

// 앱 내 즉시 언어 전환: Bundle.main을 스위즐해 선택한 언어의 .lproj에서 문자열을 찾고,
// 루트 뷰를 다시 그려 반영한다. (took와 동일한 기법)

private var bundleKey: UInt8 = 0

final class LocalizedBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let bundle = objc_getAssociatedObject(self, &bundleKey) as? Bundle {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    private static let swizzleOnce: Void = {
        object_setClass(Bundle.main, LocalizedBundle.self)
    }()

    /// Bundle.main을 특정 언어 리소스로 지정(nil = 시스템 기본).
    static func setLanguage(_ code: String?) {
        _ = swizzleOnce
        var target: Bundle?
        if let code, let path = Bundle.main.path(forResource: code, ofType: "lproj") {
            target = Bundle(path: path)
        }
        objc_setAssociatedObject(Bundle.main, &bundleKey, target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

@MainActor
final class LocaleManager: ObservableObject {
    @Published var languageCode: String?   // nil = 시스템 기본
    @Published var refresh = UUID()        // UI 재구성 트리거

    private let key = "catch.langOverride"

    init() {
        languageCode = UserDefaults.standard.string(forKey: key)
        Bundle.setLanguage(languageCode)
    }

    func set(_ code: String?) {
        guard code != languageCode else { return }
        languageCode = code
        if let code {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
            UserDefaults.standard.set(code, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            UserDefaults.standard.removeObject(forKey: key)
        }
        Bundle.setLanguage(code)
        refresh = UUID()
    }

    var locale: Locale {
        languageCode.map { Locale(identifier: $0) } ?? .autoupdatingCurrent
    }
}

struct LanguagePickerView: View {
    @ObservedObject var locales: LocaleManager
    @Environment(\.dismiss) private var dismiss

    static let languages: [(code: String?, name: String)] = [
        (nil, String(localized: "시스템 기본")),
        ("en", "English"),
        ("ko", "한국어"),
        ("ja", "日本語"),
        ("zh-Hans", "简体中文"),
        ("es", "Español"),
        ("fr", "Français"),
        ("de", "Deutsch")
    ]

    static func displayName(for code: String?) -> String {
        languages.first { $0.code == code }?.name ?? String(localized: "시스템 기본")
    }

    var body: some View {
        List {
            ForEach(Self.languages, id: \.name) { lang in
                Button {
                    locales.set(lang.code)
                    dismiss()
                } label: {
                    HStack {
                        Text(lang.name).foregroundStyle(Theme.ink)
                        Spacer()
                        if lang.code == locales.languageCode {
                            Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Theme.lime)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Theme.surface.opacity(0.5))
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("언어")
        .navigationBarTitleDisplayMode(.inline)
    }
}
