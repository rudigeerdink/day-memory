//
//  PersistenceModels.swift
//  Day Memory
//

import Foundation
import SwiftData

@Model
final class EmployerPeriod {
    var id: UUID = UUID()
    var companyName: String = ""
    var employerCountryCode: String = ""
    var startDate: Date = Date()
    var endDate: Date = Date()
    var annualLeaveEntitlementDaysRaw: Int?

    init(
        id: UUID = UUID(),
        companyName: String,
        employerCountryCode: String,
        startDate: Date,
        endDate: Date,
        annualLeaveEntitlementDaysRaw: Int? = nil
    ) {
        self.id = id
        self.companyName = companyName
        self.employerCountryCode = employerCountryCode
        self.startDate = startDate
        self.endDate = endDate
        self.annualLeaveEntitlementDaysRaw = annualLeaveEntitlementDaysRaw
    }
}

@Model
final class JournalDay {
    var id: UUID = UUID()
    /// Sort anchor: noon on this civil day in the journal timezone (see `JournalCalendar`).
    var day: Date = Date()
    /// ISO `yyyy-MM-dd` civil date — canonical identity, independent of device travel.
    /// Uniqueness is enforced in app code. CloudKit cannot honor `@Attribute(.unique)`.
    var dayKey: String?
    @Relationship(deleteRule: .cascade, inverse: \PresenceSegment.journalDay)
    var segments: [PresenceSegment]? = []
    var trip: Trip?
    var nonWorkingReasonRawValue: String?

    init(
        id: UUID = UUID(),
        day: Date,
        dayKey: String?,
        segments: [PresenceSegment] = [],
        trip: Trip? = nil,
        nonWorkingReasonRawValue: String? = nil
    ) {
        self.id = id
        self.day = day
        self.dayKey = dayKey
        self.segments = segments
        self.trip = trip
        self.nonWorkingReasonRawValue = nonWorkingReasonRawValue
    }
}

@Model
final class PresenceSegment {
    var id: UUID = UUID()
    var countryCode: String = ""
    var isWorking: Bool = false
    var sortOrder: Int = 0
    var journalDay: JournalDay?

    init(id: UUID = UUID(), countryCode: String, isWorking: Bool, sortOrder: Int, journalDay: JournalDay? = nil) {
        self.id = id
        self.countryCode = countryCode
        self.isWorking = isWorking
        self.sortOrder = sortOrder
        self.journalDay = journalDay
    }
}

@Model
final class Trip {
    var id: UUID = UUID()
    var flightDesignator: String?
    var departureCountryCode: String?
    var arrivalCountryCode: String?
    var departureDay: Date?
    var arrivalDay: Date?
    var providerSnapshot: String?
    @Relationship(deleteRule: .cascade, inverse: \TripTicketImage.trip)
    var ticketImages: [TripTicketImage]? = []
    @Relationship(inverse: \JournalDay.trip)
    var journalDays: [JournalDay]? = []

    init(
        id: UUID = UUID(),
        flightDesignator: String? = nil,
        departureCountryCode: String? = nil,
        arrivalCountryCode: String? = nil,
        departureDay: Date? = nil,
        arrivalDay: Date? = nil,
        providerSnapshot: String? = nil,
        ticketImages: [TripTicketImage] = [],
        journalDays: [JournalDay] = []
    ) {
        self.id = id
        self.flightDesignator = flightDesignator
        self.departureCountryCode = departureCountryCode
        self.arrivalCountryCode = arrivalCountryCode
        self.departureDay = departureDay
        self.arrivalDay = arrivalDay
        self.providerSnapshot = providerSnapshot
        self.ticketImages = ticketImages
        self.journalDays = journalDays
    }
}

/// One rolling presence limit: a country, how many days are allowed, and the length of each window.
@Model
final class StayLimitRule {
    var id: UUID = UUID()
    var countryCode: String = ""
    var allowedDays: Int = 90
    var periodDays: Int = 180
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        countryCode: String,
        allowedDays: Int,
        periodDays: Int,
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.countryCode = countryCode.uppercased()
        self.allowedDays = allowedDays
        self.periodDays = periodDays
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}

@Model
final class TripTicketImage {
    var id: UUID = UUID()
    var sortOrder: Int = 0
    @Attribute(.externalStorage) var imageData: Data?
    var trip: Trip?

    init(id: UUID = UUID(), sortOrder: Int = 0, imageData: Data? = nil, trip: Trip? = nil) {
        self.id = id
        self.sortOrder = sortOrder
        self.imageData = imageData
        self.trip = trip
    }
}

extension JournalDay {
    var orderedSegments: [PresenceSegment] {
        (segments ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    func appendSegment(_ segment: PresenceSegment) {
        var current = segments ?? []
        current.append(segment)
        segments = current
    }

    /// Stable identity for UI matching; prefers persisted `dayKey`.
    var canonicalDayKey: String {
        if let k = dayKey, !k.isEmpty {
            return k
        }
        return JournalCalendar.dayKey(for: day)
    }

    var nonWorkingReason: DayNonWorkingReason {
        get { DayNonWorkingReason(rawValue: nonWorkingReasonRawValue ?? DayNonWorkingReason.none.rawValue) ?? .none }
        set {
            nonWorkingReasonRawValue = (newValue == .none) ? nil : newValue.rawValue
        }
    }

    func snapshotForValidation() -> DayRecordSnapshot {
        DayRecordSnapshot(
            id: id,
            day: day,
            dayKey: canonicalDayKey,
            segments: orderedSegments.map {
                DayPresenceSegmentSnapshot(id: $0.id, countryCode: $0.countryCode, isWorking: $0.isWorking, sortOrder: $0.sortOrder)
            },
            linkedTripId: trip?.id
        )
    }
}

extension Trip {
    var orderedTicketImages: [TripTicketImage] {
        (ticketImages ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    var linkedJournalDays: [JournalDay] {
        journalDays ?? []
    }

    func appendTicketImage(_ image: TripTicketImage) {
        var current = ticketImages ?? []
        current.append(image)
        ticketImages = current
    }
}

extension EmployerPeriod {
    var annualLeaveEntitlementDays: Int {
        get { annualLeaveEntitlementDaysRaw ?? 0 }
        set { annualLeaveEntitlementDaysRaw = newValue }
    }
}

extension EmployerPeriod {
    func normalizedRange(in calendar: Calendar) -> (Date, Date) {
        ModelValidation.normalizedInclusiveRange(start: startDate, end: endDate, calendar: calendar)
    }
}
