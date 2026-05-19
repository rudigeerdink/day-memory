//
//  Day_MemoryTests.swift
//  Day MemoryTests
//
//  Created by MotionSpace - Development on 20/04/2026.
//

import Testing
import SwiftData
import Foundation
@testable import Day_Memory

struct Day_MemoryTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        // Swift Testing Documentation
        // https://developer.apple.com/documentation/testing
    }

    @MainActor
    @Test func backupRoundTripPreservesLeaveStatus() throws {
        let schema = Schema([
            EmployerPeriod.self,
            JournalDay.self,
            PresenceSegment.self,
            Trip.self,
            TripTicketImage.self,
        ])
        let sourceContainer = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let sourceContext = sourceContainer.mainContext

        let tzKey = JournalCalendar.timeZonePreferenceKey
        let previousTZ = UserDefaults.standard.string(forKey: tzKey)
        defer {
            if let previousTZ {
                UserDefaults.standard.set(previousTZ, forKey: tzKey)
            } else {
                UserDefaults.standard.removeObject(forKey: tzKey)
            }
        }
        UserDefaults.standard.set("UTC", forKey: tzKey)
        JournalCalendar.ensurePreferenceInitialized()
        let cal = JournalCalendar.civil
        let base = ModelValidation.startOfDay(Date(), calendar: cal)
        let d1 = base
        let d2 = cal.date(byAdding: .day, value: 1, to: base)!
        let d3 = cal.date(byAdding: .day, value: 2, to: base)!

        let k1 = JournalCalendar.dayKey(for: d1)
        let k2 = JournalCalendar.dayKey(for: d2)
        let k3 = JournalCalendar.dayKey(for: d3)
        let a1 = JournalCalendar.sortAnchor(dayKey: k1)!
        let a2 = JournalCalendar.sortAnchor(dayKey: k2)!
        let a3 = JournalCalendar.sortAnchor(dayKey: k3)!

        let j1 = JournalDay(day: a1, dayKey: k1, nonWorkingReasonRawValue: DayNonWorkingReason.annualLeave.rawValue)
        let j2 = JournalDay(day: a2, dayKey: k2, nonWorkingReasonRawValue: DayNonWorkingReason.publicHoliday.rawValue)
        let j3 = JournalDay(day: a3, dayKey: k3, nonWorkingReasonRawValue: nil)
        sourceContext.insert(j1)
        sourceContext.insert(j2)
        sourceContext.insert(j3)

        let s1 = PresenceSegment(countryCode: "NL", isWorking: false, sortOrder: 0, journalDay: j1)
        let s2 = PresenceSegment(countryCode: "AE", isWorking: false, sortOrder: 0, journalDay: j2)
        let s3 = PresenceSegment(countryCode: "NL", isWorking: true, sortOrder: 0, journalDay: j3)
        j1.segments = [s1]
        j2.segments = [s2]
        j3.segments = [s3]
        sourceContext.insert(s1)
        sourceContext.insert(s2)
        sourceContext.insert(s3)

        try sourceContext.save()

        let data = try DayMemoryBackupService.exportData(modelContext: sourceContext)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(DayMemoryBackupEnvelope.self, from: data)
        let exportedById: [UUID: String] = Dictionary(
            uniqueKeysWithValues: envelope.journalDays.compactMap { day in
                guard let reason = day.nonWorkingReason else { return nil }
                return (day.id, reason)
            }
        )
        #expect(exportedById[j1.id] == DayNonWorkingReason.annualLeave.rawValue)
        #expect(exportedById[j2.id] == DayNonWorkingReason.publicHoliday.rawValue)
        #expect(exportedById[j3.id] == nil)

        let restoreContainer = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let restoreContext = restoreContainer.mainContext
        try DayMemoryBackupService.importData(data, modelContext: restoreContext)
        let all = try restoreContext.fetch(FetchDescriptor<JournalDay>(sortBy: [SortDescriptor(\.day)]))
        #expect(all.count == 3)
        var byId: [UUID: DayNonWorkingReason] = [:]
        for j in all {
            byId[j.id] = j.nonWorkingReason
        }
        #expect(byId[j1.id] == DayNonWorkingReason.annualLeave)
        #expect(byId[j2.id] == DayNonWorkingReason.publicHoliday)
        #expect(byId[j3.id] == DayNonWorkingReason.none)
    }

}
