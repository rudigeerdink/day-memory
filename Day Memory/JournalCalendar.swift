//
//  JournalCalendar.swift
//  Day Memory
//

import Foundation
import SwiftData

/// Calendar logic for journal **civil dates** (year/month/day) independent of the device location.
/// The user-chosen timezone (defaults once to the device timezone at first launch) defines what
/// “May 4” means; entries stay on that date when traveling.
enum JournalCalendar {
    static let timeZonePreferenceKey = "journal.civilTimeZoneIdentifier"

    /// Call early in app startup so the preference exists before migration / UI.
    static func ensurePreferenceInitialized() {
        if UserDefaults.standard.string(forKey: timeZonePreferenceKey) == nil {
            UserDefaults.standard.set(TimeZone.current.identifier, forKey: timeZonePreferenceKey)
        }
    }

    static var civilTimeZone: TimeZone {
        let id = UserDefaults.standard.string(forKey: timeZonePreferenceKey) ?? TimeZone.current.identifier
        return TimeZone(identifier: id) ?? .current
    }

    /// User-facing calendar: current locale + fixed civil timezone (not the traveling device zone).
    static var civil: Calendar {
        var c = Calendar.current
        c.timeZone = civilTimeZone
        return c
    }

    static func setCivilTimeZone(identifier: String, modelContext: ModelContext) throws {
        UserDefaults.standard.set(identifier, forKey: timeZonePreferenceKey)
        try reanchorAllJournalDays(modelContext: modelContext)
    }

    // MARK: - Day keys (canonical identity)

    static func dayKey(year: Int, month: Int, day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Civil `yyyy-MM-dd` for an instant, interpreted in the journal timezone.
    static func dayKey(for date: Date) -> String {
        let c = civil
        let comps = c.dateComponents([.year, .month, .day], from: date)
        return dayKey(year: comps.year!, month: comps.month!, day: comps.day!)
    }

    /// Stable sort value: **noon** on that civil day in the journal zone (avoids DST midnight quirks).
    static func sortAnchor(dayKey: String) -> Date? {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var dc = DateComponents()
        dc.year = parts[0]
        dc.month = parts[1]
        dc.day = parts[2]
        dc.hour = 12
        dc.minute = 0
        dc.second = 0
        return civil.date(from: dc)
    }

    static func normalizedStartOfDay(dayKey: String) -> Date? {
        guard let anchor = sortAnchor(dayKey: dayKey) else { return nil }
        return ModelValidation.startOfDay(anchor, calendar: civil)
    }

    // MARK: - Migration / reanchor

    /// Fills `dayKey` from legacy `day` values and normalizes `day` to the sort anchor.
    static func migrateJournalDayKeys(modelContext: ModelContext) throws {
        let desc = FetchDescriptor<JournalDay>()
        let all = try modelContext.fetch(desc)
        var changed = false
        for jd in all {
            if let existing = jd.dayKey, !existing.isEmpty { continue }
            let key = dayKey(for: jd.day)
            jd.dayKey = key
            if let a = sortAnchor(dayKey: key) {
                jd.day = a
            }
            changed = true
        }
        if changed {
            try modelContext.save()
        }
    }

    /// After the user changes the journal timezone, move sort anchors (instants) — `dayKey` strings stay the same.
    static func reanchorAllJournalDays(modelContext: ModelContext) throws {
        let desc = FetchDescriptor<JournalDay>()
        let all = try modelContext.fetch(desc)
        for jd in all {
            guard let key = jd.dayKey, !key.isEmpty else { continue }
            if let a = sortAnchor(dayKey: key) {
                jd.day = a
            }
        }
        try modelContext.save()
    }
}
