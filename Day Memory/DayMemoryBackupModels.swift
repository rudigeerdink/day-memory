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
    /// Absent in backups written before stay limits (format 3 and earlier).
    var stayRules: [DayMemoryBackupStayRule]

    init(
        formatVersion: Int,
        exportedAt: Date,
        employers: [DayMemoryBackupEmployer],
        journalDays: [DayMemoryBackupJournalDay],
        stayRules: [DayMemoryBackupStayRule] = []
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.employers = employers
        self.journalDays = journalDays
        self.stayRules = stayRules
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        employers = try container.decode([DayMemoryBackupEmployer].self, forKey: .employers)
        journalDays = try container.decode([DayMemoryBackupJournalDay].self, forKey: .journalDays)
        stayRules = try container.decodeIfPresent([DayMemoryBackupStayRule].self, forKey: .stayRules) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(exportedAt, forKey: .exportedAt)
        try container.encode(employers, forKey: .employers)
        try container.encode(journalDays, forKey: .journalDays)
        try container.encode(stayRules, forKey: .stayRules)
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case exportedAt
        case employers
        case journalDays
        case stayRules
    }
}

struct DayMemoryBackupStayRule: Codable {
    var id: UUID
    var countryCode: String
    var allowedDays: Int
    var periodDays: Int
    var sortOrder: Int
    var createdAt: Date
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
    /// ISO `yyyy-MM-dd` civil journal day (format v3+). Older archives infer this from `day` on import.
    var dayKey: String?
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
