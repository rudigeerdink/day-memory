//
//  JournalCalendarView.swift
//  Day Memory
//

import SwiftData
import SwiftUI

struct JournalCalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \JournalDay.day) private var journalDays: [JournalDay]
    @Query(sort: \EmployerPeriod.startDate) private var employerPeriods: [EmployerPeriod]

    @State private var visibleMonth: Date = JournalCalendar.monthStart(for: .now)
    @State private var monthDragOffset: CGFloat = 0
    @State private var monthPageWidth: CGFloat = DayMemoryLayout.isPad ? DayMemoryLayout.screenWidth : 0
    @State private var didMeasureMonthPage = false
    @State private var showDayInspector = false
    @GestureState private var pagerDrag = PagerDrag()
    /// Persists after the day sheet closes so week apply still knows which week to use (`sheet(item:)` clears `selection` on dismiss).
    @State private var focusedDay: Date?
    @State private var selection: JournalDaySelection?
    @State private var showApplyWeekConfirm = false
    @State private var applyError: String?
    @State private var showApplyError = false
    @State private var fallbackCountry: String = Countries.deviceRegionCode
    @State private var showFallbackCountryPicker = false

    private struct MonthLegendItem: Hashable {
        let countryCode: String
        let isWorking: Bool
    }

    private struct MonthGridSlot: Identifiable {
        let id: String
        let day: Date?
    }

    private struct PagerDrag: Equatable {
        var isHorizontal = false
        var translation: CGFloat = 0
    }

    private var calendar: Calendar { JournalCalendar.civil }

    private var usesRegularPadLayout: Bool {
        DayMemoryLayout.isRegularPad(horizontalSizeClass)
    }

    private var monthGridSpacing: CGFloat { usesRegularPadLayout ? 8 : 6 }

    var body: some View {
        NavigationStack {
            journalPage
                .navigationTitle("Journal")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showFallbackCountryPicker = true
                        } label: {
                            Image(systemName: "globe")
                        }
                        .accessibilityLabel("Fallback country for new weeks")
                    }
                }
                .sheet(isPresented: $showFallbackCountryPicker) {
                    NavigationStack {
                        CountryPickerSheet(
                            selection: $fallbackCountry,
                            frequentCodes: Countries.frequentCodes(
                                journalDays: journalDays,
                                employerPeriods: employerPeriods,
                                including: fallbackCountry
                            )
                        )
                    }
                    .presentationDetents([.medium, .large])
                    .padFormSheet()
                }
                .modifier(DayEditorPresentation(
                    usesInspector: usesRegularPadLayout,
                    selection: $selection,
                    showInspector: $showDayInspector,
                    focusedDay: focusedDay,
                    fallbackCountry: fallbackCountry
                ))
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
            .onChange(of: horizontalSizeClass) { _, _ in
                guard DayMemoryLayout.isPad else { return }
                if usesRegularPadLayout {
                    if let day = selection?.day {
                        focusedDay = day
                        selection = nil
                        showDayInspector = true
                    }
                } else if showDayInspector, let focusedDay {
                    showDayInspector = false
                    selection = JournalDaySelection(day: focusedDay)
                }
            }
        }
    }

    private var journalPage: some View {
        ScrollView {
            fittedJournalColumn
        }
        .scrollDisabled(pagerDrag.isHorizontal)
    }

    @ViewBuilder
    private var fittedJournalColumn: some View {
        if usesRegularPadLayout {
            journalColumn
                .frame(maxWidth: 920)
                .frame(maxWidth: .infinity)
        } else {
            journalColumn
        }
    }

    private var journalColumn: some View {
        VStack(alignment: .leading, spacing: 20) {
            monthCalendarContent
                .padding(.horizontal, 16)
            weekActionsBlock
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private var weekActionsBlock: some View {
        if usesRegularPadLayout {
            weekActions
                .frame(maxWidth: 480, alignment: .leading)
        } else {
            weekActions
        }
    }

    private var monthCalendarContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            monthHeader
            weekdaySymbolsRow
            monthPager
        }
    }

    private var monthPager: some View {
        GeometryReader { geometry in
            let pageWidth = geometry.size.width
            let previousMonth = adjacentMonth(to: visibleMonth, by: -1)
            let nextMonth = adjacentMonth(to: visibleMonth, by: 1)

            HStack(alignment: .top, spacing: 0) {
                monthPage(month: previousMonth, pageWidth: pageWidth)
                    .id(monthPageID(previousMonth))
                monthPage(month: visibleMonth, pageWidth: pageWidth)
                    .id(monthPageID(visibleMonth))
                monthPage(month: nextMonth, pageWidth: pageWidth)
                    .id(monthPageID(nextMonth))
            }
            .offset(x: -pageWidth + monthDragOffset + pagerDrag.translation)
            .frame(width: pageWidth * 3, alignment: .leading)
            .frame(width: pageWidth, alignment: .leading)
            .clipped()
            .contentShape(Rectangle())
            .highPriorityGesture(monthPagerDragGesture(pageWidth: pageWidth))
            .onAppear {
                monthPageWidth = pageWidth
                didMeasureMonthPage = true
            }
            .onChange(of: pageWidth) { _, newWidth in
                monthPageWidth = newWidth
                didMeasureMonthPage = true
            }
        }
        .frame(height: monthPagerHeight(for: visibleMonth, pageWidth: monthPageWidth))
    }

    private func monthPage(month: Date, pageWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            monthGrid(for: month, cellHeight: dayCellHeight(pageWidth: pageWidth))
            monthColorLegend(for: month)
        }
        .frame(width: pageWidth, alignment: .leading)
    }

    private func monthPageID(_ month: Date) -> String {
        JournalCalendar.dayKey(for: normalizedMonthStart(for: month))
    }

    private func monthPagerDragGesture(pageWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .updating($pagerDrag) { value, state, _ in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical), abs(horizontal) > 6 else { return }
                state = PagerDrag(isHorizontal: true, translation: horizontal)
            }
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical), abs(horizontal) > 6 else { return }

                monthDragOffset += horizontal
                let projected = value.predictedEndTranslation.width
                let threshold = pageWidth * 0.22
                if projected < -threshold {
                    completeMonthPageTransition(by: 1, pageWidth: pageWidth)
                } else if projected > threshold {
                    completeMonthPageTransition(by: -1, pageWidth: pageWidth)
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        monthDragOffset = 0
                    }
                }
            }
    }

    private func shiftMonth(by delta: Int) {
        let width = monthPageWidth
        guard width > 0 else {
            applyMonthChange(by: delta)
            return
        }
        completeMonthPageTransition(by: delta, pageWidth: width)
    }

    private func completeMonthPageTransition(by delta: Int, pageWidth: CGFloat) {
        withAnimation(.easeOut(duration: 0.26)) {
            monthDragOffset = -CGFloat(delta) * pageWidth
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                applyMonthChange(by: delta)
                monthDragOffset = 0
            }
        }
    }

    private func applyMonthChange(by delta: Int) {
        let anchor = normalizedMonthStart(for: visibleMonth)
        visibleMonth = calendar.date(byAdding: .month, value: delta, to: anchor) ?? visibleMonth
    }

    private func normalizedMonthStart(for month: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
    }

    private func adjacentMonth(to month: Date, by delta: Int) -> Date {
        let start = normalizedMonthStart(for: month)
        return calendar.date(byAdding: .month, value: delta, to: start) ?? start
    }

    private func dayCellHeight(pageWidth: CGFloat) -> CGFloat {
        guard usesRegularPadLayout, pageWidth > 0 else { return 56 }
        let columnWidth = (pageWidth - monthGridSpacing * 6) / 7
        return min(120, max(72, floor(columnWidth * 0.92)))
    }

    private func monthPagerHeight(for month: Date, pageWidth: CGFloat) -> CGFloat {
        let rowCount = max(1, daysForMonthGrid(month: month).count / 7)
        let gridHeight: CGFloat
        if usesRegularPadLayout {
            let cell = dayCellHeight(pageWidth: pageWidth)
            gridHeight = CGFloat(rowCount) * cell + CGFloat(max(0, rowCount - 1)) * monthGridSpacing + 4
        } else {
            gridHeight = CGFloat(rowCount) * 62
        }
        let legendItems = monthLegendItems(from: visibleCountryCodesInMonth(month: month))
        let legendHeight = legendBlockHeight(itemCount: legendItems.count, pageWidth: pageWidth)
        let legendSpacing = legendItems.isEmpty ? 0 : CGFloat(20)
        return gridHeight + legendSpacing + legendHeight
    }

    private func legendBlockHeight(itemCount: Int, pageWidth: CGFloat) -> CGFloat {
        guard itemCount > 0 else { return 0 }
        let rows: Int
        if usesRegularPadLayout, didMeasureMonthPage, pageWidth > 0 {
            let columns = max(1, Int((pageWidth + 12) / 152))
            rows = Int(ceil(Double(itemCount) / Double(columns)))
        } else {
            rows = max(1, itemCount / 2)
        }
        return CGFloat(rows) * 28
    }

    private var monthHeader: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.plain)

            Spacer()

            Text(visibleMonth, format: JournalCalendar.monthYearFormat)
                .font(.title2.weight(.semibold))
                .id(monthPageID(visibleMonth))

            Spacer()

            Button {
                shiftMonth(by: 1)
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
        return HStack(spacing: 6) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, sym in
                Text(sym.uppercased())
                    .font((usesRegularPadLayout ? Font.caption : Font.caption2).weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func monthGridSlots(for month: Date) -> [MonthGridSlot] {
        let monthID = monthPageID(month)
        return daysForMonthGrid(month: month).enumerated().map { index, day in
            MonthGridSlot(id: "\(monthID)-\(index)", day: day)
        }
    }

    private func monthGrid(for month: Date, cellHeight: CGFloat) -> some View {
        let slots = monthGridSlots(for: month)
        let columns = Array(repeating: GridItem(.flexible(), spacing: monthGridSpacing), count: 7)
        return LazyVGrid(columns: columns, spacing: monthGridSpacing) {
            ForEach(slots) { slot in
                if let day = slot.day {
                    dayCell(day, height: cellHeight)
                } else {
                    Color.clear
                        .frame(height: cellHeight)
                }
            }
        }
    }

    private func monthColorLegend(for month: Date) -> some View {
        let codes = visibleCountryCodesInMonth(month: month)
        let items = monthLegendItems(from: codes)
        return Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 140), spacing: 12)],
                        alignment: .leading,
                        spacing: 6
                    ) {
                        ForEach(items, id: \.self) { item in
                            legendDot(
                                color: CountryColors.dotColor(countryCode: item.countryCode, isWorking: item.isWorking),
                                label: "\(item.countryCode) \(item.isWorking ? "working" : "non-working")"
                            )
                        }
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Date, height: CGFloat) -> some View {
        let dayKey = JournalCalendar.dayKey(for: day)
        let normalized = JournalCalendar.normalizedStartOfDay(dayKey: dayKey)
            ?? ModelValidation.startOfDay(day, calendar: calendar)
        let record = journalDays.first { $0.canonicalDayKey == dayKey }
        let isToday = calendar.isDateInToday(day)
        let isSelected = focusedDay.map {
            JournalCalendar.dayKey(for: $0) == dayKey
        } ?? false

        let accentCountryLine = emphasizeCountryLine(forNormalizedDay: normalized, record: record)
        let workAwayFromEmployer = showsWorkAwayFromEmployer(normalizedDay: normalized, record: record)
        let transitionStyle = transitionIndicatorStyle(forNormalizedDay: normalized, record: record)
        let reasonTint = nonWorkingReasonTint(for: record)

        let todayStart = ModelValidation.startOfDay(Date(), calendar: calendar)
        let isPastDay = normalized < todayStart
        let isUnfilled = journalIsUnfilled(record)
        let showPastUnfilled = isPastDay && isUnfilled
        let prominent = height >= 84

        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.08) : Color(.secondarySystemGroupedBackground))
            if let reasonTint {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(reasonTint)
            }
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: day))")
                    .font((prominent ? Font.title3 : Font.body).weight(isToday ? .bold : .regular))
                if let record, let countryLine = gridCountryLabel(for: record) {
                    VStack(spacing: 4) {
                        Text(countryLine)
                            .font((prominent ? Font.caption : Font.caption2).weight(accentCountryLine ? .semibold : .medium))
                            .foregroundStyle(accentCountryLine ? Color.primary : Color.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        HStack(spacing: 4) {
                            ForEach(gridSegments(for: record), id: \.id) { segment in
                                Circle()
                                    .fill(CountryColors.dotColor(countryCode: segment.countryCode, isWorking: segment.isWorking))
                                    .frame(width: prominent ? 8 : 6, height: prominent ? 8 : 6)
                            }
                        }
                    }
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
                    .fill(transitionStyle)
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
        .overlay {
            if isSelected && usesRegularPadLayout {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture {
            focusedDay = normalized
            if usesRegularPadLayout {
                showDayInspector = true
            } else {
                selection = JournalDaySelection(day: normalized)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Day \(calendar.component(.day, from: day))")
        .frame(height: height)
    }

    private func journalIsUnfilled(_ record: JournalDay?) -> Bool {
        guard let record else { return true }
        return record.orderedSegments.isEmpty
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
        for segment in record.orderedSegments where segment.isWorking {
            if segment.countryCode.uppercased() != employer {
                return true
            }
        }
        return false
    }

    /// Single code, or `NL/AE` when two segments (ordered by `sortOrder`).
    private func gridCountryLabel(for record: JournalDay) -> String? {
        let sorted = record.orderedSegments
        guard let first = sorted.first else { return nil }
        if sorted.count >= 2 {
            let second = sorted[1]
            return "\(first.countryCode)/\(second.countryCode)"
        }
        return first.countryCode
    }

    /// Presence segments shown as dot markers under the country label.
    private func gridSegments(for record: JournalDay) -> [PresenceSegment] {
        record.orderedSegments
    }

    /// Vertical indicator style on country-change days:
    /// - Single-country day: arriving segment color.
    /// - Split day: gradient from departure segment to arrival segment.
    private func transitionIndicatorStyle(forNormalizedDay _: Date, record: JournalDay?) -> AnyShapeStyle {
        guard let record else { return AnyShapeStyle(Color.primary.opacity(0.22)) }
        let sorted = record.orderedSegments
        guard let first = sorted.first else { return AnyShapeStyle(Color.primary.opacity(0.22)) }

        if sorted.count >= 2 {
            let second = sorted[1]
            let depart = CountryColors.dotColor(countryCode: first.countryCode, isWorking: first.isWorking)
            let arrive = CountryColors.dotColor(countryCode: second.countryCode, isWorking: second.isWorking)
            return AnyShapeStyle(
                LinearGradient(
                    colors: [depart, arrive],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }

        return AnyShapeStyle(CountryColors.dotColor(countryCode: first.countryCode, isWorking: first.isWorking))
    }

    private func nonWorkingReasonTint(for record: JournalDay?) -> Color? {
        guard let record else { return nil }
        switch record.nonWorkingReason {
        case .none:
            return nil
        case .annualLeave:
            return Color.blue.opacity(0.08)
        case .publicHoliday:
            return Color.orange.opacity(0.08)
        }
    }

    /// Primary presence country for a day (first segment), or `nil` if unlogged.
    private func primaryCountryCode(forNormalizedDay normalized: Date) -> String? {
        let dk = JournalCalendar.dayKey(for: normalized)
        guard let jd = journalDays.first(where: { $0.canonicalDayKey == dk }),
              let first = jd.orderedSegments.first
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
        let sorted = record.orderedSegments
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
        let yKey = JournalCalendar.dayKey(for: yesterdayNorm)
        guard let yRecord = journalDays.first(where: { $0.canonicalDayKey == yKey }) else {
            return false
        }
        let ySorted = yRecord.orderedSegments
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

    private func daysForMonthGrid(month: Date) -> [Date?] {
        guard let dayRange = calendar.range(of: .day, in: .month, for: month),
              let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month))
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

    private func visibleCountryCodesInMonth(month: Date) -> [String] {
        monthDates(month: month).reduce(into: Set<String>()) { acc, day in
            let dk = JournalCalendar.dayKey(for: day)
            guard let record = journalDays.first(where: { $0.canonicalDayKey == dk }) else {
                return
            }
            for segment in record.orderedSegments {
                acc.insert(segment.countryCode.uppercased())
            }
        }
        .sorted()
    }

    private func monthDates(month: Date) -> [Date] {
        guard let dayRange = calendar.range(of: .day, in: .month, for: month),
              let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month))
        else { return [] }

        return dayRange.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth)
        }
    }

    private func monthLegendItems(from codes: [String]) -> [MonthLegendItem] {
        codes.flatMap { code in
            [
                MonthLegendItem(countryCode: code, isWorking: true),
                MonthLegendItem(countryCode: code, isWorking: false),
            ]
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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

/// Sheet on iPhone and in narrow iPad windows. Inspector beside the calendar on a regular iPad.
private struct DayEditorPresentation: ViewModifier {
    var usesInspector: Bool
    @Binding var selection: JournalDaySelection?
    @Binding var showInspector: Bool
    var focusedDay: Date?
    var fallbackCountry: String

    func body(content: Content) -> some View {
        if usesInspector {
            content
                .inspector(isPresented: $showInspector) {
                    if let focusedDay {
                        NavigationStack {
                            DayDetailView(
                                day: focusedDay,
                                defaultFallbackCountry: fallbackCountry,
                                onFinished: { showInspector = false }
                            )
                        }
                        .id(JournalCalendar.dayKey(for: focusedDay))
                    }
                }
                .inspectorColumnWidth(min: 380, ideal: 440, max: 520)
        } else {
            content.sheet(item: $selection) { sel in
                NavigationStack {
                    DayDetailView(day: sel.day, defaultFallbackCountry: fallbackCountry)
                }
            }
        }
    }
}

#Preview {
    JournalCalendarView()
        .modelContainer(
            for: [EmployerPeriod.self, JournalDay.self, PresenceSegment.self, Trip.self, TripTicketImage.self, StayLimitRule.self],
            inMemory: true
        )
}
