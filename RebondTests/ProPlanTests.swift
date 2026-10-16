import Testing
@testable import Rebond

@Suite("Offres kiné")
struct ProPlanTests {
    @Test func limitsByPlan() {
        #expect(ProPlan.patientLimit(for: nil) == 3)
        #expect(ProPlan.patientLimit(for: .pro10) == 10)
        #expect(ProPlan.patientLimit(for: .pro30) == 30)
        #expect(ProPlan.patientLimit(for: .practice) == nil)
    }

    @Test func productsMapToTheirPlanMonthlyOrYearly() {
        for plan in ProPlan.allCases {
            #expect(ProPlan(productID: plan.productID(.monthly)) == plan)
            #expect(ProPlan(productID: plan.productID(.yearly)) == plan)
        }
        #expect(ProPlan(productID: "rebond.pro.monthly") == nil)
        #expect(Set(ProPlan.allProductIDs).count == 6)
    }

    @Test func theHighestActivePlanWins() {
        // An upgrade from Pro 10 to Cabinet: both may show up for a moment.
        #expect(ProPlan.best(of: ["rebond.pro10.monthly", "rebond.cabinet.yearly"]) == .practice)
        #expect(ProPlan.best(of: ["other.product"]) == nil)
        #expect(ProPlan.best(of: [String]()) == nil)
    }

    @Test func roomForOneMorePatient() {
        #expect(ProPlan.canAddPatient(count: 2, plan: nil))
        #expect(!ProPlan.canAddPatient(count: 3, plan: nil))
        #expect(ProPlan.canAddPatient(count: 9, plan: .pro10))
        #expect(!ProPlan.canAddPatient(count: 10, plan: .pro10))
        #expect(ProPlan.canAddPatient(count: 500, plan: .practice))
    }

    @Test func suggestsTheSmallestPlanThatFits() {
        #expect(ProPlan.suggested(forPatients: 3) == .pro10)
        #expect(ProPlan.suggested(forPatients: 9) == .pro10)
        #expect(ProPlan.suggested(forPatients: 10) == .pro30)
        #expect(ProPlan.suggested(forPatients: 30) == .practice)
    }
}
