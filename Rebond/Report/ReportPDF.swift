import SwiftUI

/// Renders the weekly report as a one-page PDF, on the device.
enum ReportPDF {
    static func render(_ report: WeeklyReport) -> URL? {
        let url = URL.temporaryDirectory.appending(path: String(localized: "Rapport Rebond.pdf"))
        let renderer = ImageRenderer(content: ReportPage(report: report))
        var page = CGRect(x: 0, y: 0, width: ReportPage.width, height: ReportPage.height)
        guard let context = CGContext(url as CFURL, mediaBox: &page, nil) else { return nil }
        renderer.render { _, draw in
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }
}

/// The printed page: A4, in points.
struct ReportPage: View {
    static let width = 595.0
    static let height = 842.0

    let report: WeeklyReport

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Rapport hebdomadaire Rebond")
                    .font(.title.bold())
                Text("Du \(report.start, format: .dateTime.day().month()) au \(report.end, format: .dateTime.day().month().year())")
                    .foregroundStyle(.secondary)
            }
            ReportSummary(report: report)
            Spacer()
            Text("Rapport généré par Rebond sur l'iPhone du patient. Rebond ne remplace pas l'avis d'un professionnel de santé.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(width: Self.width, height: Self.height, alignment: .topLeading)
        .background(.white)
        .environment(\.colorScheme, .light)
    }
}

/// Report content, shared by the screen and the PDF.
struct ReportSummary: View {
    let report: WeeklyReport

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Séances : \(report.sessionsDone) sur \(report.sessionsPlanned) prévues")
                .font(.headline)

            ForEach(report.exercises) { line in
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.name).font(.headline)
                    Text("\(line.completedReps) répétitions sur \(line.plannedReps) prévues")
                    if line.incompleteReps > 0 {
                        Text("\(line.incompleteReps) répétitions incomplètes")
                    }
                    if let first = line.firstAmplitude {
                        if let last = line.lastAmplitude {
                            Text("Amplitude : \(Int(first)) % → \(Int(last)) % de la profondeur visée")
                        } else {
                            Text("Amplitude : \(Int(first)) % de la profondeur visée")
                        }
                    }
                }
            }

            if let average = report.averagePain {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Douleur").font(.headline)
                    Text("Moyenne : \(average, format: .number.precision(.fractionLength(1))) sur 10")
                    if let first = report.firstPain, let last = report.lastPain {
                        Text("Évolution : \(first) → \(last)")
                    }
                    ForEach(report.painfulSessionDates, id: \.self) { date in
                        Text("⚠︎ Douleur forte le \(date, format: .dateTime.weekday(.wide).day().month())")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }
}
