//
//  StayLimitEvaluator.swift
//  Day Memory
//

import Foundation

/// One logged journal day, reduced to the countries present on it.
struct StayJournalDay: Equatable, Sendable {
    var dayKey: String
    var countryCodes: [String]
}

struct StayRuleIdentity: Equatable, Sendable {
    var countryCode: String
    var allowedDays: Int
    var periodDays: Int
}

enum StayTodayStatus: Equatable, Sendable {
    case inCountry
    case outside
    case unlogged
}

enum StayRunway: Equatable, Sendable {
    /// Today has no journal entry, so a continuous stay cannot be simulated.
    case needsTodayLogged
    /// Today is in the country and the window ending today is already over the limit.
    case alreadyOver(daysOver: Int)
    /// Today is in the country. `furtherDays` is how many days after today can still be spent there.
    case stayUntil(lastDayKey: String, furtherDays: Int)
    /// Today is outside the country. `stayDays` includes today.
    case enterUntil(lastDayKey: String, stayDays: Int)
    /// Entering today would put the window over the limit.
    case cannotEnter
    /// The allowance is at least as long as the window, so a continuous stay cannot exceed it.
    case unlimited
}

struct StayBreach: Equatable, Sendable, Identifiable {
    var firstDayKey: String
    var count: Int
    var peakDayKey: String
    var peakCount: Int
    /// Last day of this stay that is still inside the limit. Nil when the stay is over from its first day.
    var lastSafeDayKey: String?
    var id: String { firstDayKey }
}

struct StayLimitChartPoint: Equatable, Sendable, Identifiable {
    var dayKey: String
    var daysInWindow: Int
    var id: String { dayKey }
}

struct StayLimitReport: Equatable, Sendable {
    var countryCode: String
    var allowedDays: Int
    var periodDays: Int
    var todayKey: String
    var todayStatus: StayTodayStatus
    var usedInCurrentWindow: Int
    var windowStartKey: String
    var unloggedDaysInCurrentWindow: Int
    var runway: StayRunway
    var breaches: [StayBreach]
    /// Highest window count on a presence day after today, when the filled schedule stays inside the limit.
    var upcomingPeak: Int?
    var hasUpcomingPresence: Bool
    var chart: [StayLimitChartPoint]

    var roomInCurrentWindow: Int {
        max(0, allowedDays - usedInCurrentWindow)
    }
}

enum StayLimitEvaluator {
    static func clashes(_ candidate: StayRuleIdentity, with existing: [StayRuleIdentity]) -> Bool {
        let country = candidate.countryCode.uppercased()
        return existing.contains {
            $0.countryCode.uppercased() == country
                && $0.allowedDays == candidate.allowedDays
                && $0.periodDays == candidate.periodDays
        }
    }

    static func date(forDayKey key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        guard let date = components.date else { return nil }
        return calendar.startOfDay(for: date)
    }

    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func dayKey(byAdding days: Int, to key: String, calendar: Calendar) -> String? {
        guard let date = date(forDayKey: key, calendar: calendar),
              let shifted = calendar.date(byAdding: .day, value: days, to: date) else { return nil }
        return dayKey(for: shifted, calendar: calendar)
    }

    static func evaluate(
        countryCode: String,
        allowedDays: Int,
        periodDays: Int,
        days: [StayJournalDay],
        todayKey: String,
        calendar: Calendar
    ) -> StayLimitReport {
        let country = countryCode.uppercased()
        let allowed = max(1, allowedDays)
        let period = max(1, periodDays)
        let windowStartKey = dayKey(byAdding: -(period - 1), to: todayKey, calendar: calendar) ?? todayKey

        var presence = Set<String>()
        var logged = Set<String>()
        for day in days {
            guard !day.dayKey.isEmpty else { continue }
            logged.insert(day.dayKey)
            if day.countryCodes.contains(where: { $0.uppercased() == country }) {
                presence.insert(day.dayKey)
            }
        }

        let todayStatus: StayTodayStatus
        if !logged.contains(todayKey) {
            todayStatus = .unlogged
        } else if presence.contains(todayKey) {
            todayStatus = .inCountry
        } else {
            todayStatus = .outside
        }

        let unlogged = unloggedCount(
            from: windowStartKey,
            through: todayKey,
            logged: logged,
            calendar: calendar
        )

        guard let firstPresence = presence.min(), let lastPresence = presence.max() else {
            return StayLimitReport(
                countryCode: country,
                allowedDays: allowed,
                periodDays: period,
                todayKey: todayKey,
                todayStatus: todayStatus,
                usedInCurrentWindow: 0,
                windowStartKey: windowStartKey,
                unloggedDaysInCurrentWindow: unlogged,
                runway: runwayWithoutPresence(
                    todayKey: todayKey,
                    todayStatus: todayStatus,
                    allowed: allowed,
                    period: period,
                    calendar: calendar
                ),
                breaches: [],
                upcomingPeak: nil,
                hasUpcomingPresence: false,
                chart: []
            )
        }

        let plotStart = min(todayKey, firstPresence)
        let plotEnd = max(todayKey, lastPresence)
        guard let origin = dayKey(byAdding: -(period - 1), to: plotStart, calendar: calendar),
              let indexed = WindowIndex(
                originKey: origin,
                endKey: plotEnd,
                presence: presence,
                period: period,
                calendar: calendar
              ) else {
            return StayLimitReport(
                countryCode: country,
                allowedDays: allowed,
                periodDays: period,
                todayKey: todayKey,
                todayStatus: todayStatus,
                usedInCurrentWindow: 0,
                windowStartKey: windowStartKey,
                unloggedDaysInCurrentWindow: unlogged,
                runway: .needsTodayLogged,
                breaches: [],
                upcomingPeak: nil,
                hasUpcomingPresence: false,
                chart: []
            )
        }

        let usedToday = indexed.used(on: todayKey)
        let breaches = breachEpisodes(presence: presence, allowed: allowed, index: indexed, calendar: calendar)
        let upcomingKeys = presence.filter { $0 > todayKey }
        let upcomingPeak = breaches.isEmpty ? upcomingKeys.compactMap { indexed.used(on: $0) }.max() : nil

        return StayLimitReport(
            countryCode: country,
            allowedDays: allowed,
            periodDays: period,
            todayKey: todayKey,
            todayStatus: todayStatus,
            usedInCurrentWindow: usedToday,
            windowStartKey: windowStartKey,
            unloggedDaysInCurrentWindow: unlogged,
            runway: runway(
                todayKey: todayKey,
                todayStatus: todayStatus,
                presence: presence,
                allowed: allowed,
                period: period,
                calendar: calendar
            ),
            breaches: breaches,
            upcomingPeak: upcomingPeak,
            hasUpcomingPresence: !upcomingKeys.isEmpty,
            chart: indexed.chart(from: plotStart, through: plotEnd, todayKey: todayKey, breachKeys: breaches.map(\.firstDayKey))
        )
    }

    private static func runwayWithoutPresence(
        todayKey: String,
        todayStatus: StayTodayStatus,
        allowed: Int,
        period: Int,
        calendar: Calendar
    ) -> StayRunway {
        if allowed >= period { return .unlimited }
        if todayStatus == .unlogged { return .needsTodayLogged }
        if todayStatus == .inCountry {
            let further = max(0, allowed - 1)
            let last = dayKey(byAdding: further, to: todayKey, calendar: calendar) ?? todayKey
            return .stayUntil(lastDayKey: last, furtherDays: further)
        }
        let last = dayKey(byAdding: allowed - 1, to: todayKey, calendar: calendar) ?? todayKey
        return .enterUntil(lastDayKey: last, stayDays: allowed)
    }

    /// Continuous stay from today, using presence on or before today and ignoring later journal entries.
    private static func runway(
        todayKey: String,
        todayStatus: StayTodayStatus,
        presence: Set<String>,
        allowed: Int,
        period: Int,
        calendar: Calendar
    ) -> StayRunway {
        if allowed >= period { return .unlimited }
        if todayStatus == .unlogged { return .needsTodayLogged }

        var simulated = presence.filter { $0 <= todayKey }
        let usedToday = used(ending: todayKey, presence: simulated, period: period, calendar: calendar)

        if todayStatus == .inCountry {
            if usedToday > allowed {
                return .alreadyOver(daysOver: usedToday - allowed)
            }
            guard let tomorrow = dayKey(byAdding: 1, to: todayKey, calendar: calendar) else {
                return .stayUntil(lastDayKey: todayKey, furtherDays: 0)
            }
            let extended = extend(
                from: tomorrow,
                presence: &simulated,
                allowed: allowed,
                period: period,
                calendar: calendar
            )
            return .stayUntil(lastDayKey: extended.last ?? todayKey, furtherDays: extended.added)
        }

        let extended = extend(
            from: todayKey,
            presence: &simulated,
            allowed: allowed,
            period: period,
            calendar: calendar
        )
        guard let last = extended.last, extended.added > 0 else { return .cannotEnter }
        return .enterUntil(lastDayKey: last, stayDays: extended.added)
    }

    /// Adds consecutive days until the next one would exceed the allowance.
    /// A window holds at most `period` days, and prior days still inside it age out within one period,
    /// so the legal run cannot be longer than `period + allowed`.
    private static func extend(
        from startKey: String,
        presence: inout Set<String>,
        allowed: Int,
        period: Int,
        calendar: Calendar
    ) -> (last: String?, added: Int) {
        let cap = period + allowed + 1
        var day: String? = startKey
        var added = 0
        var last: String?
        while let current = day, added < cap {
            let prospective = used(ending: current, presence: presence, period: period, calendar: calendar)
                + (presence.contains(current) ? 0 : 1)
            if prospective > allowed { break }
            presence.insert(current)
            last = current
            added += 1
            day = dayKey(byAdding: 1, to: current, calendar: calendar)
        }
        return (last, added)
    }

    private static func used(ending key: String, presence: Set<String>, period: Int, calendar: Calendar) -> Int {
        guard period > 0, let end = date(forDayKey: key, calendar: calendar) else { return 0 }
        var count = 0
        for offset in 0..<period {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: end) else { continue }
            let dayKey = dayKey(for: calendar.startOfDay(for: day), calendar: calendar)
            if presence.contains(dayKey) { count += 1 }
        }
        return count
    }

    private static func unloggedCount(
        from startKey: String,
        through endKey: String,
        logged: Set<String>,
        calendar: Calendar
    ) -> Int {
        guard let start = date(forDayKey: startKey, calendar: calendar),
              let end = date(forDayKey: endKey, calendar: calendar),
              start <= end else { return 0 }
        var count = 0
        var day = start
        while day <= end {
            let key = dayKey(for: day, calendar: calendar)
            if !logged.contains(key) { count += 1 }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = calendar.startOfDay(for: next)
        }
        return count
    }

    private static func breachEpisodes(
        presence: Set<String>,
        allowed: Int,
        index: WindowIndex,
        calendar: Calendar
    ) -> [StayBreach] {
        let sorted = presence.sorted()
        var runs: [[String]] = []
        for key in sorted {
            if let last = runs.last?.last,
               dayKey(byAdding: 1, to: last, calendar: calendar) == key {
                runs[runs.count - 1].append(key)
            } else {
                runs.append([key])
            }
        }

        var breaches: [StayBreach] = []
        for run in runs {
            let counts = run.map { ($0, index.used(on: $0)) }
            guard let firstIndex = counts.firstIndex(where: { $0.1 > allowed }) else { continue }
            let over = counts[firstIndex...]
            guard let peak = over.max(by: { $0.1 < $1.1 }) else { continue }
            breaches.append(
                StayBreach(
                    firstDayKey: counts[firstIndex].0,
                    count: counts[firstIndex].1,
                    peakDayKey: peak.0,
                    peakCount: peak.1,
                    lastSafeDayKey: firstIndex > 0 ? counts[firstIndex - 1].0 : nil
                )
            )
        }
        return breaches
    }
}

private struct WindowIndex {
    let keys: [String]
    let prefix: [Int]
    let period: Int
    let indexByKey: [String: Int]

    init?(originKey: String, endKey: String, presence: Set<String>, period: Int, calendar: Calendar) {
        guard let origin = StayLimitEvaluator.date(forDayKey: originKey, calendar: calendar),
              let end = StayLimitEvaluator.date(forDayKey: endKey, calendar: calendar),
              origin <= end else { return nil }

        var keys: [String] = []
        var day = origin
        while day <= end {
            keys.append(StayLimitEvaluator.dayKey(for: day, calendar: calendar))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            day = calendar.startOfDay(for: next)
        }

        var prefix = [Int](repeating: 0, count: keys.count + 1)
        var indexByKey: [String: Int] = [:]
        indexByKey.reserveCapacity(keys.count)
        for (offset, key) in keys.enumerated() {
            prefix[offset + 1] = prefix[offset] + (presence.contains(key) ? 1 : 0)
            indexByKey[key] = offset
        }

        self.keys = keys
        self.prefix = prefix
        self.period = period
        self.indexByKey = indexByKey
    }

    func used(on key: String) -> Int {
        guard let index = indexByKey[key] else { return 0 }
        let start = max(0, index - (period - 1))
        return prefix[index + 1] - prefix[start]
    }

    func chart(from startKey: String, through endKey: String, todayKey: String, breachKeys: [String]) -> [StayLimitChartPoint] {
        guard let start = indexByKey[startKey], let end = indexByKey[endKey], start <= end else { return [] }
        let span = end - start + 1
        var chosen = Set<Int>()
        if span <= 420 {
            chosen.formUnion(start...end)
        } else {
            let stride = max(1, Int((Double(span) / 360).rounded(.up)))
            var index = start
            while index <= end {
                chosen.insert(index)
                index += stride
            }
            chosen.insert(end)
        }
        if let today = indexByKey[todayKey] { chosen.insert(today) }
        for key in breachKeys {
            if let index = indexByKey[key] { chosen.insert(index) }
        }
        return chosen.sorted().map { offset in
            StayLimitChartPoint(dayKey: keys[offset], daysInWindow: used(on: keys[offset]))
        }
    }
}
