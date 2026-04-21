//
//  JournalCalendarView.swift
//  Day Memory
//

import SwiftData
import SwiftUI

struct JournalCalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \JournalDay.day) private var journalDays: [JournalDay]
    @Query(sort: \EmployerPeriod.startDate) private var employerPeriods: [EmployerPeriod]

    @State private var visibleMonth: Date = .now
    /// Persists after the day sheet closes so week apply still knows which week to use (`sheet(item:)` clears `selection` on dismiss).
    @State private var focusedDay: Date?
    @State private var selection: JournalDaySelection?
    @State private var showApplyWeekConfirm = false
    @State private var applyError: String?
    @State private var showApplyError = false
    @State private var fallbackCountry: String = "NL"

    private var calendar: Calendar { .autoupdatingCurrent }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    monthHeader
                    weekdaySymbolsRow
                    monthGrid
                    weekActions
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Fallback country", selection: $fallbackCountry) {
                            ForEach(Countries.common, id: \.code) { item in
                                Text("\(item.name) (\(item.code))").tag(item.code)
                            }
                        }
                    } label: {
                        Image(systemName: "globe")
                    }
                    .accessibilityLabel("Fallback country for new weeks")
                }
            }
            .sheet(item: $selection) { sel in
                NavigationStack {
                    DayDetailView(day: sel.day, defaultFallbackCountry: fallbackCountry)
                }
            }
            .alert("Apply week defaults?", isPresented: $showApplyWeekConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Apply") { applyWeekDefaults() }
            } message: {
                Text("Only days without a journal entry are filled. Weekdays become working days and weekends non-working. Country comes from the last known location before that date, or your fallback (\(fallbackCountry)). Days you already set are left unchanged.")
            }
            .alert("Could not apply week", isPresented: $showApplyError) {
                Button("OK") {
                    applyError = nil
                }
            } message: {
                Text(applyError ?? "")
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                visibleMonth = calendar.date(byAdding: .month, value: -1, to: visibleMonth) ?? visibleMonth
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.plain)

            Spacer()

            Text(visibleMonth, format: .dateTime.month(.wide).year())
                .font(.title2.weight(.semibold))

            Spacer()

            Button {
                visibleMonth = calendar.date(byAdding: .month, value: 1, to: visibleMonth) ?? visibleMonth
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    private var weekdaySymbolsRow: some View {
        let symbols = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        let ordered = Array(symbols[first...] + symbols[..<first])
        return HStack(spacing: 0) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, sym in
                Text(sym.uppercased())
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        let days = daysForMonthGrid()
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(days, id: \.self) { day in
                if let day {
                    dayCell(day)
                } else {
                    Color.clear
                        .frame(height: 44)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let normalized = ModelValidation.startOfDay(day, calendar: calendar)
        let record = journalDays.first { ModelValidation.startOfDay($0.day, calendar: calendar) == normalized }
        let isToday = calendar.isDateInToday(day)
        let isSelected = focusedDay.map {
            ModelValidation.startOfDay($0, calendar: calendar) == normalized
        } ?? false

        let accentCountryLine = emphasizeCountryLine(forNormalizedDay: normalized, record: record)
        let workAwayFromEmployer = showsWorkAwayFromEmployer(normalizedDay: normalized, record: record)

        let todayStart = ModelValidation.startOfDay(Date(), calendar: calendar)
        let isPastDay = normalized < todayStart
        let isUnfilled = journalIsUnfilled(record)
        let showPastUnfilled = isPastDay && isUnfilled

        return Button {
            focusedDay = normalized
            selection = JournalDaySelection(day: normalized)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemGroupedBackground))
                VStack(spacing: 4) {
                    Text("\(calendar.component(.day, from: day))")
                        .font(.body.weight(isToday ? .bold : .regular))
                    if let record, let countryLine = gridCountryLabel(for: record) {
                        Text(countryLine)
                            .font(.caption2.weight(accentCountryLine ? .semibold : .medium))
                            .foregroundStyle(accentCountryLine ? Color.primary : Color.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    } else {
                        Circle()
                            .fill(Color.clear)
                            .frame(width: 4, height: 4)
                    }
                }
                .padding(.vertical, 6)
            }
            .overlay(alignment: .leading) {
                if accentCountryLine, record != nil {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(Color.primary.opacity(0.22))
                        .frame(width: 2)
                        .padding(.leading, 4)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottom) {
                if workAwayFromEmployer {
                    Rectangle()
                        .fill(Color.yellow.opacity(0.92))
                        .frame(height: 2)
                        .padding(.horizontal, 7)
                        .padding(.bottom, 3)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                } else if showPastUnfilled {
                    Rectangle()
                        .fill(Color.red.opacity(0.85))
                        .frame(height: 2)
                        .padding(.horizontal, 7)
                        .padding(.bottom, 3)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(height: 56)
    }

    private func journalIsUnfilled(_ record: JournalDay?) -> Bool {
        guard let record else { return true }
        return record.segments.isEmpty
    }

    /// Employer country active on `normalizedDay`, from non-overlapping periods.
    private func employerCountryCode(forNormalizedDay normalizedDay: Date) -> String? {
        let day = ModelValidation.startOfDay(normalizedDay, calendar: calendar)
        for period in employerPeriods {
            let bounds = ModelValidation.normalizedInclusiveRange(
                start: period.startDate,
                end: period.endDate,
                calendar: calendar
            )
            if day >= bounds.0 && day <= bounds.1 {
                return period.employerCountryCode.uppercased()
            }
        }
        return nil
    }

    /// Working presence in a country different from that day’s employer payer country.
    private func showsWorkAwayFromEmployer(normalizedDay: Date, record: JournalDay?) -> Bool {
        guard let record else { return false }
        guard let employer = employerCountryCode(forNormalizedDay: normalizedDay) else { return false }
        for segment in record.segments where segment.isWorking {
            if segment.countryCode.uppercased() != employer {
                return true
            }
        }
        return false
    }

    /// Single code, or `NL/AE` when two segments (ordered by `sortOrder`).
    private func gridCountryLabel(for record: JournalDay) -> String? {
        let sorted = record.segments.sorted { $0.sortOrder < $1.sortOrder }
        guard let first = sorted.first else { return nil }
        if sorted.count >= 2 {
            let second = sorted[1]
            return "\(first.countryCode)/\(second.countryCode)"
        }
        return first.countryCode
    }

    /// Primary presence country for a day (first segment), or `nil` if unlogged.
    private func primaryCountryCode(forNormalizedDay normalized: Date) -> String? {
        guard let jd = journalDays.first(where: { ModelValidation.startOfDay($0.day, calendar: calendar) == normalized }),
              let first = jd.segments.sorted(by: { $0.sortOrder < $1.sortOrder }).first
        else { return nil }
        return first.countryCode
    }

    /// First day of a new country run vs the **previous calendar day** (including across month boundaries).
    private func isCountryRunStart(forNormalizedDay normalizedDay: Date) -> Bool {
        guard let todayCode = primaryCountryCode(forNormalizedDay: normalizedDay) else { return false }
        guard let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: normalizedDay) else { return false }
        let yesterdayNorm = ModelValidation.startOfDay(yesterdayDate, calendar: calendar)
        let yesterdayCode = primaryCountryCode(forNormalizedDay: yesterdayNorm)
        if yesterdayCode == nil {
            return true
        }
        return todayCode != yesterdayCode
    }

    /// Strong line + type: split travel days (`NL/AE`), or single-country run starts—except the day **after**
    /// a split day when today is only the “landing” continuation (matches yesterday’s **second** segment).
    private func emphasizeCountryLine(forNormalizedDay normalized: Date, record: JournalDay?) -> Bool {
        guard let record else { return false }
        let sorted = record.segments.sorted { $0.sortOrder < $1.sortOrder }
        if sorted.count >= 2 {
            return true
        }
        if isNaturalContinuationLandingDay(forNormalizedDay: normalized) {
            return false
        }
        return isCountryRunStart(forNormalizedDay: normalized)
    }

    /// True when **yesterday** was a split day and today’s primary country equals yesterday’s **second** segment (arrival).
    private func isNaturalContinuationLandingDay(forNormalizedDay normalizedDay: Date) -> Bool {
        guard let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: normalizedDay) else { return false }
        let yesterdayNorm = ModelValidation.startOfDay(yesterdayDate, calendar: calendar)
        guard let yRecord = journalDays.first(where: { ModelValidation.startOfDay($0.day, calendar: calendar) == yesterdayNorm }) else {
            return false
        }
        let ySorted = yRecord.segments.sorted { $0.sortOrder < $1.sortOrder }
        guard ySorted.count >= 2 else { return false }
        guard let todayPrimary = primaryCountryCode(forNormalizedDay: normalizedDay) else { return false }
        return ySorted[1].countryCode == todayPrimary
    }

    private var weekActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Week tools")
                .font(.headline)
            Text("Tap a day to choose which week (it stays selected after you close the editor). Then confirm below.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                guard focusedDay != nil else { return }
                showApplyWeekConfirm = true
            } label: {
                Label("Apply defaults to this week", systemImage: "calendar.badge.clock")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(focusedDay == nil)
        }
        .padding(.top, 8)
    }

    private func daysForMonthGrid() -> [Date?] {
        guard let dayRange = calendar.range(of: .day, in: .month, for: visibleMonth),
              let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: visibleMonth))
        else { return [] }

        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let leadingBlankDays = (firstWeekday - calendar.firstWeekday + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: leadingBlankDays)
        for day in dayRange {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) {
                days.append(date)
            }
        }
        while days.count % 7 != 0 {
            days.append(nil)
        }
        return days
    }

    private func applyWeekDefaults() {
        guard let anchor = focusedDay else { return }
        do {
            try JournalBulkFill.applyWeekDefaults(
                weekContaining: anchor,
                calendar: calendar,
                fallbackCountry: fallbackCountry,
                context: modelContext
            )
            applyError = nil
        } catch {
            applyError = error.localizedDescription
            showApplyError = true
        }
    }
}

struct JournalDaySelection: Identifiable {
    var day: Date
    var id: TimeInterval { day.timeIntervalSinceReferenceDate }
}

#Preview {
    JournalCalendarView()
        .modelContainer(
            for: [EmployerPeriod.self, JournalDay.self, PresenceSegment.self, Trip.self, TripTicketImage.self],
            inMemory: true
        )
}
