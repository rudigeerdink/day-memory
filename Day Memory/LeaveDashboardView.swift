//
//  LeaveDashboardView.swift
//  Day Memory
//

import SwiftData
import SwiftUI

struct LeaveDashboardView: View {
    @Query(sort: \EmployerPeriod.startDate) private var employerPeriods: [EmployerPeriod]
    @Query(sort: \JournalDay.day) private var journalDays: [JournalDay]

    @State private var year: Int = Calendar.autoupdatingCurrent.component(.year, from: .now)

    private var calendar: Calendar { .autoupdatingCurrent }
    private let awardedColor = Color(red: 0.67, green: 0.83, blue: 0.98)
    private let consumedColor = Color(red: 0.07, green: 0.24, blue: 0.50)
    private let cardBackground = Color(.secondarySystemGroupedBackground)

    private var report: LeaveYearReport {
        LeaveDashboardAggregator.report(
            year: year,
            employerPeriods: employerPeriods,
            journalDays: journalDays,
            calendar: calendar
        )
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

                        Spacer(minLength: 0)
                    }

                    if report.employerCards.isEmpty {
                        ContentUnavailableView(
                            "No employer periods",
                            systemImage: "building.2",
                            description: Text("Add employer periods and annual leave entitlement in Employers.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        ForEach(report.employerCards) { card in
                            employerLeaveCard(card)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationTitle("Leave")
            .background(Color(.systemGroupedBackground))
        }
    }

    private var yearChoices: [Int] {
        let current = calendar.component(.year, from: .now)
        return Array((current - 5)...(current + 1))
    }

    private func employerLeaveCard(_ card: LeaveEmployerCard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(CountryDisplay.name(for: card.employerCountryCode)) (\(card.employerCountryCode))")
                .font(.headline)
            Text("\(card.companyName) · \(card.clippedRangeStart, format: .dateTime.day().month(.abbreviated))–\(card.clippedRangeEnd, format: .dateTime.day().month(.abbreviated).year())")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 26) {
                metricBlock("Awarded (pro-rated)", value: Int(card.proratedAwardedDays.rounded()), tint: awardedColor)
                metricBlock("Consumed (annual leave)", value: card.consumedDays, tint: consumedColor)
                metricBlock("Delta", value: Int((card.proratedAwardedDays - Double(card.consumedDays)).rounded()), tint: card.proratedAwardedDays >= Double(card.consumedDays) ? .green : .red)
            }
            .frame(maxWidth: .infinity)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                ForEach(card.months, id: \.monthStart) { month in
                    HStack {
                        Text(month.monthStart, format: .dateTime.month(.abbreviated))
                            .font(.subheadline)
                            .frame(width: 44, alignment: .leading)
                        Spacer()
                        rowPill(text: "Awarded \(Int(month.proratedAwardedDays.rounded()))", fill: awardedColor.opacity(0.18))
                        rowPill(text: "Consumed \(month.consumedDays)", fill: consumedColor.opacity(0.16))
                    }
                }
            }
        }
        .padding(16)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func metricBlock(_ title: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 6) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                    .padding(.top, 3)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(height: 30, alignment: .topLeading)
            Text("\(value)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rowPill(text: String, fill: Color) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(fill, in: Capsule())
    }
}

struct LeaveMonthBreakdown: Hashable, Sendable {
    var monthStart: Date
    var proratedAwardedDays: Double
    var consumedDays: Int
}

struct LeaveEmployerCard: Identifiable, Hashable, Sendable {
    var id: UUID
    var companyName: String
    var employerCountryCode: String
    var clippedRangeStart: Date
    var clippedRangeEnd: Date
    var proratedAwardedDays: Double
    var consumedDays: Int
    var months: [LeaveMonthBreakdown]
}

struct LeaveYearReport: Hashable, Sendable {
    var year: Int
    var employerCards: [LeaveEmployerCard]
}

enum LeaveDashboardAggregator {
    static func report(
        year: Int,
        employerPeriods: [EmployerPeriod],
        journalDays: [JournalDay],
        calendar: Calendar
    ) -> LeaveYearReport {
        guard let (yearStart, yearEnd) = YearOverviewAggregator.yearBounds(year: year, calendar: calendar) else {
            return LeaveYearReport(year: year, employerCards: [])
        }

        let annualLeaveDays: Set<Date> = Set(
            journalDays
                .filter { $0.nonWorkingReason == .annualLeave }
                .map { ModelValidation.startOfDay($0.day, calendar: calendar) }
        )

        let cards = employerPeriods.compactMap { period -> LeaveEmployerCard? in
            let (periodStart, periodEnd) = period.normalizedRange(in: calendar)
            let clipStart = max(periodStart, yearStart)
            let clipEnd = min(periodEnd, yearEnd)
            guard clipStart <= clipEnd else { return nil }

            let monthBreakdowns = monthlyBreakdowns(
                clipStart: clipStart,
                clipEnd: clipEnd,
                annualEntitlement: period.annualLeaveEntitlementDays,
                annualLeaveDays: annualLeaveDays,
                calendar: calendar
            )

            let awarded = monthBreakdowns.reduce(0.0) { $0 + $1.proratedAwardedDays }
            let consumed = monthBreakdowns.reduce(0) { $0 + $1.consumedDays }

            return LeaveEmployerCard(
                id: period.id,
                companyName: period.companyName,
                employerCountryCode: period.employerCountryCode,
                clippedRangeStart: clipStart,
                clippedRangeEnd: clipEnd,
                proratedAwardedDays: awarded,
                consumedDays: consumed,
                months: monthBreakdowns
            )
        }
        .sorted { $0.clippedRangeStart < $1.clippedRangeStart }

        return LeaveYearReport(year: year, employerCards: cards)
    }

    private static func monthlyBreakdowns(
        clipStart: Date,
        clipEnd: Date,
        annualEntitlement: Int,
        annualLeaveDays: Set<Date>,
        calendar: Calendar
    ) -> [LeaveMonthBreakdown] {
        let monthlyEntitlement = Double(annualEntitlement) / 12.0
        var rows: [LeaveMonthBreakdown] = []

        var cursor = startOfMonth(for: clipStart, calendar: calendar)
        let endMonth = startOfMonth(for: clipEnd, calendar: calendar)

        while cursor <= endMonth {
            guard let monthInterval = calendar.dateInterval(of: .month, for: cursor) else { break }
            let monthStart = ModelValidation.startOfDay(monthInterval.start, calendar: calendar)
            guard let monthEndRaw = calendar.date(byAdding: .day, value: -1, to: monthInterval.end) else { break }
            let monthEnd = ModelValidation.startOfDay(monthEndRaw, calendar: calendar)

            let overlapStart = max(monthStart, clipStart)
            let overlapEnd = min(monthEnd, clipEnd)

            var prorated = 0.0
            var consumed = 0

            if overlapStart <= overlapEnd,
               let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count
            {
                let coveredDays = inclusiveDayCount(start: overlapStart, end: overlapEnd, calendar: calendar)
                let ratio = Double(coveredDays) / Double(daysInMonth)
                prorated = monthlyEntitlement * ratio

                var d = overlapStart
                while d <= overlapEnd {
                    if annualLeaveDays.contains(d) { consumed += 1 }
                    guard let next = calendar.date(byAdding: .day, value: 1, to: d) else { break }
                    d = ModelValidation.startOfDay(next, calendar: calendar)
                }
            }

            rows.append(
                LeaveMonthBreakdown(
                    monthStart: monthStart,
                    proratedAwardedDays: prorated,
                    consumedDays: consumed
                )
            )

            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = startOfMonth(for: nextMonth, calendar: calendar)
        }

        return rows
    }

    private static func startOfMonth(for date: Date, calendar: Calendar) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: comps).map { ModelValidation.startOfDay($0, calendar: calendar) } ?? date
    }

    private static func inclusiveDayCount(start: Date, end: Date, calendar: Calendar) -> Int {
        let s = ModelValidation.startOfDay(start, calendar: calendar)
        let e = ModelValidation.startOfDay(end, calendar: calendar)
        let days = calendar.dateComponents([.day], from: s, to: e).day ?? 0
        return max(0, days + 1)
    }
}

#Preview {
    LeaveDashboardView()
        .modelContainer(
            for: [EmployerPeriod.self, JournalDay.self, PresenceSegment.self, Trip.self, TripTicketImage.self],
            inMemory: true
        )
}
