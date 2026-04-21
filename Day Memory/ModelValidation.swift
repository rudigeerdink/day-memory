//
//  ModelValidation.swift
//  Day Memory
//

import Foundation

enum ModelValidation {}

// MARK: - Calendar helpers

extension ModelValidation {
    static func startOfDay(_ date: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: date)
    }

    /// Inclusive range of calendar days: [normalizedStart, normalizedEnd].
    static func normalizedInclusiveRange(start: Date, end: Date, calendar: Calendar) -> (Date, Date) {
        let s = startOfDay(start, calendar: calendar)
        let e = startOfDay(end, calendar: calendar)
        return s <= e ? (s, e) : (e, s)
    }

    static func employerPeriodsOverlap(
        _ aStart: Date,
        _ aEnd: Date,
        _ bStart: Date,
        _ bEnd: Date,
        calendar: Calendar
    ) -> Bool {
        let (as_, ae) = normalizedInclusiveRange(start: aStart, end: aEnd, calendar: calendar)
        let (bs, be) = normalizedInclusiveRange(start: bStart, end: bEnd, calendar: calendar)
        return as_ <= be && bs <= ae
    }

    /// True iff the two inclusive day ranges share at least one calendar day.
    static func employerPeriodsOverlap(
        _ a: EmployerPeriod,
        _ b: EmployerPeriod,
        calendar: Calendar
    ) -> Bool {
        employerPeriodsOverlap(
            a.startDate,
            a.endDate,
            b.startDate,
            b.endDate,
            calendar: calendar
        )
    }

    /// Returns nil if valid, or any two periods that share a day (ranges are inclusive).
    static func firstOverlappingEmployerPair(
        periods: [EmployerPeriod],
        calendar: Calendar
    ) -> (EmployerPeriod, EmployerPeriod)? {
        for i in periods.indices {
            for j in periods.indices where j > i {
                if employerPeriodsOverlap(periods[i], periods[j], calendar: calendar) {
                    return (periods[i], periods[j])
                }
            }
        }
        return nil
    }

    /// Use this before inserting a **new** model instance — avoids building a temporary `EmployerPeriod` just for overlap math (which can confuse SwiftData).
    static func employerRangeOverlapsPersistedPeriods(
        normalizedStart: Date,
        normalizedEnd: Date,
        persistedPeriods: [EmployerPeriod],
        excludingEmployerId: UUID?,
        calendar: Calendar
    ) -> Bool {
        let (cs, ce) = normalizedInclusiveRange(start: normalizedStart, end: normalizedEnd, calendar: calendar)
        for p in persistedPeriods {
            if let ex = excludingEmployerId, p.id == ex { continue }
            let (ps, pe) = normalizedInclusiveRange(start: p.startDate, end: p.endDate, calendar: calendar)
            if cs <= pe && ps <= ce {
                return true
            }
        }
        return false
    }

    static func isValidCountryCode(_ code: CountryCode) -> Bool {
        code.count == 2 && code.uppercased() == code && code.allSatisfy { $0.isLetter }
    }
}

// MARK: - Day segments

extension ModelValidation {
    enum DayRecordError: Equatable, Sendable, LocalizedError {
        case noSegments
        case invalidCountryCode
        case sortOrderNotUnique
        case sortOrderNotContiguousFromZero
        case splitDaySameCountry
        case tooManySegmentsForV1(Int)

        var errorDescription: String? {
            switch self {
            case .noSegments:
                "Add at least one country for this day."
            case .invalidCountryCode:
                "Use a two-letter country code (for example NL or DE)."
            case .sortOrderNotUnique:
                "Travel segments are out of order. Try toggling split-day off and on."
            case .sortOrderNotContiguousFromZero:
                "Travel segments are out of order."
            case .splitDaySameCountry:
                "A split travel day needs two different countries."
            case .tooManySegmentsForV1(let count):
                "At most two countries per day (got \(count))."
            }
        }
    }

    /// Enforces: ≥1 segment; unique contiguous `sortOrder` from 0; if exactly two segments, countries must differ.
    static func validate(dayRecord: DayRecordSnapshot) -> DayRecordError? {
        if dayRecord.segments.isEmpty { return .noSegments }
        let maxSegments = 2
        if dayRecord.segments.count > maxSegments { return .tooManySegmentsForV1(dayRecord.segments.count) }

        let orders = dayRecord.segments.map(\.sortOrder).sorted()
        if Set(orders).count != orders.count { return .sortOrderNotUnique }
        if orders.first != 0 || orders.last != orders.count - 1 {
            return .sortOrderNotContiguousFromZero
        }

        if dayRecord.segments.count == 2 {
            let sortedSegs = dayRecord.segments.sorted { $0.sortOrder < $1.sortOrder }
            if sortedSegs[0].countryCode == sortedSegs[1].countryCode {
                return .splitDaySameCountry
            }
        }

        for seg in dayRecord.segments where !isValidCountryCode(seg.countryCode) {
            return .invalidCountryCode
        }

        return nil
    }
}

// MARK: - Bulk fill: last known country

extension ModelValidation {
    /// Walks **backwards** from `day` (exclusive) through `priorRecords` (unsorted; sorted internally by day)
    /// and returns the country of the first segment with the lowest `sortOrder` on the latest prior day.
    static func lastKnownCountry(
        before day: Date,
        priorRecords: [DayRecordSnapshot],
        calendar: Calendar,
        fallback: CountryCode?
    ) -> CountryCode? {
        let anchor = startOfDay(day, calendar: calendar)
        let sorted = priorRecords
            .map { r -> (Date, DayRecordSnapshot) in (startOfDay(r.day, calendar: calendar), r) }
            .filter { $0.0 < anchor }
            .sorted { $0.0 < $1.0 }

        guard let last = sorted.last else { return fallback }
        let firstSeg = last.1.segments.min(by: { $0.sortOrder < $1.sortOrder })
        return firstSeg?.countryCode ?? fallback
    }
}
