//
//  DayMemoryBackupModels.swift
//  Day Memory
//

import Foundation

/// Versioned archive for export / import.
struct DayMemoryBackupEnvelope: Codable {
    var formatVersion: Int
    var exportedAt: Date
    var employers: [DayMemoryBackupEmployer]
    var journalDays: [DayMemoryBackupJournalDay]
}

struct DayMemoryBackupEmployer: Codable {
    var id: UUID
    var companyName: String
    var employerCountryCode: String
    var startDate: Date
    var endDate: Date
    var annualLeaveEntitlementDays: Int?
}

struct DayMemoryBackupJournalDay: Codable {
    var id: UUID
    var day: Date
    var segments: [DayMemoryBackupSegment]
    var trip: DayMemoryBackupTrip?
    var nonWorkingReason: String?
}

struct DayMemoryBackupSegment: Codable {
    var id: UUID
    var countryCode: String
    var isWorking: Bool
    var sortOrder: Int
}

struct DayMemoryBackupTrip: Codable {
    var id: UUID
    var flightDesignator: String?
    var departureCountryCode: String?
    var arrivalCountryCode: String?
    var departureDay: Date?
    var arrivalDay: Date?
    var providerSnapshot: String?
    var ticketImages: [DayMemoryBackupTicketImage]
}

struct DayMemoryBackupTicketImage: Codable {
    var id: UUID
    var sortOrder: Int
    /// Base64-encoded JPEG/PNG data.
    var imageDataBase64: String?
}
