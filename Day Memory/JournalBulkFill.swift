//
//  JournalBulkFill.swift
//  Day Memory
//

import Foundation
import SwiftData

enum JournalBulkFill {
    static func daysInWeek(containing date: Date, calendar: Calendar) -> [Date] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return [] }
        var result: [Date] = []
        var d = interval.start
        while d < interval.end {
            result.append(ModelValidation.startOfDay(d, calendar: calendar))
            guard let next = calendar.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return result.sorted()
    }

    /// Fills **empty** days in the week with one segment each; preserves an existing linked trip.
    /// Days that already have a journal entry are **skipped** so manually set countries (e.g. travel on Monday)
    /// are not overwritten by the previous day’s country from the same week.
    static func applyWeekDefaults(
        weekContaining selectedDay: Date,
        calendar: Calendar,
        fallbackCountry: CountryCode?,
        context: ModelContext
    ) throws {
        let week = daysInWeek(containing: selectedDay, calendar: calendar)
        guard !week.isEmpty else { return }

        let allDescriptor = FetchDescriptor<JournalDay>(sortBy: [SortDescriptor(\.day)])

        for day in week {
            let normalized = ModelValidation.startOfDay(day, calendar: calendar)
            let existingFD = FetchDescriptor<JournalDay>(predicate: #Predicate { journalDay in
                journalDay.day == normalized
            })
            if try context.fetch(existingFD).first != nil {
                continue
            }

            let allDays = try context.fetch(allDescriptor)
            let snapshots = allDays.map { $0.snapshotForValidation() }

            let country =
                ModelValidation.lastKnownCountry(
                    before: day,
                    priorRecords: snapshots,
                    calendar: calendar,
                    fallback: fallbackCountry
                ) ?? fallbackCountry ?? "NL"

            let working = !calendar.isDateInWeekend(day)
            try upsertSingleSegmentDay(
                day: day,
                country: country.uppercased(),
                isWorking: working,
                calendar: calendar,
                context: context
            )
        }
    }

    private static func upsertSingleSegmentDay(
        day: Date,
        country: CountryCode,
        isWorking: Bool,
        calendar: Calendar,
        context: ModelContext
    ) throws {
        let normalized = ModelValidation.startOfDay(day, calendar: calendar)
        let fd = FetchDescriptor<JournalDay>(predicate: #Predicate { journalDay in
            journalDay.day == normalized
        })
        let existing = try context.fetch(fd).first

        if let existing {
            let trip = existing.trip
            for seg in existing.segments {
                context.delete(seg)
            }
            existing.segments.removeAll()
            let seg = PresenceSegment(countryCode: country, isWorking: isWorking, sortOrder: 0, journalDay: existing)
            existing.segments.append(seg)
            existing.trip = trip
            context.insert(seg)
        } else {
            let jd = JournalDay(day: normalized, segments: [], trip: nil)
            let seg = PresenceSegment(countryCode: country, isWorking: isWorking, sortOrder: 0, journalDay: jd)
            jd.segments.append(seg)
            context.insert(jd)
            context.insert(seg)
        }
    }
}
