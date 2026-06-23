import SwiftUI

/// 약관·개인정보 문서 — 앱 내에서만 표시(외부 브라우저로 안 나감, 404 없음).
enum LegalDoc: String, Identifiable {
    case privacy, terms
    var id: String { rawValue }
}

/// 법적 고지 화면. 현재 로케일이 한국어면 국문, 그 외엔 영문.
struct LegalView: View {
    let doc: LegalDoc
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    private var isKorean: Bool { locale.language.languageCode?.identifier == "ko" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(title).font(.title2.bold()).foregroundStyle(Theme.ink)
                    Text(effective).font(.footnote).foregroundStyle(Theme.muted)
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, sec in
                        VStack(alignment: .leading, spacing: 6) {
                            if !sec.0.isEmpty {
                                Text(sec.0).font(.headline).foregroundStyle(Theme.ink)
                            }
                            Text(sec.1).font(.subheadline).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text(isKorean ? "문의: tntlabgo@gmail.com — Gojaehyun (tntlabs)"
                                  : "Contact: tntlabgo@gmail.com — Gojaehyun (tntlabs)")
                        .font(.footnote).foregroundStyle(Theme.muted).padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isKorean ? "완료" : "Done") { dismiss() }.foregroundStyle(Theme.lime)
                }
            }
        }
    }

    private var title: String {
        switch doc {
        case .privacy: return isKorean ? "개인정보처리방침" : "Privacy Policy"
        case .terms:   return isKorean ? "이용약관" : "Terms of Use"
        }
    }

    private var effective: String { isKorean ? "시행일: 2026년 6월 22일" : "Effective: June 22, 2026" }

    private var sections: [(String, String)] {
        switch doc {
        case .privacy: return isKorean ? privacyKO : privacyEN
        case .terms:   return isKorean ? termsKO : termsEN
        }
    }

    // MARK: - 개인정보처리방침

    private var privacyKO: [(String, String)] {[
        ("", "Catch(이하 ‘앱’)는 이용자의 프라이버시를 가장 중요하게 생각합니다. Catch는 로컬 우선(local-first) 앱으로, 수집한 스티커와 사진은 기본적으로 이용자의 기기에만 저장됩니다."),
        ("1. 수집·이용하는 정보", "카메라/사진은 스티커를 만들기 위해서만 사용됩니다. 배경 제거(누끼)는 전부 기기 내에서(Apple Vision) 처리되며 사진은 서버로 전송·저장되지 않습니다. 수집한 스티커·폴더는 기기에 로컬 저장됩니다. 구매 정보는 Apple App Store가 처리하며 Catch는 카드 정보를 받지 않습니다. 이름·이메일·전화번호 등 개인 식별 정보는 별도로 수집하지 않습니다."),
        ("2. 백업", "Catch Pro의 백업은 이용자가 직접 백업 파일을 만들어 파일/iCloud 등 선택한 위치에 저장합니다. 백업 파일은 Catch 서버에 보관되지 않으며 관리 책임은 이용자에게 있습니다."),
        ("3. 제3자 제공", "Catch는 이용자의 콘텐츠를 제3자에게 판매하거나 공유하지 않습니다. 결제 처리에 한해 Apple이 관여하며, 이는 Apple 개인정보처리방침을 따릅니다."),
        ("4. 권한", "카메라 — 스티커 촬영 시. 사진 — 앨범에서 사진을 불러와 스티커로 만들 때(Catch Pro). 시스템 사진 선택기를 사용하며 전체 앨범 접근 권한은 요구하지 않습니다."),
        ("5. 아동의 개인정보", "Catch는 만 13세 미만 아동으로부터 의도적으로 개인정보를 수집하지 않습니다."),
        ("6. 보관 및 삭제", "로컬 데이터는 앱을 삭제하면 함께 삭제됩니다(별도 백업 파일 제외). Catch 서버에 보관되는 개인정보는 없습니다."),
        ("7. 변경 고지", "본 방침이 변경되면 본 화면을 통해 공지합니다."),
    ]}

    private var privacyEN: [(String, String)] {[
        ("", "Catch (the “App”) is built privacy-first. Catch is a local-first app: the stickers and photos you collect stay on your device by default."),
        ("1. Information We Handle", "Camera/Photos are used solely to create stickers. Background removal runs entirely on-device (Apple Vision); your photos are never uploaded to or stored on Catch servers. Your stickers & folders are stored locally. Purchases are processed by the Apple App Store; card details are handled by Apple and not shared with Catch. Catch does not separately collect your name, email, or phone number."),
        ("2. Backup", "Catch Pro’s backup lets you create a backup file and save it to a location you choose (Files, iCloud, etc.). Backup files are not stored on Catch servers; you are responsible for managing them."),
        ("3. Third Parties", "Catch does not sell or share your content with third parties. Apple is involved only for payment processing, subject to Apple’s Privacy Policy."),
        ("4. Permissions", "Camera — to capture stickers. Photos — to import a photo and turn it into a sticker (Catch Pro). We use the system photo picker and do not request full library access."),
        ("5. Children", "Catch does not knowingly collect personal information from children under 13."),
        ("6. Retention & Deletion", "Local data is removed when you delete the app (except backup files you exported). No personal data is retained on Catch servers."),
        ("7. Changes", "If this policy changes, we will post updates on this screen."),
    ]}

    // MARK: - 이용약관

    private var termsKO: [(String, String)] {[
        ("", "본 약관은 Catch(이하 ‘앱’) 이용에 적용됩니다. 앱을 사용함으로써 본 약관에 동의하는 것으로 간주됩니다."),
        ("1. 서비스", "Catch는 사진으로 스티커를 만들어 모으는 로컬 우선 앱입니다. 수집물은 기본적으로 기기에 저장됩니다."),
        ("2. Catch Pro 구독", "Catch Pro는 월/연 구독 또는 평생 결제로 제공됩니다. 구독은 기간이 끝나기 전 취소하지 않으면 자동 갱신되며, 갱신 24시간 이내에 Apple ID 설정에서 관리·해지할 수 있습니다. 결제는 구매 확정 시 Apple 계정으로 청구됩니다."),
        ("3. 콘텐츠 책임", "이용자가 만든 스티커·백업 파일의 관리 책임은 이용자에게 있습니다. 앱 삭제 시 로컬 데이터는 함께 삭제됩니다."),
        ("4. 면책", "앱은 ‘있는 그대로’ 제공되며, 법이 허용하는 범위에서 묵시적 보증을 포함한 모든 보증을 배제합니다."),
        ("5. 표준 EULA", "본 약관에 명시되지 않은 사항은 Apple의 표준 최종 사용자 사용권 계약(Apple Standard EULA)을 따릅니다."),
        ("6. 변경", "약관이 변경되면 본 화면을 통해 공지합니다."),
    ]}

    private var termsEN: [(String, String)] {[
        ("", "These terms apply to your use of Catch (the “App”). By using the App you agree to these terms."),
        ("1. Service", "Catch is a local-first app for making and collecting stickers from photos. Your collection is stored on your device by default."),
        ("2. Catch Pro Subscription", "Catch Pro is offered as a monthly/yearly subscription or a one-time lifetime purchase. Subscriptions auto-renew unless cancelled at least 24 hours before the end of the period; manage or cancel anytime in your Apple ID settings. Payment is charged to your Apple account upon confirmation."),
        ("3. Your Content", "You are responsible for managing the stickers and backup files you create. Deleting the app removes local data."),
        ("4. Disclaimer", "The App is provided “as is,” and to the extent permitted by law all warranties, including implied warranties, are disclaimed."),
        ("5. Standard EULA", "Matters not covered here are governed by Apple’s Standard End User License Agreement (Apple Standard EULA)."),
        ("6. Changes", "If these terms change, we will post updates on this screen."),
    ]}
}
