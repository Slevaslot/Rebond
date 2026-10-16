import Foundation

/// The physiotherapist's offers, priced by volume: the more patients followed, the higher the plan. All the plans
/// are levels of one App Store subscription group ("Rebond Pro"): moving up or down is a system upgrade or
/// downgrade, prorated by the App Store. Pure logic, tested.
nonisolated enum ProPlan: Int, CaseIterable, Comparable, Sendable {
    /// Up to 10 patients.
    case pro10 = 1
    /// Up to 30 patients.
    case pro30
    /// Unlimited: a practice with several physiotherapists, or many patients.
    case practice

    /// Patients followed with no subscription.
    static let freePatientLimit = 3

    static func < (lhs: ProPlan, rhs: ProPlan) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Patients this plan follows; nil for unlimited.
    var patientLimit: Int? {
        switch self {
        case .pro10: 10
        case .pro30: 30
        case .practice: nil
        }
    }

    var name: LocalizedStringResource {
        switch self {
        case .pro10: "Rebond Pro 10"
        case .pro30: "Rebond Pro 30"
        case .practice: "Rebond Cabinet"
        }
    }

    enum Period: CaseIterable, Sendable {
        case monthly, yearly
    }

    /// App Store product identifiers, created in App Store Connect in the "Rebond Pro" group.
    func productID(_ period: Period) -> String {
        let plan = switch self {
        case .pro10: "pro10"
        case .pro30: "pro30"
        case .practice: "cabinet"
        }
        return "rebond.\(plan).\(period == .monthly ? "monthly" : "yearly")"
    }

    static var allProductIDs: [String] {
        allCases.flatMap { plan in Period.allCases.map(plan.productID) }
    }

    static func productIDs(_ period: Period) -> [String] {
        allCases.map { $0.productID(period) }
    }

    /// The plan a product unlocks, monthly or yearly alike.
    init?(productID: String) {
        guard let plan = Self.allCases.first(where: { plan in Period.allCases.contains { plan.productID($0) == productID } })
        else { return nil }
        self = plan
    }

    /// The highest plan among active subscriptions (a leftover lower one while an upgrade settles doesn't count).
    static func best(of productIDs: some Sequence<String>) -> ProPlan? {
        productIDs.compactMap(ProPlan.init(productID:)).max()
    }

    /// Patients followed with this plan, or with no plan at all; nil for unlimited.
    static func patientLimit(for plan: ProPlan?) -> Int? {
        plan.map(\.patientLimit) ?? freePatientLimit
    }

    /// Whether one more patient can be followed, with `count` already followed (demo patients aside).
    static func canAddPatient(count: Int, plan: ProPlan?) -> Bool {
        patientLimit(for: plan).map { count < $0 } ?? true
    }

    /// The smallest plan with room for one more patient than `count`: the one to suggest.
    static func suggested(forPatients count: Int) -> ProPlan {
        allCases.first { $0.patientLimit.map { count < $0 } ?? true } ?? .practice
    }
}
