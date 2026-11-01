//
//  YearPresenceReportView.swift
//  Day Memory
//

import SwiftData
import SwiftUI

struct YearPresenceReportView: View {
    @Query(sort: \JournalDay.day) private var journalDays: [JournalDay]

    @State private var year: Int = JournalCalendar.civil.component(.year, from: .now)
    @State private var showConfirm = false
    @State private var isGenerating = false

    private struct PreparedExport: Identifiable {
        let id = UUID()
        let url: URL
    }

    @State private var preparedExport: PreparedExport?
    @State private var exportError = false
    @State private var exportErrorMessage = ""

    private var calendar: Calendar { JournalCalendar.civil }

    private var report: YearPresenceReport {
        YearPresenceReportBuilder.build(year: year, journalDays: journalDays, calendar: calendar)
    }

    var body: some View {
        Form {
            Section {
                Picker("Year", selection: $year) {
                    ForEach(yearChoices, id: \.self) { y in
                        Text(String(y)).tag(y)
                    }
                }
            } footer: {
                Text("The report covers every calendar day in the selected year using your journal timezone.")
            }

            Section("Preview") {
                LabeledContent("Days logged") {
                    Text("\(report.loggedDays)")
                        .monospacedDigit()
                }
                LabeledContent("Days not logged") {
                    Text("\(report.unloggedDays)")
                        .monospacedDigit()
                }
                LabeledContent("Split travel days") {
                    Text("\(report.splitTravelDays)")
                        .monospacedDigit()
                }
            }

            Section {
                Button {
                    showConfirm = true
                } label: {
                    Label("Generate PDF report…", systemImage: "doc.richtext")
                }
                .disabled(isGenerating)
            } footer: {
                Text(
                    "Creates a PDF with a day-by-day table for each month: location, working status, leave tags, and any travel details you logged. Days in two countries show both locations."
                )
            }
        }
        .padReadableColumn()
        .navigationTitle("Year report")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Generate report for \(year)?",
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button("Generate PDF") {
                Task { await generatePDF() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "A PDF will be created for all \(report.loggedDays + report.unloggedDays) days in \(year), including \(report.unloggedDays) days without journal entries."
            )
        }
        .sheet(item: $preparedExport) { prepared in
            ShareSheet(activityItems: [prepared.url])
        }
        .alert("Report failed", isPresented: $exportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage)
        }
    }

    private var yearChoices: [Int] {
        let current = calendar.component(.year, from: .now)
        return Array((current - 10)...(current + 1))
    }

    @MainActor
    private func generatePDF() async {
        isGenerating = true
        defer { isGenerating = false }
        do {
            let built = YearPresenceReportBuilder.build(year: year, journalDays: journalDays, calendar: calendar)
            let data = try YearPresencePDFRenderer.render(built)
            let url = try YearPresencePDFRenderer.exportFileURL(year: year)
            try data.write(to: url, options: .atomic)
            preparedExport = PreparedExport(url: url)
        } catch {
            exportErrorMessage = error.localizedDescription
            exportError = true
        }
    }
}

#Preview {
    NavigationStack {
        YearPresenceReportView()
    }
    .modelContainer(
        for: [EmployerPeriod.self, JournalDay.self, PresenceSegment.self, Trip.self, TripTicketImage.self],
        inMemory: true
    )
}
