import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject private var pro: ProStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Product?

    private let perks: [(String, String)] = [
        ("photo.on.rectangle", "사진앨범에서 불러오기"),
        ("folder.fill.badge.plus", "폴더 무제한 (무료 7개까지)"),
        ("icloud.and.arrow.up.fill", "수집 백업 & 복원"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    VStack(spacing: 14) {
                        ForEach(perks, id: \.0) { perk($0.0, $0.1) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    planList
                    purchaseButton
                    Button { Task { await pro.restore(); if pro.isPro { dismiss() } } } label: {
                        Text("구매 복원").font(.footnote).foregroundStyle(Theme.muted)
                    }
                }
                .padding(24)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(Theme.muted) }
                }
            }
        }
        .onChange(of: pro.isPro) { _, p in if p { dismiss() } }
        .onChange(of: pro.products.count) { _, _ in if selected == nil { selected = defaultPlan } }
        .onAppear { if selected == nil { selected = defaultPlan } }
    }

    private var defaultPlan: Product? { pro.lifetime ?? pro.products.first }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "crown.fill").font(.system(size: 46)).foregroundStyle(Theme.lime).padding(.top, 12)
            Text("Catch Pro").font(.largeTitle.bold()).foregroundStyle(Theme.ink)
            Text("Catch를 더 자유롭게").font(.subheadline).foregroundStyle(Theme.muted)
        }
    }

    private func perk(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Theme.lime).frame(width: 30)
            Text(text).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
            Spacer()
        }
    }

    // MARK: - Plans

    private var planList: some View {
        VStack(spacing: 10) {
            ForEach(pro.products, id: \.id) { planRow($0) }
        }
    }

    private func planRow(_ product: Product) -> some View {
        let isSel = selected?.id == product.id
        let lifetime = product.id == ProStore.lifetimeID
        return Button { selected = product } label: {
            HStack(spacing: 12) {
                Image(systemName: isSel ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSel ? Theme.lime : Theme.muted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lifetime ? "평생 이용" : "연 구독").font(.headline).foregroundStyle(Theme.ink)
                    Text(lifetime ? "한 번 결제로 평생" : "매년 자동 갱신")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                Text(product.displayPrice).font(.headline.bold()).foregroundStyle(Theme.ink)
            }
            .padding(16)
            .background(Theme.surface.opacity(isSel ? 0.9 : 0.4), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isSel ? Theme.lime : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var purchaseButton: some View {
        Button { if let s = selected { Task { await pro.purchase(s) } } } label: {
            Group {
                if pro.purchasing { ProgressView().tint(.black) }
                else if selected?.id == ProStore.lifetimeID { Text("평생 이용 구매") }
                else { Text("구독 시작하기") }
            }
            .font(.headline).foregroundStyle(.black)
            .frame(maxWidth: .infinity).frame(height: 54)
            .background(Theme.lime, in: Capsule())
        }
        .disabled(pro.purchasing || selected == nil)
    }
}
