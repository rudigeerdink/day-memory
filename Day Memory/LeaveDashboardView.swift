//
//  LeaveDashboardView.swift
//  Day Memory
//

import SwiftData
import SwiftUI

struct LeaveDashboardView: View {
    @Query(sort: \EmployerPeriod.startDate) private var employerPeriods: [EmployerPeriod]
    @Query(sort: \JournalDay.day) private var journalDays: [JournalDay]

    @State private var year: Int = JournalCalendar.civil.component(.year, from: .now)
    @State private var countScope: YearCountScope = .throughToday

    private var calendar: Calendar { JournalCalendar.civil }
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

                    Picker("Count scope", selection: $countScope) {
                        ForEach(YearCountScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)

                    scopeCaption

                    if showsFutureEntriesHint {
                        Text("Includes annual leave marked on future dates in \(String(year)).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
            .navigationTitle("Leave view")
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

    private var showsFutureEntriesHint: Bool {
        guard countScope == .fullYear, year == calendar.component(.year, from: .now) else { return false }
        return report.employerCards.contains {
            $0.consumedDays > $0.consumedDaysThroughToday
                || Int($0.proratedAwardedDays.rounded()) > Int($0.proratedAwardedDaysThroughToday.rounded())
        }
    }

    private var scopeCaption: some View {
        Group {
            switch countScope {
            case .throughToday:
                if let end = report.throughTodayEnd {
                    Text(
                        "Leave through \(end, format: .dateTime.day().month(.abbreviated).day().year()) in your journal calendar."
                    )
                } else {
                    Text("No leave days in \(String(year)) on or before today yet.")
                }
            case .fullYear:
                Text("All annual leave in \(String(year)), including dates after today.")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func employerLeaveCard(_ card: LeaveEmployerCard) -> some View {
        let balance = leaveBalance(for: card)
        let awardedInt = leaveAwarded(for: card)
        let consumed = leaveConsumed(for: card)
        let months = leaveMonths(for: card)

        return HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(consumedColor.opacity(0.45))
                .frame(width: 3)
                .padding(.vertical, 14)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "building.2.fill")
                        .font(.title3)
                        .foregroundStyle(consumedColor.opacity(0.9))
                        .frame(width: 26, alignment: .center)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(CountryDisplay.name(for: card.employerCountryCode))
                                .font(.headline)
                            Text(card.employerCountryCode)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(consumedColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(consumedColor.opacity(0.1), in: Capsule())
                        }
                        Text("\(card.companyName) · \(card.clippedRangeStart, format: .dateTime.day().month(.abbreviated))–\(card.clippedRangeEnd, format: .dateTime.day().month(.abbreviated).year())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 6) {
                    Text("Balance")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.6)

                    Text(balanceLabel(balance))
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(balanceTint(balance))

                    Text("days vs pro-rated entitlement")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 0) {
                    compactStat(title: "Awarded", subtitle: "pro-rated", value: awardedInt, accent: awardedColor)
                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 1, height: 36)
                    compactStat(title: "Consumed", subtitle: "annual leave", value: consumed, accent: consumedColor)
                }
                .padding(.vertical, 4)

                Divider()

                Text("By month")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                VStack(spacing: 6) {
                    ForEach(months, id: \.monthStart) { month in
                        monthBreakdownRow(month: month)
                    }
                }
            }
            .padding(16)
        }
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func balanceLabel(_ balance: Int) -> String {
        if balance > 0 { return "+\(balance)" }
        return "\(balance)"
    }

    private func balanceTint(_ balance: Int) -> Color {
        if balance == 0 { return Color.primary }
        return balance > 0 ? Color.green : Color.red
    }

    private func leaveBalance(for card: LeaveEmployerCard) -> Int {
        switch countScope {
        case .throughToday:
            return Int((card.proratedAwardedDaysThroughToday - Double(card.consumedDaysThroughToday)).rounded())
        case .fullYear:
            return Int((card.proratedAwardedDays - Double(card.consumedDays)).rounded())
        }
    }

    private func leaveAwarded(for card: LeaveEmployerCard) -> Int {
        switch countScope {
        case .throughToday:
            return Int(card.proratedAwardedDaysThroughToday.rounded())
        case .fullYear:
            return Int(card.proratedAwardedDays.rounded())
        }
    }

    private func leaveConsumed(for card: LeaveEmployerCard) -> Int {
        switch countScope {
        case .throughToday:
            return card.consumedDaysThroughToday
        case .fullYear:
            return card.consumedDays
        }
    }

    private func leaveMonths(for card: LeaveEmployerCard) -> [LeaveMonthBreakdown] {
        switch countScope {
        case .throughToday:
            return card.monthsThroughToday
        case .fullYear:
            return card.months
        }
    }

    private func compactStat(title: String, subtitle: String, value: Int, accent: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text("\(value)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func monthBreakdownRow(month: LeaveMonthBreakdown) -> some View {
        let awarded = month.proratedAwardedDays
        let consumed = month.consumedDays
        let isQuietMonth = awarded < 0.01 && consumed == 0
        let fillRatio: CGFloat = {
            guard awarded > 0.001 else { return consumed > 0 ? 1 : 0 }
            return CGFloat(min(1, Double(consumed) / awarded))
        }()

        return HStack(spacing: 12) {
            Text(monthMonthLabel(month))
                .font(.subheadline.weight(.medium))
                .frame(width: 38, alignment: .leading)
                .foregroundStyle(.primary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(awardedColor.opacity(0.2))
                        .frame(height: 5)
                    Capsule()
                        .fill(consumedColor.opacity(0.92))
                        .frame(width: max(2, geo.size.width * fillRatio), height: 5)
                }
            }
            .frame(height: 5)

            HStack(spacing: 3) {
                Text("\(Int(awarded.rounded()))")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text("·")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("\(consumed)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            .frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Color(.tertiarySystemGroupedBackground).opacity(0.55),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .opacity(isQuietMonth ? 0.42 : 1)
    }

    /// Month name in the journal calendar (not device timezone — avoids “Dec” for January data).
    private func monthMonthLabel(_ month: LeaveMonthBreakdown) -> String {
        let symbols = calendar.shortStandaloneMonthSymbols
        let index = month.calendarMonth - 1
        guard index >= 0, index < symbols.count else { return "?" }
        return symbols[index]
    }
}

struct LeaveMonthBreakdown: Hashable, Sendable {
    var monthStart: Date
    /// Civil year/month for this row (journal timezone).
    var calendarYear: Int
    var calendarMonth: Int
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
    var proratedAwardedDaysThroughToday: Double
    var consumedDaysThroughToday: Int
    var months: [LeaveMonthBreakdown]
    var monthsThroughToday: [LeaveMonthBreakdown]
}

struct LeaveYearReport: Hashable, Sendable {
    var year: Int
    var employerCards: [LeaveEmployerCard]
    var throughTodayEnd: Date?
}

enum LeaveDashboardAggregator {
    static func report(
        year: Int,
        employerPeriods: [EmployerPeriod],
        journalDays: [JournalDay],
        calendar: Calendar
    ) -> LeaveYearReport {
        guard let (yearStart, yearEnd) = YearOverviewAggregator.yearBounds(year: year, calendar: calendar) else {
            return LeaveYearReport(year: year, employerCards: [], throughTodayEnd: nil)
        }

        let yearTodayEnd = YearOverviewAggregator.throughTodayEnd(
            rangeStart: yearStart,
            rangeEnd: yearEnd,
            calendar: calendar
        )

        let annualLeaveDays: Set<Date> = Set(
            journalDays
                .filter { $0.nonWorkingReason == .annualLeave }
                .compactMap { jd in
                    JournalCalendar.normalizedStartOfDay(dayKey: jd.canonicalDayKey)
                }
                .map { ModelValidation.startOfDay($0, calendar: calendar) }
        )

        let cards = employerPeriods.compactMap { period -> LeaveEmployerCard? in
            let (periodStart, periodEnd) = period.normalizedRange(in: calendar)
            let clipStart = max(periodStart, yearStart)
            let clipEnd = min(periodEnd, yearEnd)
            guard clipStart <= clipEnd else { return nil }

            let monthBreakdowns = monthlyBreakdowns(
                clipStart: clipStart,
                clipEnd: clipEnd,
                countThrough: clipEnd,
                annualEntitlement: period.annualLeaveEntitlementDays,
                annualLeaveDays: annualLeaveDays,
                calendar: calendar
            )

            let awarded = monthBreakdowns.reduce(0.0) { $0 + $1.proratedAwardedDays }
            let consumed = monthBreakdowns.reduce(0) { $0 + $1.consumedDays }

            let monthBreakdownsThroughToday: [LeaveMonthBreakdown]
            let awardedThroughToday: Double
            let consumedThroughToday: Int
            if let throughEnd = YearOverviewAggregator.throughTodayEnd(
                rangeStart: clipStart,
                rangeEnd: clipEnd,
                calendar: calendar
            ) {
                monthBreakdownsThroughToday = monthlyBreakdowns(
                    clipStart: clipStart,
                    clipEnd: clipEnd,
                    countThrough: throughEnd,
                    annualEntitlement: period.annualLeaveEntitlementDays,
                    annualLeaveDays: annualLeaveDays,
                    calendar: calendar
                )
                awardedThroughToday = monthBreakdownsThroughToday.reduce(0.0) { $0 + $1.proratedAwardedDays }
                consumedThroughToday = monthBreakdownsThroughToday.reduce(0) { $0 + $1.consumedDays }
            } else {
                monthBreakdownsThroughToday = []
                awardedThroughToday = 0
                consumedThroughToday = 0
            }

            return LeaveEmployerCard(
                id: period.id,
                companyName: period.companyName,
                employerCountryCode: period.employerCountryCode,
                clippedRangeStart: clipStart,
                clippedRangeEnd: clipEnd,
                proratedAwardedDays: awarded,
                consumedDays: consumed,
                proratedAwardedDaysThroughToday: awardedThroughToday,
                consumedDaysThroughToday: consumedThroughToday,
                months: monthBreakdowns,
                monthsThroughToday: monthBreakdownsThroughToday
            )
        }
        .sorted { $0.clippedRangeStart < $1.clippedRangeStart }

        return LeaveYearReport(year: year, employerCards: cards, throughTodayEnd: yearTodayEnd)
    }

    private static func monthlyBreakdowns(
        clipStart: Date,
        clipEnd: Date,
        countThrough: Date,
        annualEntitlement: Int,
        annualLeaveDays: Set<Date>,
        calendar: Calendar
    ) -> [LeaveMonthBreakdown] {
        let monthlyEntitlement = Double(annualEntitlement) / 12.0
        let countCap = ModelValidation.startOfDay(countThrough, calendar: calendar)
        var rows: [LeaveMonthBreakdown] = []

        var cursor = startOfMonth(for: clipStart, calendar: calendar)
        let endMonth = startOfMonth(for: clipEnd, calendar: calendar)

        while cursor <= endMonth {
            let calendarYear = calendar.component(.year, from: cursor)
            let calendarMonth = calendar.component(.month, from: cursor)

            guard let monthInterval = calendar.dateInterval(of: .month, for: cursor) else { break }
            let monthStart = ModelValidation.startOfDay(monthInterval.start, calendar: calendar)
            guard let monthEndRaw = calendar.date(byAdding: .day, value: -1, to: monthInterval.end) else { break }
            let monthEnd = ModelValidation.startOfDay(monthEndRaw, calendar: calendar)

            let overlapStart = max(monthStart, clipStart)
            let overlapEnd = min(monthEnd, clipEnd, countCap)

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
                    calendarYear: calendarYear,
                    calendarMonth: calendarMonth,
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
