//
//  Countries.swift
//  Day Memory
//

import Foundation

enum Countries {
    struct Entry: Hashable, Sendable {
        let code: String
        let name: String
    }

    static let all: [Entry] = {
        Locale.Region.isoRegions
            .filter { $0.identifier.count == 2 && $0.identifier.allSatisfy(\.isLetter) }
            .map { region in
                let code = region.identifier.uppercased()
                let name = Locale.current.localizedString(forRegionCode: code) ?? code
                return Entry(code: code, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()

    static func name(for code: String) -> String {
        let normalized = code.uppercased()
        return all.first { $0.code == normalized }?.name ?? normalized
    }

    static func entry(for code: String) -> Entry? {
        let normalized = code.uppercased()
        guard ModelValidation.isValidCountryCode(normalized) else { return nil }
        return all.first { $0.code == normalized }
            ?? Entry(code: normalized, name: normalized)
    }

    static var deviceRegionCode: String {
        let code = Locale.current.region?.identifier.uppercased() ?? "NL"
        return ModelValidation.isValidCountryCode(code) ? code : "NL"
    }

    /// Top country codes by how often they appear in journal data and employer periods.
    static func frequentCodes(
        journalDays: [JournalDay],
        employerPeriods: [EmployerPeriod],
        limit: Int = 5,
        including selection: String? = nil
    ) -> [String] {
        var counts: [String: Int] = [:]

        for day in journalDays {
            for segment in day.segments {
                let code = segment.countryCode.uppercased()
                guard ModelValidation.isValidCountryCode(code) else { continue }
                counts[code, default: 0] += 1
            }
            if let trip = day.trip {
                if let departure = trip.departureCountryCode?.uppercased(),
                   ModelValidation.isValidCountryCode(departure)
                {
                    counts[departure, default: 0] += 1
                }
                if let arrival = trip.arrivalCountryCode?.uppercased(),
                   ModelValidation.isValidCountryCode(arrival)
                {
                    counts[arrival, default: 0] += 1
                }
            }
        }

        for period in employerPeriods {
            let code = period.employerCountryCode.uppercased()
            guard ModelValidation.isValidCountryCode(code) else { continue }
            counts[code, default: 0] += 1
        }

        var ranked = counts
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .prefix(limit)
            .map(\.key)

        if let selection {
            let normalized = selection.uppercased()
            guard ModelValidation.isValidCountryCode(normalized) else { return ranked }
            if !ranked.contains(normalized) {
                ranked.insert(normalized, at: 0)
                if ranked.count > limit {
                    ranked.removeLast()
                }
            }
        }

        return ranked
    }
}
