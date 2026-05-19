//
//  YearOverviewAggregator.swift
//  Day Memory
//

import Foundation

/// One row per **presence country**: each `JournalDay` segment counts as one unit
/// (a split travel day contributes one unit to each of two countries).
struct YearLocationStat: Hashable, Sendable {
    var countryCode: String
    /// Segment count (= working + nonWorking) for the full selected year range.
    var presenceUnits: Int
    var working: Int
    var nonWorking: Int
    /// Same metrics counting only journal days on or before today (journal calendar).
    var presenceUnitsThroughToday: Int
    var workingThroughToday: Int
    var nonWorkingThroughToday: Int
}

struct YearEmployerSlice: Identifiable, Hashable, Sendable {
    var id: UUID
    var companyName: String
    var employerCountryCode: String
    var clippedRangeStart: Date
    var clippedRangeEnd: Date
    var byPresenceCountry: [YearLocationStat]
    /// Calendar days in the clipped range with no journal entry (full year range).
    var unloggedCalendarDays: Int
    var unloggedCalendarDaysThroughToday: Int
}

struct YearOverviewReport: Hashable, Sendable {
    var year: Int
    var yearTotalsByCountry: [YearLocationStat]
    var unloggedCalendarDaysInYear: Int
    var unloggedCalendarDaysInYearThroughToday: Int
    var employerSlices: [YearEmployerSlice]
    /// Last calendar day included in the “through today” slice (journal timezone).
    var throughTodayEnd: Date?
}

enum YearOverviewAggregator {
    static func report(
        year: Int,
        journalDays: [JournalDay],
        employerPeriods: [EmployerPeriod],
        calendar: Calendar
    ) -> YearOverviewReport {
        let dayMap = journalDayMap(journalDays, calendar: calendar)
        guard let (yearStart, yearEnd) = yearBounds(year: year, calendar: calendar) else {
            return YearOverviewReport(
                year: year,
                yearTotalsByCountry: [],
                unloggedCalendarDaysInYear: 0,
                unloggedCalendarDaysInYearThroughToday: 0,
                employerSlices: [],
                throughTodayEnd: nil
            )
        }

        let todayEnd = throughTodayEnd(rangeStart: yearStart, rangeEnd: yearEnd, calendar: calendar)
        let yearDayList = inclusiveDayRange(from: yearStart, through: yearEnd, calendar: calendar)
        let yearDayListThroughToday = todayEnd.map {
            inclusiveDayRange(from: yearStart, through: $0, calendar: calendar)
        } ?? []

        let (yearStats, yearUnlogged) = aggregate(days: yearDayList, daysThroughToday: yearDayListThroughToday, dayMap: dayMap)
        let yearUnloggedThroughToday = aggregateUnloggedOnly(days: yearDayListThroughToday, dayMap: dayMap)

        let employerSlices: [YearEmployerSlice] = employerPeriods.compactMap { period in
            guard let (clipStart, clipEnd) = clipPeriodToYear(period: period, year: year, calendar: calendar) else {
                return nil
            }
            let days = inclusiveDayRange(from: clipStart, through: clipEnd, calendar: calendar)
            let daysThroughToday: [Date]
            if let cap = throughTodayEnd(rangeStart: clipStart, rangeEnd: clipEnd, calendar: calendar) {
                daysThroughToday = inclusiveDayRange(from: clipStart, through: cap, calendar: calendar)
            } else {
                daysThroughToday = []
            }
            let (stats, unlogged) = aggregate(days: days, daysThroughToday: daysThroughToday, dayMap: dayMap)
            let unloggedThroughToday = aggregateUnloggedOnly(days: daysThroughToday, dayMap: dayMap)
            return YearEmployerSlice(
                id: period.id,
                companyName: period.companyName,
                employerCountryCode: period.employerCountryCode,
                clippedRangeStart: clipStart,
                clippedRangeEnd: clipEnd,
                byPresenceCountry: stats,
                unloggedCalendarDays: unlogged,
                unloggedCalendarDaysThroughToday: unloggedThroughToday
            )
        }
        .sorted { $0.clippedRangeStart < $1.clippedRangeStart }

        return YearOverviewReport(
            year: year,
            yearTotalsByCountry: yearStats,
            unloggedCalendarDaysInYear: yearUnlogged,
            unloggedCalendarDaysInYearThroughToday: yearUnloggedThroughToday,
            employerSlices: employerSlices,
            throughTodayEnd: todayEnd
        )
    }

    /// Inclusive end date for “through today” within `[rangeStart, rangeEnd]` (journal calendar). `nil` if today is before the range.
    static func throughTodayEnd(rangeStart: Date, rangeEnd: Date, calendar: Calendar) -> Date? {
        let start = ModelValidation.startOfDay(rangeStart, calendar: calendar)
        let end = ModelValidation.startOfDay(rangeEnd, calendar: calendar)
        let today = ModelValidation.startOfDay(Date(), calendar: calendar)
        let capped = min(today, end)
        guard capped >= start else { return nil }
        return capped
    }

    // MARK: - Core aggregation

    private static func journalDayMap(_ days: [JournalDay], calendar: Calendar) -> [Date: JournalDay] {
        var map: [Date: JournalDay] = [:]
        for d in days {
            guard let start = JournalCalendar.normalizedStartOfDay(dayKey: d.canonicalDayKey) else { continue }
            let key = ModelValidation.startOfDay(start, calendar: calendar)
            map[key] = d
        }
        return map
    }

    private static func aggregate(
        days: [Date],
        daysThroughToday: [Date],
        dayMap: [Date: JournalDay]
    ) -> ([YearLocationStat], unlogged: Int) {
        var workingByCountry: [String: Int] = [:]
        var nonWorkingByCountry: [String: Int] = [:]
        var workingToday: [String: Int] = [:]
        var nonWorkingToday: [String: Int] = [:]
        var unlogged = 0

        func countSegments(in dayList: [Date], working: inout [String: Int], nonWorking: inout [String: Int]) {
            for day in dayList {
                guard let journal = dayMap[day] else { continue }
                for seg in journal.segments {
                    let code = seg.countryCode
                    if seg.isWorking {
                        working[code, default: 0] += 1
                    } else {
                        nonWorking[code, default: 0] += 1
                    }
                }
            }
        }

        for day in days {
            if dayMap[day] == nil {
                unlogged += 1
            }
        }

        countSegments(in: days, working: &workingByCountry, nonWorking: &nonWorkingByCountry)
        countSegments(in: daysThroughToday, working: &workingToday, nonWorking: &nonWorkingToday)

        let codes = Set(workingByCountry.keys)
            .union(nonWorkingByCountry.keys)
            .union(workingToday.keys)
            .union(nonWorkingToday.keys)
            .sorted()
        let stats: [YearLocationStat] = codes.map { code in
            let w = workingByCountry[code, default: 0]
            let n = nonWorkingByCountry[code, default: 0]
            let wt = workingToday[code, default: 0]
            let nt = nonWorkingToday[code, default: 0]
            return YearLocationStat(
                countryCode: code,
                presenceUnits: w + n,
                working: w,
                nonWorking: n,
                presenceUnitsThroughToday: wt + nt,
                workingThroughToday: wt,
                nonWorkingThroughToday: nt
            )
        }
        return (stats, unlogged)
    }

    private static func aggregateUnloggedOnly(days: [Date], dayMap: [Date: JournalDay]) -> Int {
        days.reduce(0) { $0 + (dayMap[$1] == nil ? 1 : 0) }
    }

    // MARK: - Calendar ranges

    static func yearBounds(year: Int, calendar: Calendar) -> (Date, Date)? {
        var comps = DateComponents()
        comps.year = year
        comps.month = 1
        comps.day = 1
        guard let jan1 = calendar.date(from: comps) else { return nil }
        let start = ModelValidation.startOfDay(jan1, calendar: calendar)
        guard let dec31 = calendar.date(byAdding: DateComponents(year: 1, day: -1), to: start) else { return nil }
        let end = ModelValidation.startOfDay(dec31, calendar: calendar)
        return (start, end)
    }

    private static func clipPeriodToYear(
        period: EmployerPeriod,
        year: Int,
        calendar: Calendar
    ) -> (Date, Date)? {
        guard let (yStart, yEnd) = yearBounds(year: year, calendar: calendar) else { return nil }
        let (pStart, pEnd) = ModelValidation.normalizedInclusiveRange(
            start: period.startDate,
            end: period.endDate,
            calendar: calendar
        )
        let start = max(pStart, yStart)
        let end = min(pEnd, yEnd)
        guard start <= end else { return nil }
        return (start, end)
    }

    private static func inclusiveDayRange(from start: Date, through end: Date, calendar: Calendar) -> [Date] {
        var result: [Date] = []
        var d = ModelValidation.startOfDay(start, calendar: calendar)
        let endN = ModelValidation.startOfDay(end, calendar: calendar)
        while d <= endN {
            result.append(d)
            guard let next = calendar.date(byAdding: .day, value: 1, to: d) else { break }
            d = ModelValidation.startOfDay(next, calendar: calendar)
        }
        return result
    }
}

enum CountryDisplay {
    static func name(for code: String) -> String {
        Countries.common.first { $0.code == code }?.name ?? code
    }
}

extension YearLocationStat {
    func counts(for scope: YearCountScope) -> (presence: Int, working: Int, nonWorking: Int) {
        switch scope {
        case .throughToday:
            return (presenceUnitsThroughToday, workingThroughToday, nonWorkingThroughToday)
        case .fullYear:
            return (presenceUnits, working, nonWorking)
        }
    }
}
