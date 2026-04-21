//
//  YearOverviewView.swift
//  Day Memory
//

import SwiftData
import SwiftUI

struct YearOverviewView: View {
    @Query(sort: \JournalDay.day) private var journalDays: [JournalDay]
    @Query(sort: \EmployerPeriod.startDate) private var employerPeriods: [EmployerPeriod]

    @State private var year: Int = Calendar.autoupdatingCurrent.component(.year, from: .now)

    private var calendar: Calendar { .autoupdatingCurrent }

    private var report: YearOverviewReport {
        YearOverviewAggregator.report(
            year: year,
            journalDays: journalDays,
            employerPeriods: employerPeriods,
            calendar: calendar
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Year", selection: $year) {
                        ForEach(yearChoices, id: \.self) { y in
                            Text(String(y)).tag(y)
                        }
                    }
                    .pickerStyle(.menu)

                    Text(
                        "Travel days split across two countries count once toward each country. Numbers are presence units (segments), not calendar days."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
                }

                Section("This year — your locations") {
                    if report.yearTotalsByCountry.isEmpty {
                        ContentUnavailableView(
                            "No journal entries",
                            systemImage: "tray",
                            description: Text("Log days in Journal to see totals for \(String(year)).")
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(report.yearTotalsByCountry, id: \.self) { row in
                            locationStatRow(row)
                        }

                        if report.unloggedCalendarDaysInYear > 0 {
                            LabeledContent("Days without an entry") {
                                Text("\(report.unloggedCalendarDaysInYear)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("By employer period (within \(String(year)))") {
                    if report.employerSlices.isEmpty {
                        ContentUnavailableView(
                            "No employer periods",
                            systemImage: "building.2",
                            description: Text("Add periods under Employers. Only days overlapping \(String(year)) are shown.")
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(report.employerSlices) { slice in
                            DisclosureGroup {
                                if slice.byPresenceCountry.isEmpty {
                                    Text("No journal entries in this slice.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(slice.byPresenceCountry, id: \.self) { row in
                                        locationStatRow(row, indent: true)
                                    }
                                }

                                if slice.unloggedCalendarDays > 0 {
                                    LabeledContent("Days without an entry") {
                                        Text("\(slice.unloggedCalendarDays)")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(slice.companyName)
                                        .font(.headline)
                                    Text(
                                        "Employer: \(CountryDisplay.name(for: slice.employerCountryCode)) (\(slice.employerCountryCode))"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    Text(
                                        "\(slice.clippedRangeStart, format: .dateTime.day().month(.abbreviated))–\(slice.clippedRangeEnd, format: .dateTime.day().month(.abbreviated).year())"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Overview")
        }
    }

    private var yearChoices: [Int] {
        let current = calendar.component(.year, from: .now)
        return Array((current - 5)...(current + 1))
    }

    @ViewBuilder
    private func locationStatRow(_ row: YearLocationStat, indent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(CountryDisplay.name(for: row.countryCode))
                    .font(.body.weight(.medium))
                Spacer()
                Text(row.countryCode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                statPill(title: "Presence", value: row.presenceUnits)
                statPill(title: "Working", value: row.working)
                statPill(title: "Non-working", value: row.nonWorking)
            }
        }
        .padding(.vertical, 4)
        .padding(.leading, indent ? 8 : 0)
    }

    private func statPill(title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    YearOverviewView()
        .modelContainer(
            for: [EmployerPeriod.self, JournalDay.self, PresenceSegment.self, Trip.self, TripTicketImage.self],
            inMemory: true
        )
}
