//
//  YearOverviewAggregator.swift
//  Day Memory
//

import Foundation

/// One row per **presence country**: each `JournalDay` segment counts as one unit
/// (a split travel day contributes one unit to each of two countries).
struct YearLocationStat: Hashable, Sendable {
    var countryCode: String
    /// Segment count (= working + nonWorking).
    var presenceUnits: Int
    var working: Int
    var nonWorking: Int
}

struct YearEmployerSlice: Identifiable, Hashable, Sendable {
    var id: UUID
    var companyName: String
    var employerCountryCode: String
    var clippedRangeStart: Date
    var clippedRangeEnd: Date
    var byPresenceCountry: [YearLocationStat]
    /// Calendar days in the clipped range with no journal entry.
    var unloggedCalendarDays: Int
}

struct YearOverviewReport: Hashable, Sendable {
    var year: Int
    var yearTotalsByCountry: [YearLocationStat]
    var unloggedCalendarDaysInYear: Int
    var employerSlices: [YearEmployerSlice]
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
            return YearOverviewReport(year: year, yearTotalsByCountry: [], unloggedCalendarDaysInYear: 0, employerSlices: [])
        }

        let yearDayList = inclusiveDayRange(from: yearStart, through: yearEnd, calendar: calendar)
        let (yearStats, yearUnlogged) = aggregate(days: yearDayList, dayMap: dayMap)

        let employerSlices: [YearEmployerSlice] = employerPeriods.compactMap { period in
            guard let (clipStart, clipEnd) = clipPeriodToYear(period: period, year: year, calendar: calendar) else {
                return nil
            }
            let days = inclusiveDayRange(from: clipStart, through: clipEnd, calendar: calendar)
            let (stats, unlogged) = aggregate(days: days, dayMap: dayMap)
            return YearEmployerSlice(
                id: period.id,
                companyName: period.companyName,
                employerCountryCode: period.employerCountryCode,
                clippedRangeStart: clipStart,
                clippedRangeEnd: clipEnd,
                byPresenceCountry: stats,
                unloggedCalendarDays: unlogged
            )
        }
        .sorted { $0.clippedRangeStart < $1.clippedRangeStart }

        return YearOverviewReport(
            year: year,
            yearTotalsByCountry: yearStats,
            unloggedCalendarDaysInYear: yearUnlogged,
            employerSlices: employerSlices
        )
    }

    // MARK: - Core aggregation

    private static func journalDayMap(_ days: [JournalDay], calendar: Calendar) -> [Date: JournalDay] {
        var map: [Date: JournalDay] = [:]
        for d in days {
            let key = ModelValidation.startOfDay(d.day, calendar: calendar)
            map[key] = d
        }
        return map
    }

    private static func aggregate(
        days: [Date],
        dayMap: [Date: JournalDay]
    ) -> ([YearLocationStat], unlogged: Int) {
        var workingByCountry: [String: Int] = [:]
        var nonWorkingByCountry: [String: Int] = [:]
        var unlogged = 0

        for day in days {
            guard let journal = dayMap[day] else {
                unlogged += 1
                continue
            }
            for seg in journal.segments {
                let code = seg.countryCode
                if seg.isWorking {
                    workingByCountry[code, default: 0] += 1
                } else {
                    nonWorkingByCountry[code, default: 0] += 1
                }
            }
        }

        let codes = Set(workingByCountry.keys).union(nonWorkingByCountry.keys).sorted()
        let stats: [YearLocationStat] = codes.map { code in
            let w = workingByCountry[code, default: 0]
            let n = nonWorkingByCountry[code, default: 0]
            return YearLocationStat(countryCode: code, presenceUnits: w + n, working: w, nonWorking: n)
        }
        return (stats, unlogged)
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
