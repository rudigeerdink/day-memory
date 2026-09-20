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
                || $0.proratedAwardedDays > $0.proratedAwardedDaysThroughToday + 0.05
        }
    }

    private var scopeCaption: some View {
        Group {
            switch countScope {
            case .throughToday:
                if let end = report.throughTodayEnd {
                    Text(
                        "Leave through \(end, format: JournalCalendar.dayMonthYearFormat) in your journal calendar."
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
        let awarded = leaveAwarded(for: card)
        let consumed = leaveConsumed(for: card)
        let months = leaveMonths(for: card)
        let barScale = LeaveMonthBarScale.scale(for: months)

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
                        Text("\(card.companyName) · \(card.clippedRangeStart, format: JournalCalendar.dayMonthFormat)–\(card.clippedRangeEnd, format: JournalCalendar.dayMonthYearFormat)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 0) {
                    leaveStatColumn(
                        label: {
                            Text("Balance")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .tracking(0.6)
                                .lineLimit(1)
                        },
                        value: LeaveDaysFormatting.signedText(balance),
                        valueColor: balanceTint(balance),
                        caption: "days vs pro-rated"
                    )
                    statDivider
                    leaveStatColumn(
                        label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(awardedColor)
                                    .frame(width: 6, height: 6)
                                Text("Awarded")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        },
                        value: LeaveDaysFormatting.text(awarded),
                        valueColor: .primary,
                        caption: "pro-rated"
                    )
                    statDivider
                    leaveStatColumn(
                        label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(consumedColor)
                                    .frame(width: 6, height: 6)
                                Text("Consumed")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        },
                        value: "\(consumed)",
                        valueColor: .primary,
                        caption: "annual leave"
                    )
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
                        monthBreakdownRow(month: month, barScale: barScale)
                    }
                }
            }
            .padding(16)
        }
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func balanceTint(_ balance: Double) -> Color {
        let tenths = (balance * 10).rounded()
        if tenths == 0 { return Color.primary }
        return tenths > 0 ? Color.green : Color.red
    }

    private func leaveBalance(for card: LeaveEmployerCard) -> Double {
        switch countScope {
        case .throughToday:
            return card.proratedAwardedDaysThroughToday - Double(card.consumedDaysThroughToday)
        case .fullYear:
            return card.proratedAwardedDays - Double(card.consumedDays)
        }
    }

    private func leaveAwarded(for card: LeaveEmployerCard) -> Double {
        switch countScope {
        case .throughToday:
            return card.proratedAwardedDaysThroughToday
        case .fullYear:
            return card.proratedAwardedDays
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

    private let statLabelRowHeight: CGFloat = 16

    private var statDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(width: 1, height: 52)
    }

    private func leaveStatColumn<Label: View>(
        @ViewBuilder label: () -> Label,
        value: String,
        valueColor: Color,
        caption: String
    ) -> some View {
        VStack(spacing: 4) {
            label()
                .frame(maxWidth: .infinity)
                .frame(height: statLabelRowHeight)

            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(valueColor)

            Text(caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
    }

    private func monthBreakdownRow(month: LeaveMonthBreakdown, barScale: Double) -> some View {
        let awarded = month.proratedAwardedDays
        let consumed = month.consumedDays
        let isQuietMonth = awarded < 0.01 && consumed == 0
        let awardedRatio = LeaveMonthBarScale.widthRatio(value: awarded, scale: barScale)
        let consumedRatio = LeaveMonthBarScale.widthRatio(value: Double(consumed), scale: barScale)

        return HStack(spacing: 12) {
            Text(monthMonthLabel(month))
                .font(.subheadline.weight(.medium))
                .frame(width: 38, alignment: .leading)
                .foregroundStyle(.primary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 6)
                    Capsule()
                        .fill(awardedColor.opacity(0.55))
                        .frame(width: barSegmentWidth(ratio: awardedRatio, total: geo.size.width), height: 6)
                    Capsule()
                        .fill(consumedColor.opacity(0.92))
                        .frame(width: barSegmentWidth(ratio: consumedRatio, total: geo.size.width), height: 6)
                }
            }
            .frame(height: 6)

            HStack(spacing: 3) {
                Text(LeaveDaysFormatting.text(awarded))
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
            .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Color(.tertiarySystemGroupedBackground).opacity(0.55),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .opacity(isQuietMonth ? 0.42 : 1)
    }

    private func barSegmentWidth(ratio: CGFloat, total: CGFloat) -> CGFloat {
        guard ratio > 0, total > 0 else { return 0 }
        return min(total, max(2, total * ratio))
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

/// Shared month-bar scale: bar length is comparable across rows, not capped at that month's accrual.
enum LeaveMonthBarScale {
    static func scale(for months: [LeaveMonthBreakdown]) -> Double {
        months.reduce(0) { max($0, max($1.proratedAwardedDays, Double($1.consumedDays))) }
    }

    static func widthRatio(value: Double, scale: Double) -> CGFloat {
        guard scale > 0.001, value > 0.001 else { return 0 }
        return CGFloat(min(1, value / scale))
    }
}

/// Leave day labels: whole numbers stay integers; otherwise one decimal, half-up.
enum LeaveDaysFormatting {
    static func text(_ days: Double) -> String {
        let tenths = (days * 10).rounded()
        if tenths.truncatingRemainder(dividingBy: 10) == 0 {
            return String(Int((tenths / 10).rounded()))
        }
        return String(format: "%.1f", tenths / 10)
    }

    static func signedText(_ days: Double) -> String {
        let tenths = (days * 10).rounded()
        if tenths == 0 { return "0" }
        let body = text(days)
        if tenths > 0 { return "+\(body)" }
        return body
    }
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
