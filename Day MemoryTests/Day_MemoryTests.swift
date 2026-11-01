//
//  Day_MemoryTests.swift
//  Day MemoryTests
//
//  Created by MotionSpace - Development on 20/04/2026.
//

import Testing
import SwiftData
import Foundation
import PDFKit
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
        let sourceContainer = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
        )
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

        let restoreContainer = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
        )
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
        let seg1 = PresenceSegment(countryCode: "NL", isWorking: true, sortOrder: 0, journalDay: journal)
        let seg2 = PresenceSegment(countryCode: "AE", isWorking: false, sortOrder: 1, journalDay: journal)
        journal.segments = [seg1, seg2]

        let trip = Trip(
            flightDesignator: "KL427",
            departureCountryCode: "NL",
            arrivalCountryCode: "AE",
            departureDay: dayDate,
            arrivalDay: dayDate
        )
        journal.trip = trip

        let leaveDate = cal.date(byAdding: .day, value: 1, to: dayDate)!
        let leaveKey = JournalCalendar.dayKey(for: leaveDate)
        let leaveAnchor = JournalCalendar.sortAnchor(dayKey: leaveKey)!
        let leaveDay = JournalDay(
            day: leaveAnchor,
            dayKey: leaveKey,
            nonWorkingReasonRawValue: DayNonWorkingReason.annualLeave.rawValue
        )
        let leaveSeg = PresenceSegment(countryCode: "NL", isWorking: false, sortOrder: 0, journalDay: leaveDay)
        leaveDay.segments = [leaveSeg]

        let report = YearPresenceReportBuilder.build(year: 2025, journalDays: [journal, leaveDay], calendar: cal)

        #expect(report.loggedDays == 2)
        #expect(report.unloggedDays == 363)
        #expect(report.splitTravelDays == 1)
        #expect(report.months.count == 12)
        #expect(report.loggedDays + report.unloggedDays == 365)

        let june = report.months.first { $0.month == 6 }
        #expect(june != nil)
        let row = june?.rows.first { $0.dayKey == dayKey }
        #expect(row?.isSplitDay == true)
        #expect(row?.segments.count == 2)
        #expect(row?.segments[0].countryCode == "NL")
        #expect(row?.segments[0].workingLabel == "Working")
        #expect(row?.segments[1].countryCode == "AE")
        #expect(row?.segments[1].workingLabel == "Not working")
        #expect(row?.tripSummary?.contains("KL427") == true)
        #expect(row?.tripSummary?.contains("NL") == true)
        #expect(row?.tripSummary?.contains("AE") == true)

        let leaveRow = june?.rows.first { $0.dayKey == leaveKey }
        #expect(leaveRow?.isLogged == true)
        #expect(leaveRow?.leaveLabel == "Annual leave")
        #expect(leaveRow?.workingSummary == "Not working")
        #expect(leaveRow?.presenceSummary.contains("NL") == true)

        let unloggedRow = june?.rows.first { $0.dayOfMonth == 12 }
        #expect(unloggedRow?.isLogged == false)
        #expect(unloggedRow?.presenceSummary == "Not logged")
        #expect(unloggedRow?.workingSummary == "—")
        #expect(unloggedRow?.leaveLabel == "—")

        let pdfData = try YearPresencePDFRenderer.render(report)
        #expect(pdfData.count > 1000)
        #expect(String(data: pdfData.prefix(4), encoding: .ascii) == "%PDF")

        let document = try #require(PDFDocument(data: pdfData))
        #expect(document.pageCount > 1)
        let extracted = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
        #expect(extracted.contains("Presence & Working Report — 2025"))
        #expect(extracted.contains("Date"))
        #expect(extracted.contains("Location"))
        #expect(extracted.contains("Working"))
        #expect(extracted.contains("Leave"))
        #expect(extracted.contains("Travel"))
        #expect(extracted.contains("KL427"))
        #expect(extracted.contains("Annual leave"))
        #expect(extracted.contains("Not logged"))
        #expect(extracted.contains("Page 1"))
        #expect(extracted.contains("June 2025") || extracted.contains("June"))

        let exportURL = try YearPresencePDFRenderer.exportFileURL(year: 2025)
        #expect(exportURL.lastPathComponent == "DayMemory-presence-2025.pdf")
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

struct LeaveDaysFormattingTests {

    @Test func wholeNumbersDropDecimal() {
        #expect(LeaveDaysFormatting.text(0) == "0")
        #expect(LeaveDaysFormatting.text(11) == "11")
        #expect(LeaveDaysFormatting.text(11.04) == "11")
        #expect(LeaveDaysFormatting.text(2) == "2")
        #expect(LeaveDaysFormatting.text(-3) == "-3")
    }

    @Test func fractionalDaysKeepOneDecimal() {
        #expect(LeaveDaysFormatting.text(2.5) == "2.5")
        #expect(LeaveDaysFormatting.text(15.0 / 31.0 * 2.5) == "1.2")
        #expect(LeaveDaysFormatting.text(11.209677) == "11.2")
        #expect(LeaveDaysFormatting.text(-2.5) == "-2.5")
    }

    @Test func signedBalance() {
        #expect(LeaveDaysFormatting.signedText(1.2) == "+1.2")
        #expect(LeaveDaysFormatting.signedText(11) == "+11")
        #expect(LeaveDaysFormatting.signedText(0) == "0")
        #expect(LeaveDaysFormatting.signedText(-2.5) == "-2.5")
        #expect(LeaveDaysFormatting.signedText(-0.04) == "0")
    }
}

struct LeaveDashboardAggregatorTests {

    @Test func thirtyDayEntitlementShowsHalfDaysPerMonth() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day))!
        }

        let period = EmployerPeriod(
            companyName: "Commercial Bank of Dubai",
            employerCountryCode: "AE",
            startDate: day(2026, 8, 17),
            endDate: day(2026, 12, 31),
            annualLeaveEntitlementDaysRaw: 30
        )

        let report = LeaveDashboardAggregator.report(
            year: 2026,
            employerPeriods: [period],
            journalDays: [],
            calendar: calendar
        )
        let card = try #require(report.employerCards.first)
        let awardedByMonth = Dictionary(
            uniqueKeysWithValues: card.months.map { ($0.calendarMonth, $0.proratedAwardedDays) }
        )

        #expect(LeaveDaysFormatting.text(try #require(awardedByMonth[8])) == "1.2")
        #expect(LeaveDaysFormatting.text(try #require(awardedByMonth[9])) == "2.5")
        #expect(LeaveDaysFormatting.text(try #require(awardedByMonth[10])) == "2.5")
        #expect(LeaveDaysFormatting.text(try #require(awardedByMonth[11])) == "2.5")
        #expect(LeaveDaysFormatting.text(try #require(awardedByMonth[12])) == "2.5")
        #expect(LeaveDaysFormatting.text(card.proratedAwardedDays) == "11.2")
    }
}

struct LeaveMonthBarScaleTests {

    @Test func scaleUsesLargestAwardedOrConsumed() {
        let months = [
            LeaveMonthBreakdown(monthStart: Date(), calendarYear: 2026, calendarMonth: 9, proratedAwardedDays: 2.5, consumedDays: 0),
            LeaveMonthBreakdown(monthStart: Date(), calendarYear: 2026, calendarMonth: 10, proratedAwardedDays: 2.5, consumedDays: 2),
            LeaveMonthBreakdown(monthStart: Date(), calendarYear: 2026, calendarMonth: 12, proratedAwardedDays: 2.5, consumedDays: 9),
        ]
        #expect(LeaveMonthBarScale.scale(for: months) == 9)
        #expect(abs(Double(LeaveMonthBarScale.widthRatio(value: 2.5, scale: 9)) - 2.5 / 9) < 0.0001)
        #expect(LeaveMonthBarScale.widthRatio(value: 9, scale: 9) == 1)
        #expect(LeaveMonthBarScale.widthRatio(value: 0, scale: 9) == 0)
    }

    @Test func unusedMonthsScaleToAwarded() {
        let months = [
            LeaveMonthBreakdown(monthStart: Date(), calendarYear: 2026, calendarMonth: 9, proratedAwardedDays: 2.5, consumedDays: 0),
            LeaveMonthBreakdown(monthStart: Date(), calendarYear: 2026, calendarMonth: 10, proratedAwardedDays: 1.2, consumedDays: 0),
        ]
        #expect(LeaveMonthBarScale.scale(for: months) == 2.5)
        #expect(abs(Double(LeaveMonthBarScale.widthRatio(value: 1.2, scale: 2.5)) - 1.2 / 2.5) < 0.0001)
        #expect(LeaveMonthBarScale.widthRatio(value: 2.5, scale: 2.5) == 1)
    }

    @Test func emptyOrZeroMonthsHaveNoScale() {
        #expect(LeaveMonthBarScale.scale(for: []) == 0)
        #expect(LeaveMonthBarScale.widthRatio(value: 2.5, scale: 0) == 0)
    }
}
