//
//  DomainModels.swift
//  Day Memory
//

import Foundation

/// ISO 3166-1 alpha-2 (e.g. "NL", "DE").
typealias CountryCode = String

enum DayNonWorkingReason: String, Codable, CaseIterable, Sendable {
    case none
    case annualLeave
    case publicHoliday

    var title: String {
        switch self {
        case .none:
            return "No selection"
        case .annualLeave:
            return "Annual leave"
        case .publicHoliday:
            return "Public holiday"
        }
    }
}

/// Lightweight copies for validation and bulk-fill logic.
struct DayPresenceSegmentSnapshot: Identifiable, Equatable, Sendable {
    var id: UUID
    var countryCode: CountryCode
    var isWorking: Bool
    var sortOrder: Int
}

struct DayRecordSnapshot: Identifiable, Equatable, Sendable {
    var id: UUID
    var day: Date
    var segments: [DayPresenceSegmentSnapshot]
    var linkedTripId: UUID?
}

extension DayRecordSnapshot {
    func validationError() -> ModelValidation.DayRecordError? {
        ModelValidation.validate(dayRecord: self)
    }
}
