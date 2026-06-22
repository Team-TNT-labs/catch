import Foundation
import StoreKit

/// StoreKit 2 래퍼: Catch Pro 상품 로드 + 권한(isPro) 추적 + 구매/복원.
/// Pro 잠금 해제: 사진앨범 불러오기, 폴더 무제한(무료 7개), 백업.
@MainActor
final class ProStore: ObservableObject {
    // App Store Connect 상품: 연간 구독 + 평생(비소모성).
    static let yearlyID = "com.tntlabs.catch.pro.yearly"
    static let lifetimeID = "com.tntlabs.catch.pro.lifetime"
    static let productIDs = [yearlyID, lifetimeID]
    static let freeFolderLimit = 7

    @Published private(set) var products: [Product] = []   // [연간, 평생] 순
    @Published private(set) var isPro = false
    @Published private(set) var loading = true
    @Published var purchasing = false

    var yearly: Product? { products.first { $0.id == Self.yearlyID } }
    var lifetime: Product? { products.first { $0.id == Self.lifetimeID } }

    private var updates: Task<Void, Never>?

    init() {
        updates = listenForTransactions()
        Task {
            await loadProducts()
            await refreshEntitlement()
            loading = false
        }
    }

    deinit { updates?.cancel() }

    func loadProducts() async {
        let fetched = (try? await Product.products(for: Self.productIDs)) ?? []
        products = fetched.sorted { (Self.productIDs.firstIndex(of: $0.id) ?? 0) < (Self.productIDs.firstIndex(of: $1.id) ?? 0) }
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        purchasing = true
        defer { purchasing = false }
        do {
            let result = try await product.purchase()
            if case .success(let verification) = result, case .verified(let t) = verification {
                await t.finish()
                await refreshEntitlement()
            }
        } catch { }
        return isPro
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }

    func refreshEntitlement() async {
        var pro = UserDefaults.standard.bool(forKey: Self.devKey)
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, Self.productIDs.contains(t.productID), t.revocationDate == nil {
                pro = true
            }
        }
        isPro = pro
    }

    // MARK: 개발자 테스트 토글(상품 등록 전 잠금 해제용 — 개발자소개 사진 5회 탭)
    private static let devKey = "catch.devProUnlock"
    var devUnlocked: Bool { UserDefaults.standard.bool(forKey: Self.devKey) }
    @discardableResult
    func toggleDevPro() -> Bool {
        let new = !devUnlocked
        UserDefaults.standard.set(new, forKey: Self.devKey)
        Task { await refreshEntitlement() }
        return new
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let t) = update {
                    await t.finish()
                    await self?.refreshEntitlement()
                }
            }
        }
    }
}
