//
//  DayMemoryBackupService.swift
//  Day Memory
//

import Foundation
import SwiftData

enum DayMemoryBackupError: LocalizedError {
    case unsupportedVersion(Int)
    case invalidData
    case iCloudUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let v):
            "This backup format (version \(v)) is not supported."
        case .invalidData:
            "The file could not be read as a Day Memory backup."
        case .iCloudUnavailable:
            "iCloud Drive is not available for this app. Enable iCloud for Day Memory in Settings, or sign in to iCloud."
        }
    }
}

@MainActor
enum DayMemoryBackupService {
    static let iCloudBackupFileName = "DayMemory-backup.json"
    static let formatVersion = 2

    private static var jsonEncoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static var jsonDecoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: - Export

    static func exportData(modelContext: ModelContext) throws -> Data {
        let empDesc = FetchDescriptor<EmployerPeriod>(sortBy: [SortDescriptor(\.startDate)])
        let dayDesc = FetchDescriptor<JournalDay>(sortBy: [SortDescriptor(\.day)])

        let employers = try modelContext.fetch(empDesc).map { e in
            DayMemoryBackupEmployer(
                id: e.id,
                companyName: e.companyName,
                employerCountryCode: e.employerCountryCode,
                startDate: e.startDate,
                endDate: e.endDate,
                annualLeaveEntitlementDays: e.annualLeaveEntitlementDays
            )
        }

        let journalDays = try modelContext.fetch(dayDesc).map { jd in
            DayMemoryBackupJournalDay(
                id: jd.id,
                day: jd.day,
                segments: jd.segments.sorted { $0.sortOrder < $1.sortOrder }.map { s in
                    DayMemoryBackupSegment(
                        id: s.id,
                        countryCode: s.countryCode,
                        isWorking: s.isWorking,
                        sortOrder: s.sortOrder
                    )
                },
                trip: jd.trip.map { trip in
                    DayMemoryBackupTrip(
                        id: trip.id,
                        flightDesignator: trip.flightDesignator,
                        departureCountryCode: trip.departureCountryCode,
                        arrivalCountryCode: trip.arrivalCountryCode,
                        departureDay: trip.departureDay,
                        arrivalDay: trip.arrivalDay,
                        providerSnapshot: trip.providerSnapshot,
                        ticketImages: trip.ticketImages.sorted { $0.sortOrder < $1.sortOrder }.map { img in
                            DayMemoryBackupTicketImage(
                                id: img.id,
                                sortOrder: img.sortOrder,
                                imageDataBase64: img.imageData.map { $0.base64EncodedString() }
                            )
                        }
                    )
                },
                nonWorkingReason: jd.nonWorkingReason == .none ? nil : jd.nonWorkingReason.rawValue
            )
        }

        let envelope = DayMemoryBackupEnvelope(
            formatVersion: formatVersion,
            exportedAt: Date(),
            employers: employers,
            journalDays: journalDays
        )

        return try jsonEncoder.encode(envelope)
    }

    static func exportFileURL() throws -> URL {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate]
        let stamp = fmt.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("DayMemory-export-\(stamp).json")
    }

    // MARK: - Import

    static func importData(_ data: Data, modelContext: ModelContext) throws {
        let envelope = try jsonDecoder.decode(DayMemoryBackupEnvelope.self, from: data)
        guard envelope.formatVersion == 1 || envelope.formatVersion == formatVersion else {
            throw DayMemoryBackupError.unsupportedVersion(envelope.formatVersion)
        }

        try wipeAll(modelContext: modelContext)

        for e in envelope.employers {
            let ep = EmployerPeriod(
                id: e.id,
                companyName: e.companyName,
                employerCountryCode: e.employerCountryCode,
                startDate: e.startDate,
                endDate: e.endDate,
                annualLeaveEntitlementDaysRaw: e.annualLeaveEntitlementDays
            )
            modelContext.insert(ep)
        }

        for dto in envelope.journalDays {
            let jd = JournalDay(
                id: dto.id,
                day: dto.day,
                segments: [],
                trip: nil,
                nonWorkingReasonRawValue: dto.nonWorkingReason ?? DayNonWorkingReason.none.rawValue
            )
            modelContext.insert(jd)

            if let t = dto.trip {
                let trip = Trip(
                    id: t.id,
                    flightDesignator: t.flightDesignator,
                    departureCountryCode: t.departureCountryCode,
                    arrivalCountryCode: t.arrivalCountryCode,
                    departureDay: t.departureDay,
                    arrivalDay: t.arrivalDay,
                    providerSnapshot: t.providerSnapshot,
                    ticketImages: [],
                    journalDays: []
                )
                for img in t.ticketImages.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                    let data = img.imageDataBase64.flatMap { Data(base64Encoded: $0) }
                    let ti = TripTicketImage(id: img.id, sortOrder: img.sortOrder, imageData: data, trip: trip)
                    trip.ticketImages.append(ti)
                    modelContext.insert(ti)
                }
                jd.trip = trip
                modelContext.insert(trip)
            }

            for s in dto.segments.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                let seg = PresenceSegment(
                    id: s.id,
                    countryCode: s.countryCode,
                    isWorking: s.isWorking,
                    sortOrder: s.sortOrder,
                    journalDay: jd
                )
                jd.segments.append(seg)
                modelContext.insert(seg)
            }
        }

        try modelContext.save()
    }

    // MARK: - Wipe

    static func wipeAll(modelContext: ModelContext) throws {
        for item in try modelContext.fetch(FetchDescriptor<JournalDay>()) {
            modelContext.delete(item)
        }
        for item in try modelContext.fetch(FetchDescriptor<TripTicketImage>()) {
            modelContext.delete(item)
        }
        for item in try modelContext.fetch(FetchDescriptor<Trip>()) {
            modelContext.delete(item)
        }
        for item in try modelContext.fetch(FetchDescriptor<EmployerPeriod>()) {
            modelContext.delete(item)
        }
        try modelContext.save()
    }

    // MARK: - iCloud Documents

    /// Writes the same JSON into the app’s iCloud Documents container (`Files` → iCloud Drive → Day Memory).
    static func writeToICloudDocuments(data: Data) throws {
        guard let base = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            throw DayMemoryBackupError.iCloudUnavailable
        }
        let folder = base.appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("DayMemory", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(iCloudBackupFileName)
        try data.write(to: url, options: .atomic)
    }

    /// `nil` if iCloud container not available (capability off or not signed in).
    static func iCloudBackupURLIfAvailable() -> URL? {
        guard let base = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        return base.appendingPathComponent("Documents/DayMemory/\(iCloudBackupFileName)")
    }

    /// Reads backup JSON from iCloud path if the file exists.
    static func readFromICloudIfAvailable() throws -> Data? {
        guard let url = iCloudBackupURLIfAvailable(),
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return try Data(contentsOf: url)
    }

    // MARK: - Periodic iCloud backup

    /// Call when the app enters the background; backs up at most once per 24 hours when the toggle is on.
    @MainActor
    static func performAutomaticICloudBackupIfNeeded(modelContext: ModelContext) {
        guard BackupPreferences.isAutoICloudBackupEnabled else { return }
        let last = BackupPreferences.lastICloudBackupDate ?? .distantPast
        guard Date().timeIntervalSince(last) >= 24 * 3600 else { return }
        do {
            let data = try exportData(modelContext: modelContext)
            try writeToICloudDocuments(data: data)
            BackupPreferences.lastICloudBackupDate = Date()
        } catch {
            // Unavailable iCloud / offline — ignore
        }
    }
}
