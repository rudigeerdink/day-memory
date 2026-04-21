//
//  PersistenceModels.swift
//  Day Memory
//

import Foundation
import SwiftData

@Model
final class EmployerPeriod {
    var id: UUID
    var companyName: String
    var employerCountryCode: String
    var startDate: Date
    var endDate: Date

    init(
        id: UUID = UUID(),
        companyName: String,
        employerCountryCode: String,
        startDate: Date,
        endDate: Date
    ) {
        self.id = id
        self.companyName = companyName
        self.employerCountryCode = employerCountryCode
        self.startDate = startDate
        self.endDate = endDate
    }
}

@Model
final class JournalDay {
    var id: UUID
    /// Start-of-day in the journal calendar (unique).
    @Attribute(.unique) var day: Date
    @Relationship(deleteRule: .cascade, inverse: \PresenceSegment.journalDay)
    var segments: [PresenceSegment]
    var trip: Trip?

    init(id: UUID = UUID(), day: Date, segments: [PresenceSegment] = [], trip: Trip? = nil) {
        self.id = id
        self.day = day
        self.segments = segments
        self.trip = trip
    }
}

@Model
final class PresenceSegment {
    var id: UUID
    var countryCode: String
    var isWorking: Bool
    var sortOrder: Int
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
    var id: UUID
    var flightDesignator: String?
    var departureCountryCode: String?
    var arrivalCountryCode: String?
    var departureDay: Date?
    var arrivalDay: Date?
    var providerSnapshot: String?
    @Relationship(deleteRule: .cascade, inverse: \TripTicketImage.trip)
    var ticketImages: [TripTicketImage]
    @Relationship(inverse: \JournalDay.trip)
    var journalDays: [JournalDay]

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

@Model
final class TripTicketImage {
    var id: UUID
    var sortOrder: Int
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
    func snapshotForValidation() -> DayRecordSnapshot {
        DayRecordSnapshot(
            id: id,
            day: day,
            segments: segments.sorted { $0.sortOrder < $1.sortOrder }.map {
                DayPresenceSegmentSnapshot(id: $0.id, countryCode: $0.countryCode, isWorking: $0.isWorking, sortOrder: $0.sortOrder)
            },
            linkedTripId: trip?.id
        )
    }
}

extension EmployerPeriod {
    func normalizedRange(in calendar: Calendar) -> (Date, Date) {
        ModelValidation.normalizedInclusiveRange(start: startDate, end: endDate, calendar: calendar)
    }
}
