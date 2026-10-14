import Foundation
import Observation
import StoreKit

/// Rebond Pro: the physiotherapist's subscription. The free offer has everything that works on the iPhone,
/// for up to `freePatientLimit` patients; Pro follows as many patients as needed (and, later, the connected
/// version with a server). Patients never pay: their app is entirely free.
@Observable
final class ProStore {
    /// Products created in App Store Connect, in the "Rebond Pro" subscription group.
    static let productIDs = ["rebond.pro.monthly", "rebond.pro.yearly"]
    /// Patients followed with the free offer.
    nonisolated static let freePatientLimit = 3

    private(set) var isSubscribed = false

    #if DEBUG
    /// Development builds only: unlocks Pro without a purchase, to show the physiotherapist space during the demo.
    var demoUnlocked = UserDefaults.standard.bool(forKey: "demoProUnlocked") {
        didSet {
            UserDefaults.standard.set(demoUnlocked, forKey: "demoProUnlocked")
        }
    }
    #endif

    var hasPro: Bool {
        #if DEBUG
        isSubscribed || demoUnlocked
        #else
        isSubscribed
        #endif
    }

    @ObservationIgnored private var updates: Task<Void, Never>?

    init() {
        updates = Task { [weak self] in
            for await _ in Transaction.updates {
                await self?.refresh()
            }
        }
    }

    /// Reads the current entitlements: a purchase, a renewal, or an offer code.
    func refresh() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               Self.productIDs.contains(transaction.productID),
               transaction.revocationDate == nil {
                active = true
                await transaction.finish()
            }
        }
        isSubscribed = active
    }
}
