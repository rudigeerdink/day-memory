//
//  YearOverviewView.swift
//  Day Memory
//

import SwiftData
import SwiftUI

struct YearOverviewView: View {
    @Query(sort: \JournalDay.day) private var journalDays: [JournalDay]
    @Query(sort: \EmployerPeriod.startDate) private var employerPeriods: [EmployerPeriod]

    @State private var year: Int = JournalCalendar.civil.component(.year, from: .now)
    @State private var countScope: YearCountScope = .throughToday

    private var calendar: Calendar { JournalCalendar.civil }
    private let workingColor = Color(red: 0.07, green: 0.24, blue: 0.50)
    private let nonWorkingColor = Color(red: 0.67, green: 0.83, blue: 0.98)
    private let cardBackground = Color(.secondarySystemGroupedBackground)

    private var report: YearOverviewReport {
        YearOverviewAggregator.report(
            year: year,
            journalDays: journalDays,
            employerPeriods: employerPeriods,
            calendar: calendar
        )
    }

    private var showsFutureEntriesHint: Bool {
        guard countScope == .fullYear, year == calendar.component(.year, from: .now) else { return false }
        return report.yearTotalsByCountry.contains { $0.presenceUnits > $0.presenceUnitsThroughToday }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Menu {
                            Picker("Year", selection: $year) {
                                ForEach(yearChoices, id: \.self) { y in
                                    Text(String(y)).tag(y)
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "calendar")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(String(year))
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .monospacedDigit()
                                Image(systemName: "chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(.systemBackground))
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            }
                        }
                        .contentShape(Rectangle())

                        Spacer(minLength: 0)
                    }

                    Picker("Count scope", selection: $countScope) {
                        ForEach(YearCountScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)

                    scopeCaption

                    if showsFutureEntriesHint {
                        Text("Includes journal entries on future dates in \(String(year)).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if report.yearTotalsByCountry.isEmpty {
                        ContentUnavailableView(
                            "No journal entries",
                            systemImage: "tray",
                            description: Text("Log days in Journal to see totals for \(String(year)).")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }

                    sectionTitle("By employer country")
                    if report.employerSlices.isEmpty {
                        ContentUnavailableView(
                            "No employer periods",
                            systemImage: "building.2",
                            description: Text("Add periods under Employers. Only periods overlapping \(String(year)) are shown.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    } else {
                        ForEach(report.employerSlices) { slice in
                            employerCard(slice)
                        }
                    }

                    if !report.yearTotalsByCountry.isEmpty {
                        sectionTitle("By presence location")
                        ForEach(report.yearTotalsByCountry, id: \.self) { row in
                            locationCard(row)
                        }
                    }

                    let unlogged = unloggedCount(for: countScope)
                    if unlogged > 0 {
                        unloggedDaysRow(count: unlogged)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationTitle("Work view")
            .background(Color(.systemGroupedBackground))
            .onAppear {
                countScope = YearCountScope.defaultForYear(year, calendar: calendar)
            }
            .onChange(of: year) { _, newYear in
                countScope = YearCountScope.defaultForYear(newYear, calendar: calendar)
            }
        }
    }

    private var yearChoices: [Int] {
        let current = calendar.component(.year, from: .now)
        return Array((current - 5)...(current + 1))
    }

    private var scopeCaption: some View {
        Group {
            switch countScope {
            case .throughToday:
                if let end = report.throughTodayEnd {
                    Text(
                        "Presence days through \(end, format: .dateTime.day().month(.abbreviated).day().year()) in your journal calendar."
                    )
                } else {
                    Text("No days in \(String(year)) on or before today yet.")
                }
            case .fullYear:
                Text("All journal entries in \(String(year)), including dates after today.")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func unloggedCount(for scope: YearCountScope) -> Int {
        switch scope {
        case .throughToday:
            return report.unloggedCalendarDaysInYearThroughToday
        case .fullYear:
            return report.unloggedCalendarDaysInYear
        }
    }

    private func locationCard(_ row: YearLocationStat) -> some View {
        let c = row.counts(for: countScope)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                countryCodeBadge(row.countryCode)
                Text(CountryDisplay.name(for: row.countryCode))
                    .font(.title3.weight(.semibold))
            }
            ringWithMetrics(
                total: c.presence,
                working: c.working,
                nonWorking: c.nonWorking,
                ringSize: 98,
                lineWidth: 10
            )
        }
        .padding(16)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func employerCard(_ slice: YearEmployerSlice) -> some View {
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                countryCodeBadge(slice.employerCountryCode)
                Text(CountryDisplay.name(for: slice.employerCountryCode))
                    .font(.headline)
            }
            Text(
                "\(slice.companyName) · \(slice.clippedRangeStart, format: .dateTime.day().month(.abbreviated))–\(slice.clippedRangeEnd, format: .dateTime.day().month(.abbreviated).year())"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if !slice.byPresenceCountry.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(slice.byPresenceCountry, id: \.self) { row in
                        employerCountryBreakdownRow(row)
                    }
                }
            }
        }
        .padding(16)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .padding(.top, 2)
    }

    private func ringWithMetrics(
        total: Int,
        working: Int,
        nonWorking: Int,
        ringSize: CGFloat,
        lineWidth: CGFloat,
        contentSpacing: CGFloat = 30
    ) -> some View {
        HStack(alignment: .center, spacing: contentSpacing) {
            PresenceRing(
                working: working,
                nonWorking: nonWorking,
                workingColor: workingColor,
                nonWorkingColor: nonWorkingColor,
                size: ringSize,
                lineWidth: lineWidth
            )
            .overlay {
                VStack(spacing: 0) {
                    Text("\(total)")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    Text("days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 20) {
                legendMetric(title: "Working", value: working, total: max(total, 1), color: workingColor)
                legendMetric(title: "Non-working", value: nonWorking, total: max(total, 1), color: nonWorkingColor)
            }
            Spacer(minLength: 0)
        }
    }

    private func legendMetric(title: String, value: Int, total: Int, color: Color) -> some View {
        let safeTotal = max(total, 1)
        let percent = Int((Double(value) / Double(safeTotal) * 100).rounded())

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(value)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text("\(percent)%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func unloggedDaysRow(count: Int) -> some View {
        HStack {
            Label("Days without an entry", systemImage: "calendar.badge.exclamationmark")
                .font(.subheadline)
            Spacer()
            Text("\(count)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .padding(14)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func employerCountryBreakdownRow(_ row: YearLocationStat) -> some View {
        let c = row.counts(for: countScope)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                countryCodeBadge(row.countryCode)
                Text(CountryDisplay.name(for: row.countryCode))
                    .font(.subheadline.weight(.medium))
            }
            ringWithMetrics(
                total: c.presence,
                working: c.working,
                nonWorking: c.nonWorking,
                ringSize: 98,
                lineWidth: 10
            )
        }
    }

    private func countryCodeBadge(_ code: String) -> some View {
        Text(code)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(workingColor)
            .frame(width: 34, height: 34)
            .background(workingColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct PresenceRing: View {
    var working: Int
    var nonWorking: Int
    var workingColor: Color
    var nonWorkingColor: Color
    var size: CGFloat
    var lineWidth: CGFloat

    private var total: Double { Double(max(working + nonWorking, 1)) }
    private var workingFraction: Double { Double(working) / total }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)

            if working > 0 {
                Circle()
                    .trim(from: 0, to: workingFraction)
                    .stroke(
                        workingColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }

            if nonWorking > 0 {
                Circle()
                    .trim(from: workingFraction, to: 1)
                    .stroke(
                        nonWorkingColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    YearOverviewView()
        .modelContainer(
            for: [EmployerPeriod.self, JournalDay.self, PresenceSegment.self, Trip.self, TripTicketImage.self],
            inMemory: true
        )
}
