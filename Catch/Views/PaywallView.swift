import SwiftUI
import StoreKit

/// took식 페이월 — 헤더 / 기능 카드 / 플랜 카드 / 구매·복원·약관.
struct PaywallView: View {
    @EnvironmentObject private var pro: ProStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var selected: Product?
    @State private var working = false
    @State private var legalDoc: LegalDoc?

    private let features: [(String, String)] = [
        ("photo.on.rectangle", "사진앨범에서 스티커 가져오기"),
        ("folder.fill.badge.plus", "폴더 무제한 (무료는 7개까지)"),
        ("paintbrush.fill", "배경 꾸미기"),
        ("icloud.and.arrow.up.fill", "수집 백업 & 복원"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    featureList
                    planList
                    VStack(spacing: 12) {
                        purchaseButton
                        restoreButton
                        legalLinks
                        footnote
                    }
                }
                .padding(20)
            }
            .background(backdrop)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .onChange(of: pro.isPro) { _, p in if p { dismiss() } }
        .onChange(of: pro.products.count) { _, _ in if selected == nil { selected = defaultPlan } }
        .onAppear { if selected == nil { selected = defaultPlan } }
    }

    private var defaultPlan: Product? { pro.yearly ?? pro.lifetime ?? pro.products.first }

    private var backdrop: some View {
        ZStack {
            Color.black
            LinearGradient(colors: [Theme.lime.opacity(0.18), .clear], startPoint: .top, endPoint: .center)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Theme.lime.opacity(0.16))
                    .frame(width: 88, height: 88)
                Image(systemName: "crown.fill").font(.system(size: 40)).foregroundStyle(Theme.lime)
            }
            Text("Catch Pro").font(.largeTitle.bold()).foregroundStyle(Theme.ink)
            Text("수집을 더 자유롭게, 더 멋지게.").font(.subheadline).foregroundStyle(Theme.muted)
        }
        .padding(.top, 8)
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(features, id: \.1) { icon, text in
                HStack(spacing: 12) {
                    Image(systemName: icon).font(.headline).foregroundStyle(Theme.lime).frame(width: 26)
                    Text(LocalizedStringKey(text)).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                    Spacer()
                }
            }
        }
        .padding(18)
        .background(Theme.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var planList: some View {
        VStack(spacing: 10) {
            if pro.products.isEmpty {
                ProgressView().tint(Theme.lime).padding()
            } else {
                ForEach(pro.products, id: \.id) { planRow($0) }
            }
        }
    }

    private func planRow(_ product: Product) -> some View {
        let isSel = selected?.id == product.id
        return Button { selected = product } label: {
            HStack(spacing: 12) {
                Image(systemName: isSel ? "largecircle.fill.circle" : "circle")
                    .font(.title3).foregroundStyle(isSel ? Theme.lime : Theme.muted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(planTitle(product)).font(.headline).foregroundStyle(Theme.ink)
                    if let sub = planSubtitle(product) {
                        Text(sub).font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                Spacer()
                Text(product.displayPrice).font(.headline).foregroundStyle(Theme.ink)
            }
            .padding(16)
            .background(Theme.surface.opacity(isSel ? 0.8 : 0.4), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isSel ? Theme.lime : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private func planTitle(_ product: Product) -> LocalizedStringKey {
        if product.id.contains("monthly") { return "월 구독" }
        if product.id.contains("yearly") { return "연 구독" }
        return "평생 이용"
    }

    private func planSubtitle(_ product: Product) -> LocalizedStringKey? {
        if product.id.contains("yearly") { return "가장 인기 · 월 구독보다 저렴" }
        if product.id.contains("lifetime") { return "한 번 결제로 평생" }
        return nil
    }

    private var purchaseButton: some View {
        Button {
            guard let product = selected else { return }
            working = true
            Task { _ = await pro.purchase(product); working = false; if pro.isPro { dismiss() } }
        } label: {
            Group {
                if working { ProgressView().tint(.black) }
                else {
                    let key: LocalizedStringKey = selected?.id.contains("lifetime") == true ? "구매하기" : "구독 시작하기"
                    Text(key)
                }
            }
            .font(.headline).foregroundStyle(.black)
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(Theme.lime, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(selected == nil || working)
        .opacity(selected == nil ? 0.5 : 1)
    }

    private var restoreButton: some View {
        Button("구매 복원") { Task { await pro.restore(); if pro.isPro { dismiss() } } }
            .font(.subheadline).foregroundStyle(Theme.muted)
    }

    private var legalLinks: some View {
        HStack(spacing: 8) {
            Button("이용약관") { legalDoc = .terms }
            Text("·").foregroundStyle(Theme.muted.opacity(0.6))
            Button("개인정보처리방침") { legalDoc = .privacy }
        }
        .font(.caption2.weight(.medium)).foregroundStyle(Theme.muted)
        .sheet(item: $legalDoc) { doc in LegalView(doc: doc).environment(\.locale, locale) }
    }

    private var footnote: some View {
        Text("구독은 기간이 끝나기 전 취소하지 않으면 자동 갱신됩니다. 언제든 설정 > Apple ID에서 관리할 수 있어요.")
            .font(.caption2).foregroundStyle(Theme.muted.opacity(0.7))
            .multilineTextAlignment(.center)
    }
}
