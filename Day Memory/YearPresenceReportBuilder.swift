//
//  YearPresenceReportBuilder.swift
//  Day Memory
//

import Foundation

struct YearPresenceSegmentRow: Hashable, Sendable {
    var countryCode: String
    var countryName: String
    var isWorking: Bool
    var sortOrder: Int

    var workingLabel: String {
        isWorking ? "Working" : "Not working"
    }

    var locationLabel: String {
        "\(countryName) (\(countryCode))"
    }
}

struct YearPresenceDayRow: Hashable, Sendable {
    var dayKey: String
    var date: Date
    var dayOfMonth: Int
    var weekdayShort: String
    var isLogged: Bool
    var segments: [YearPresenceSegmentRow]
    var nonWorkingReason: DayNonWorkingReason
    var tripSummary: String?

    var isSplitDay: Bool {
        segments.count >= 2
    }

    var leaveLabel: String {
        switch nonWorkingReason {
        case .none:
            return "—"
        case .annualLeave:
            return "Annual leave"
        case .publicHoliday:
            return "Public holiday"
        }
    }

    var dateLabel: String {
        "\(dayOfMonth) \(weekdayShort)"
    }

    var presenceSummary: String {
        guard isLogged else { return "Not logged" }
        return segments.map(\.locationLabel).joined(separator: " / ")
    }

    var workingSummary: String {
        guard isLogged else { return "—" }
        if segments.count == 1, let only = segments.first {
            return only.workingLabel
        }
        return segments
            .map { "\($0.countryCode): \($0.workingLabel)" }
            .joined(separator: " / ")
    }
}

struct YearPresenceMonthSection: Hashable, Sendable {
    var month: Int
    var monthName: String
    var rows: [YearPresenceDayRow]
}

struct YearPresenceReport: Hashable, Sendable {
    var year: Int
    var generatedAt: Date
    var journalTimeZoneIdentifier: String
    var months: [YearPresenceMonthSection]
    var loggedDays: Int
    var unloggedDays: Int
    var splitTravelDays: Int
}

enum YearPresenceReportBuilder {
    static func build(
        year: Int,
        journalDays: [JournalDay],
        calendar: Calendar = JournalCalendar.civil,
        generatedAt: Date = Date()
    ) -> YearPresenceReport {
        guard let (yearStart, yearEnd) = YearOverviewAggregator.yearBounds(year: year, calendar: calendar) else {
            return YearPresenceReport(
                year: year,
                generatedAt: generatedAt,
                journalTimeZoneIdentifier: calendar.timeZone.identifier,
                months: [],
                loggedDays: 0,
                unloggedDays: 0,
                splitTravelDays: 0
            )
        }

        let dayMap = journalDayMap(journalDays, calendar: calendar)
        let allDays = inclusiveDayRange(from: yearStart, through: yearEnd, calendar: calendar)

        var monthBuckets: [Int: [YearPresenceDayRow]] = [:]
        var logged = 0
        var unlogged = 0
        var splitDays = 0

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.calendar = calendar
        weekdayFormatter.timeZone = calendar.timeZone
        weekdayFormatter.locale = Locale.current
        weekdayFormatter.dateFormat = "EEE"

        let monthFormatter = DateFormatter()
        monthFormatter.calendar = calendar
        monthFormatter.timeZone = calendar.timeZone
        monthFormatter.locale = Locale.current
        monthFormatter.dateFormat = "MMMM"

        for day in allDays {
            let month = calendar.component(.month, from: day)
            let dayOfMonth = calendar.component(.day, from: day)
            let weekday = weekdayFormatter.string(from: day)
            let dayKey = JournalCalendar.dayKey(for: day)

            if let journal = dayMap[day] {
                logged += 1
                let segments = journal.orderedSegments
                    .map { seg in
                        YearPresenceSegmentRow(
                            countryCode: seg.countryCode.uppercased(),
                            countryName: CountryDisplay.name(for: seg.countryCode),
                            isWorking: seg.isWorking,
                            sortOrder: seg.sortOrder
                        )
                    }
                if segments.count >= 2 {
                    splitDays += 1
                }
                let row = YearPresenceDayRow(
                    dayKey: dayKey,
                    date: day,
                    dayOfMonth: dayOfMonth,
                    weekdayShort: weekday,
                    isLogged: true,
                    segments: segments,
                    nonWorkingReason: journal.nonWorkingReason,
                    tripSummary: tripSummary(for: journal.trip)
                )
                monthBuckets[month, default: []].append(row)
            } else {
                unlogged += 1
                let row = YearPresenceDayRow(
                    dayKey: dayKey,
                    date: day,
                    dayOfMonth: dayOfMonth,
                    weekdayShort: weekday,
                    isLogged: false,
                    segments: [],
                    nonWorkingReason: .none,
                    tripSummary: nil
                )
                monthBuckets[month, default: []].append(row)
            }
        }

        let months: [YearPresenceMonthSection] = (1...12).compactMap { month in
            guard let rows = monthBuckets[month], !rows.isEmpty else { return nil }
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.day = 1
            let monthDate = calendar.date(from: comps) ?? rows[0].date
            let name = monthFormatter.string(from: monthDate)
            return YearPresenceMonthSection(month: month, monthName: name, rows: rows)
        }

        return YearPresenceReport(
            year: year,
            generatedAt: generatedAt,
            journalTimeZoneIdentifier: calendar.timeZone.identifier,
            months: months,
            loggedDays: logged,
            unloggedDays: unlogged,
            splitTravelDays: splitDays
        )
    }

    // MARK: - Helpers

    private static func journalDayMap(_ days: [JournalDay], calendar: Calendar) -> [Date: JournalDay] {
        var map: [Date: JournalDay] = [:]
        for d in days {
            guard let start = JournalCalendar.normalizedStartOfDay(dayKey: d.canonicalDayKey) else { continue }
            let key = ModelValidation.startOfDay(start, calendar: calendar)
            map[key] = d
        }
        return map
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

    static func tripSummary(for trip: Trip?) -> String? {
        guard let trip else { return nil }

        let flight = trip.flightDesignator?.trimmingCharacters(in: .whitespacesAndNewlines)
        let depCode = trip.departureCountryCode?.uppercased()
        let arrCode = trip.arrivalCountryCode?.uppercased()

        var parts: [String] = []
        if let flight, !flight.isEmpty {
            parts.append(flight)
        }

        if let depCode, let arrCode, ModelValidation.isValidCountryCode(depCode), ModelValidation.isValidCountryCode(arrCode) {
            let route = "\(CountryDisplay.name(for: depCode)) (\(depCode)) → \(CountryDisplay.name(for: arrCode)) (\(arrCode))"
            parts.append(route)
        } else if let depCode, ModelValidation.isValidCountryCode(depCode) {
            parts.append("From \(CountryDisplay.name(for: depCode)) (\(depCode))")
        } else if let arrCode, ModelValidation.isValidCountryCode(arrCode) {
            parts.append("To \(CountryDisplay.name(for: arrCode)) (\(arrCode))")
        }

        let ticketCount = trip.orderedTicketImages.count
        if ticketCount > 0 {
            parts.append("\(ticketCount) ticket photo\(ticketCount == 1 ? "" : "s")")
        }

        let summary = parts.joined(separator: " · ")
        return summary.isEmpty ? nil : summary
    }
}
