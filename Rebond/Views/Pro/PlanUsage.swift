import SwiftUI

/// The physiotherapist's offer and its use: "Offre gratuite · 2 / 3 patients", "Rebond Pro 10 · 4 / 10 patients",
/// "Rebond Cabinet · patients illimités".
struct PlanUsage: View {
    /// Real patients followed (demo patients aside).
    let followed: Int
    @Environment(ProStore.self) private var store

    var body: some View {
        let name = store.plan.map { Text($0.name) } ?? Text("Offre gratuite")
        if let limit = store.patientLimit {
            Text("\(name) · \(min(followed, limit)) / \(limit) patients")
        } else {
            Text("\(name) · patients illimités")
        }
    }
}
