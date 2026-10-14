import SwiftUI

/// Renders the weekly report as a one-page PDF, on the device.
enum ReportPDF {
    static func render(_ report: WeeklyReport, progress: ProgressData, patientName: String = "") -> URL? {
        let url = URL.temporaryDirectory.appending(path: String(localized: "Bilan Rebond.pdf"))
        let renderer = ImageRenderer(content: ReportPage(report: report, progress: progress, patientName: patientName))
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
    let progress: ProgressData
    var patientName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bilan hebdomadaire Rebond")
                    .font(.title.bold())
                if !patientName.isEmpty {
                    Text(patientName)
                        .font(.title3)
                }
                Text("Du \(report.start, format: .dateTime.day().month(.wide)) au \(report.end, format: .dateTime.day().month(.wide).year())")
                    .foregroundStyle(.secondary)
            }
            ReportSummary(report: report)
            HStack(alignment: .top, spacing: 16) {
                if !progress.amplitude.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Amplitude (% de l'objectif)").font(.caption.bold())
                        AmplitudeChart(data: progress).frame(height: 150)
                    }
                }
                if !progress.pain.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Douleur après chaque séance (sur 10)").font(.caption.bold())
                        PainChart(data: progress).frame(height: 150)
                    }
                }
            }
            Spacer(minLength: 0)
            Text("L'amplitude est mesurée par la caméra de l'iPhone, à titre indicatif : 100 % correspond à l'objectif de mouvement fixé dans l'app. Rebond est un outil de suivi : il ne pose pas de diagnostic et ne remplace pas l'avis d'un professionnel de santé.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(36)
        .frame(width: Self.width, height: Self.height, alignment: .topLeading)
        .background(.white)
        .environment(\.colorScheme, .light)
    }
}

/// Report content, shared by the screen and the PDF.
struct ReportSummary: View {
    let report: WeeklyReport

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Séances : \(report.sessionsDone) sur \(report.sessionsPlanned) prévues")
                .font(.headline)

            ForEach(report.exercises) { line in
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.name).font(.headline)
                    if line.isHeld {
                        Text("Maintien : \(line.heldSeconds) s sur \(line.plannedSeconds) s prévues")
                    } else {
                        Text("\(line.completedReps) répétitions sur \(line.plannedReps) prévues")
                        if line.incompleteReps > 0 {
                            Text("\(line.incompleteReps) répétitions incomplètes (amplitude insuffisante)")
                        }
                    }
                    if let first = line.firstAmplitude {
                        if let last = line.lastAmplitude {
                            Text("Amplitude : \(Int(first.rounded())) % → \(Int(last.rounded())) % de l'objectif")
                        } else {
                            Text("Amplitude : \(Int(first.rounded())) % de l'objectif")
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
                        Label("Douleur forte (≥ \(WeeklyReport.highPain)) le \(date, format: .dateTime.weekday(.wide).day().month())", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            } else {
                Text("Aucune séance ces 7 derniers jours.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
