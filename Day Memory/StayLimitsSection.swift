//
//  StayLimitsSection.swift
//  Day Memory
//

import Charts
import SwiftData
import SwiftUI

struct StayLimitsSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StayLimitRule.sortOrder) private var rules: [StayLimitRule]
    @Query(sort: \JournalDay.day) private var journalDays: [JournalDay]
    @Query(sort: \EmployerPeriod.startDate) private var employerPeriods: [EmployerPeriod]

    @State private var draftCountry = ""
    @State private var draftAllowed = 90
    @State private var draftPeriod = 180
    @State private var showDuplicate = false

    private let cardBackground = Color(.secondarySystemGroupedBackground)
    private let navy = Color(red: 0.07, green: 0.24, blue: 0.50)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stay limits")
                .font(.title3.weight(.semibold))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 0) {
                if rules.isEmpty {
                    form
                        .padding(16)
                } else {
                    ForEach(rules) { rule in
                        NavigationLink {
                            StayLimitDetailView(rule: rule)
                        } label: {
                            ruleSummary(rule)
                                .padding(16)
                        }
                        .buttonStyle(.plain)
                        Divider()
                            .padding(.leading, 16)
                    }
                    form
                        .padding(16)
                }
            }
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text("Counted from your journal. Confirm the entry rule with the official calculator or an adviser.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .alert("Already tracked", isPresented: $showDuplicate) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This country is already tracked for these days and this period.")
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            if rules.isEmpty {
                Text("Track a country for a set number of days in each rolling period.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CountryPicker(
                title: "Country",
                selection: $draftCountry,
                frequentCodes: Countries.frequentCodes(
                    journalDays: journalDays,
                    employerPeriods: employerPeriods,
                    including: draftCountry
                )
            )

            Stepper(value: $draftAllowed, in: 1...max(draftPeriod, 1)) {
                Text("\(draftAllowed) days")
                    .monospacedDigit()
            }
            .onChange(of: draftPeriod) { _, newValue in
                if draftAllowed > newValue {
                    draftAllowed = max(1, newValue)
                }
            }

            Stepper(value: $draftPeriod, in: 1...1095) {
                Text("in every \(draftPeriod) days")
                    .monospacedDigit()
            }

            Button("Add rule") {
                addRule()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canAdd)
        }
    }

    private var canAdd: Bool {
        ModelValidation.isValidCountryCode(draftCountry.uppercased())
            && draftAllowed >= 1
            && draftPeriod >= 1
            && draftAllowed <= draftPeriod
    }

    private func addRule() {
        let country = draftCountry.uppercased()
        guard ModelValidation.isValidCountryCode(country) else { return }
        let candidate = StayRuleIdentity(countryCode: country, allowedDays: draftAllowed, periodDays: draftPeriod)
        let existing = rules.map {
            StayRuleIdentity(countryCode: $0.countryCode, allowedDays: $0.allowedDays, periodDays: $0.periodDays)
        }
        guard !StayLimitEvaluator.clashes(candidate, with: existing) else {
            showDuplicate = true
            return
        }
        let nextOrder = (rules.map(\.sortOrder).max() ?? -1) + 1
        let rule = StayLimitRule(
            countryCode: country,
            allowedDays: draftAllowed,
            periodDays: draftPeriod,
            sortOrder: nextOrder
        )
        modelContext.insert(rule)
        try? modelContext.save()
        draftCountry = ""
    }

    private func ruleSummary(_ rule: StayLimitRule) -> some View {
        let report = report(for: rule)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                countryBadge(rule.countryCode)
                VStack(alignment: .leading, spacing: 2) {
                    Text(CountryDisplay.name(for: rule.countryCode))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(rulePhrase(allowed: rule.allowedDays, period: rule.periodDays))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            Text(headline(report))
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle = subtitle(report) {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            StayUsageBar(used: report.usedInCurrentWindow, allowed: report.allowedDays, tint: navy)
            HStack {
                Text("\(report.usedInCurrentWindow) of \(report.allowedDays) days")
                    .monospacedDigit()
                Spacer(minLength: 8)
                Text(windowCaption(report))
                    .multilineTextAlignment(.trailing)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if report.unloggedDaysInCurrentWindow > 0 {
                Text(gapCaption(report.unloggedDaysInCurrentWindow))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(planCaption(report))
                .font(.subheadline)
                .foregroundStyle(report.breaches.isEmpty ? Color.secondary : Color.red)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func report(for rule: StayLimitRule) -> StayLimitReport {
        StayLimitEvaluator.evaluate(
            countryCode: rule.countryCode,
            allowedDays: rule.allowedDays,
            periodDays: rule.periodDays,
            days: journalDays.map {
                StayJournalDay(dayKey: $0.canonicalDayKey, countryCodes: $0.orderedSegments.map(\.countryCode))
            },
            todayKey: JournalCalendar.dayKey(for: .now),
            calendar: JournalCalendar.civil
        )
    }

    private func countryBadge(_ code: String) -> some View {
        Text(code.uppercased())
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(navy)
            .frame(width: 34, height: 34)
            .background(navy.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct StayLimitDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \JournalDay.day) private var journalDays: [JournalDay]
    @Query(sort: \EmployerPeriod.startDate) private var employerPeriods: [EmployerPeriod]

    @Bindable var rule: StayLimitRule

    @State private var editing = false
    @State private var draftCountry = ""
    @State private var draftAllowed = 90
    @State private var draftPeriod = 180
    @State private var showDuplicate = false
    @State private var confirmDelete = false

    private let navy = Color(red: 0.07, green: 0.24, blue: 0.50)

    var body: some View {
        let report = currentReport
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(rulePhrase(allowed: rule.allowedDays, period: rule.periodDays))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(headline(report))
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle = subtitle(report) {
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                StayUsageBar(used: report.usedInCurrentWindow, allowed: report.allowedDays, tint: navy)
                Text("\(report.usedInCurrentWindow) of \(report.allowedDays) days in the window \(medium(report.windowStartKey)) – \(medium(report.todayKey)).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if report.unloggedDaysInCurrentWindow > 0 {
                    Text(gapCaption(report.unloggedDaysInCurrentWindow))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                planSection(report)
                chartSection(report)
            }
            .padding(16)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(CountryDisplay.name(for: rule.countryCode))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit") {
                        draftCountry = rule.countryCode
                        draftAllowed = rule.allowedDays
                        draftPeriod = rule.periodDays
                        editing = true
                    }
                    Button("Delete", role: .destructive) {
                        confirmDelete = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Rule actions")
            }
        }
        .sheet(isPresented: $editing) {
            NavigationStack {
                Form {
                    CountryPicker(
                        title: "Country",
                        selection: $draftCountry,
                        frequentCodes: Countries.frequentCodes(
                            journalDays: journalDays,
                            employerPeriods: employerPeriods,
                            including: draftCountry
                        )
                    )
                    Stepper(value: $draftAllowed, in: 1...max(draftPeriod, 1)) {
                        Text("\(draftAllowed) days")
                            .monospacedDigit()
                    }
                    .onChange(of: draftPeriod) { _, newValue in
                        if draftAllowed > newValue {
                            draftAllowed = max(1, newValue)
                        }
                    }
                    Stepper(value: $draftPeriod, in: 1...1095) {
                        Text("in every \(draftPeriod) days")
                            .monospacedDigit()
                    }
                }
                .navigationTitle("Edit rule")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { editing = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { saveEdit() }
                            .disabled(!canSaveEdit)
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .padFormSheet()
        }
        .alert("Already tracked", isPresented: $showDuplicate) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Another rule already uses this country, day count, and period.")
        }
        .confirmationDialog(
            "Delete this rule?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                modelContext.delete(rule)
                try? modelContext.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(CountryDisplay.name(for: rule.countryCode)), \(rulePhrase(allowed: rule.allowedDays, period: rule.periodDays)).")
        }
    }

    private var currentReport: StayLimitReport {
        StayLimitEvaluator.evaluate(
            countryCode: rule.countryCode,
            allowedDays: rule.allowedDays,
            periodDays: rule.periodDays,
            days: journalDays.map {
                StayJournalDay(dayKey: $0.canonicalDayKey, countryCodes: $0.orderedSegments.map(\.countryCode))
            },
            todayKey: JournalCalendar.dayKey(for: .now),
            calendar: JournalCalendar.civil
        )
    }

    private var canSaveEdit: Bool {
        ModelValidation.isValidCountryCode(draftCountry.uppercased())
            && draftAllowed >= 1
            && draftPeriod >= 1
            && draftAllowed <= draftPeriod
    }

    private func saveEdit() {
        let country = draftCountry.uppercased()
        let candidate = StayRuleIdentity(countryCode: country, allowedDays: draftAllowed, periodDays: draftPeriod)
        guard !StayLimitEvaluator.clashes(candidate, with: otherIdentities(ignoring: rule.id)) else {
            showDuplicate = true
            return
        }
        rule.countryCode = country
        rule.allowedDays = draftAllowed
        rule.periodDays = draftPeriod
        try? modelContext.save()
        editing = false
    }

    private func otherIdentities(ignoring id: UUID) -> [StayRuleIdentity] {
        let descriptor = FetchDescriptor<StayLimitRule>()
        let stored = (try? modelContext.fetch(descriptor)) ?? []
        return stored
            .filter { $0.id != id }
            .map { StayRuleIdentity(countryCode: $0.countryCode, allowedDays: $0.allowedDays, periodDays: $0.periodDays) }
    }

    @ViewBuilder
    private func planSection(_ report: StayLimitReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Schedule already filled")
                .font(.headline)
            if report.breaches.isEmpty {
                Text(planCaption(report))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(report.breaches.prefix(3)) { breach in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Over from \(medium(breach.firstDayKey)), peak \(breach.peakCount).")
                            .foregroundStyle(.red)
                        if let safe = breach.lastSafeDayKey {
                            Text("Leaving by \(medium(safe)) stays inside the limit.")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("This stay is over the limit from the day it starts.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if report.breaches.count > 3 {
                    Text("\(report.breaches.count - 3) more stays are also over the limit.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func chartSection(_ report: StayLimitReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Days in each \(report.periodDays)-day window")
                .font(.headline)
            if report.chart.isEmpty {
                Text("No days logged in \(CountryDisplay.name(for: report.countryCode)).")
                    .foregroundStyle(.secondary)
            } else {
                let points = plotPoints(report.chart)
                Chart {
                    ForEach(points) { point in
                        LineMark(
                            x: .value("Window ending", point.date),
                            y: .value("Days in the window", point.days)
                        )
                        .interpolationMethod(.linear)
                        .foregroundStyle(navy)
                    }
                    RuleMark(y: .value("Limit", report.allowedDays))
                        .foregroundStyle(.red)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("\(report.allowedDays)")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                }
                .chartYScale(domain: 0...yTop(report))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4))
                }
                .frame(height: 220)
                .accessibilityLabel("Days in each \(report.periodDays) day window. Limit \(report.allowedDays).")
                Text("Each point is the number of days in \(CountryDisplay.name(for: report.countryCode)) during the \(report.periodDays) days ending on that date, including days already filled in ahead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func plotPoints(_ chart: [StayLimitChartPoint]) -> [StayPlotPoint] {
        let calendar = JournalCalendar.civil
        return chart.compactMap { point in
            guard let date = StayLimitEvaluator.date(forDayKey: point.dayKey, calendar: calendar) else { return nil }
            return StayPlotPoint(id: point.dayKey, date: date, days: point.daysInWindow)
        }
    }

    private func yTop(_ report: StayLimitReport) -> Int {
        let peak = report.chart.map(\.daysInWindow).max() ?? 0
        let top = max(peak, report.allowedDays, 1)
        return top + max(2, top / 12)
    }
}

private struct StayPlotPoint: Identifiable {
    var id: String
    var date: Date
    var days: Int
}

private struct StayUsageBar: View {
    var used: Int
    var allowed: Int
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            let fraction = allowed > 0 ? min(1, CGFloat(used) / CGFloat(allowed)) : 0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(used > allowed ? Color.red : tint)
                    .frame(width: max(0, geo.size.width * fraction))
            }
        }
        .frame(height: 8)
        .accessibilityLabel("\(used) of \(allowed) days")
    }
}

private func rulePhrase(allowed: Int, period: Int) -> String {
    "\(allowed) days in every \(period)"
}

private func headline(_ report: StayLimitReport) -> String {
    switch report.runway {
    case .needsTodayLogged:
        "Log today to calculate a stay"
    case .alreadyOver(let daysOver):
        "\(dayCount(daysOver)) over in the window ending today"
    case .stayUntil(let lastDayKey, _):
        "Stay until \(long(lastDayKey))"
    case .enterUntil(let lastDayKey, _):
        "A stay from today fits until \(long(lastDayKey))"
    case .cannotEnter:
        "A stay from today is already over the limit"
    case .unlimited:
        report.todayStatus == .outside
            ? "A stay from today stays within the limit"
            : "A continuous stay stays within the limit"
    }
}

private func subtitle(_ report: StayLimitReport) -> String? {
    switch report.runway {
    case .stayUntil(_, let further):
        var text = further == 0
            ? "Today is the last day within the limit."
            : further == 1
                ? "1 more day if you do not leave."
                : "\(further) more days if you do not leave."
        if further != report.roomInCurrentWindow {
            text += " Today’s window has \(dayCount(report.roomInCurrentWindow)) of room."
        }
        return text
    case .enterUntil(_, let stayDays):
        var text = "\(dayCount(stayDays)) from today."
        if stayDays != report.roomInCurrentWindow {
            text += " Today’s window has \(dayCount(report.roomInCurrentWindow)) of room."
        }
        return text
    case .alreadyOver:
        return "The days already logged in this window are over the limit."
    case .cannotEnter:
        return "Today’s window already holds \(dayCount(report.usedInCurrentWindow))."
    case .needsTodayLogged, .unlimited:
        return nil
    }
}

private func planCaption(_ report: StayLimitReport) -> String {
    if let breach = report.breaches.first {
        return "Over from \(medium(breach.firstDayKey)), peak \(breach.peakCount)."
    }
    if report.hasUpcomingPresence, let peak = report.upcomingPeak {
        return "Filled days stay inside the limit, peak \(peak)."
    }
    return "No further days in this country are filled in."
}

private func gapCaption(_ count: Int) -> String {
    let noun = count == 1 ? "day" : "days"
    return "\(count) \(noun) in this window have no journal entry, so this count may be low."
}

private func windowCaption(_ report: StayLimitReport) -> String {
    "\(medium(report.windowStartKey)) – \(medium(report.todayKey))"
}

private func dayCount(_ count: Int) -> String {
    count == 1 ? "1 day" : "\(count) days"
}

private func long(_ dayKey: String) -> String {
    guard let date = StayLimitEvaluator.date(forDayKey: dayKey, calendar: JournalCalendar.civil) else { return dayKey }
    return date.formatted(JournalCalendar.weekdayDayMonthYearFormat)
}

private func medium(_ dayKey: String) -> String {
    guard let date = StayLimitEvaluator.date(forDayKey: dayKey, calendar: JournalCalendar.civil) else { return dayKey }
    return date.formatted(JournalCalendar.dayMonthYearFormat)
}
