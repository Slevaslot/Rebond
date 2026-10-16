import Foundation
import Observation
import StoreKit

/// Rebond Pro: the physiotherapist's subscription, priced by the number of patients followed (`ProPlan`).
/// The free offer has everything that works on the iPhone, for up to `ProPlan.freePatientLimit` patients.
/// No server either way. Patients never pay: their app is entirely free.
@Observable
final class ProStore {
    /// The active plan, the highest if several; nil with the free offer.
    private(set) var plan: ProPlan?

    var isSubscribed: Bool { plan != nil }

    /// Test builds only (`BuildChannel.showsDemoTools`): unlocks Pro without a purchase, to show the physiotherapist
    /// space during the demo and to the jury.
    var demoUnlocked = UserDefaults.standard.bool(forKey: "demoProUnlocked") {
        didSet {
            UserDefaults.standard.set(demoUnlocked, forKey: "demoProUnlocked")
        }
    }

    /// Patients that can be followed now; nil for unlimited. The demo switch unlocks everything.
    var patientLimit: Int? {
        if BuildChannel.showsDemoTools, demoUnlocked { return nil }
        return ProPlan.patientLimit(for: plan)
    }

    /// Unlimited patients: nothing more to buy.
    var isUnlimited: Bool { patientLimit == nil }

    @ObservationIgnored private var updates: Task<Void, Never>?

    init() {
        updates = Task { [weak self] in
            for await _ in Transaction.updates {
                await self?.refresh()
            }
        }
    }

    /// Reads the current entitlements: a purchase, a renewal, an upgrade, or an offer code.
    func refresh() async {
        var active: [String] = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               ProPlan(productID: transaction.productID) != nil,
               transaction.revocationDate == nil {
                active.append(transaction.productID)
                await transaction.finish()
            }
        }
        plan = ProPlan.best(of: active)
    }
}
