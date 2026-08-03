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

@Suite(.serialized)
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

    @MainActor
    @Test func yearPresenceReportIncludesSplitDaysAndTravel() throws {
        let schema = Schema([
            EmployerPeriod.self,
            JournalDay.self,
            PresenceSegment.self,
            Trip.self,
            TripTicketImage.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext

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

        var comps = DateComponents()
        comps.year = 2025
        comps.month = 6
        comps.day = 10
        let dayDate = cal.date(from: comps)!
        let dayKey = JournalCalendar.dayKey(for: dayDate)
        let anchor = JournalCalendar.sortAnchor(dayKey: dayKey)!

        let journal = JournalDay(day: anchor, dayKey: dayKey, nonWorkingReasonRawValue: nil)
        context.insert(journal)

        let seg1 = PresenceSegment(countryCode: "NL", isWorking: true, sortOrder: 0, journalDay: journal)
        let seg2 = PresenceSegment(countryCode: "AE", isWorking: false, sortOrder: 1, journalDay: journal)
        journal.segments = [seg1, seg2]
        context.insert(seg1)
        context.insert(seg2)

        let trip = Trip(
            flightDesignator: "KL427",
            departureCountryCode: "NL",
            arrivalCountryCode: "AE",
            departureDay: dayDate,
            arrivalDay: dayDate
        )
        context.insert(trip)
        journal.trip = trip

        try context.save()

        let allDays = try context.fetch(FetchDescriptor<JournalDay>())
        let report = YearPresenceReportBuilder.build(year: 2025, journalDays: allDays, calendar: cal)

        #expect(report.loggedDays == 1)
        #expect(report.unloggedDays == 364)
        #expect(report.splitTravelDays == 1)

        let june = report.months.first { $0.month == 6 }
        #expect(june != nil)
        let row = june?.rows.first { $0.dayKey == dayKey }
        #expect(row?.isSplitDay == true)
        #expect(row?.segments.count == 2)
        #expect(row?.segments[0].countryCode == "NL")
        #expect(row?.segments[1].countryCode == "AE")
        #expect(row?.tripSummary?.contains("KL427") == true)

        let pdfData = try YearPresencePDFRenderer.render(report)
        #expect(pdfData.count > 1000)
        #expect(String(data: pdfData.prefix(4), encoding: .ascii) == "%PDF")
    }

    /// Journal TZ east of the phone (Dubai vs Amsterdam): midnight civil dates must still format as that civil day/month.
    @Test func civilDateFormatsStayOnJournalDayWhenDeviceIsWest() throws {
        let tzKey = JournalCalendar.timeZonePreferenceKey
        let previousTZ = UserDefaults.standard.string(forKey: tzKey)
        defer {
            if let previousTZ {
                UserDefaults.standard.set(previousTZ, forKey: tzKey)
            } else {
                UserDefaults.standard.removeObject(forKey: tzKey)
            }
        }
        UserDefaults.standard.set("Asia/Dubai", forKey: tzKey)

        var julyComps = DateComponents()
        julyComps.year = 2026
        julyComps.month = 7
        julyComps.day = 15
        julyComps.hour = 12
        let julyMid = try #require(JournalCalendar.civil.date(from: julyComps))
        let julyMonthStart = JournalCalendar.monthStart(for: julyMid)

        #expect(JournalCalendar.civil.component(.month, from: julyMonthStart) == 7)
        let julyLabel = julyMonthStart.formatted(JournalCalendar.monthYearFormat)
        let julyName = JournalCalendar.civil.monthSymbols[6]
        #expect(julyLabel.localizedStandardContains(julyName))

        let amsterdam = try #require(TimeZone(identifier: "Europe/Amsterdam"))
        var naiveMonthStyle = Date.FormatStyle().month(.wide).year()
        naiveMonthStyle.timeZone = amsterdam
        let naiveMonthLabel = julyMonthStart.formatted(naiveMonthStyle)
        let juneName = JournalCalendar.civil.monthSymbols[5]
        #expect(naiveMonthLabel.localizedStandardContains(juneName))
        #expect(julyLabel != naiveMonthLabel)

        let dayKey = "2026-08-24"
        let midnight = try #require(JournalCalendar.normalizedStartOfDay(dayKey: dayKey))
        #expect(JournalCalendar.civil.component(.day, from: midnight) == 24)

        let detailLabel = midnight.formatted(JournalCalendar.weekdayDayMonthYearFormat)
        #expect(detailLabel.contains("24"))
        #expect(!detailLabel.contains("23"))

        var naiveDetailStyle = Date.FormatStyle().weekday(.wide).day().month(.abbreviated).year()
        naiveDetailStyle.timeZone = amsterdam
        let naiveDetailLabel = midnight.formatted(naiveDetailStyle)
        #expect(naiveDetailLabel.contains("23"))
        #expect(detailLabel != naiveDetailLabel)
    }

}
