//
//  Day_MemoryApp.swift
//  Day Memory
//
//  Created by MotionSpace - Development on 20/04/2026.
//

import SwiftData
import SwiftUI

@main
struct Day_MemoryApp: App {
    init() {
        JournalCalendar.ensurePreferenceInitialized()
        try? JournalCalendar.migrateJournalDayKeys(modelContext: Self.sharedModelContainer.mainContext)
    }

    /// Private CloudKit database for this Apple ID. The iCloud Drive JSON backup stays a separate copy.
    private static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            EmployerPeriod.self,
            JournalDay.self,
            PresenceSegment.self,
            Trip.self,
            TripTicketImage.self,
        ])
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to open SwiftData store: \(error.localizedDescription)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(Self.sharedModelContainer)
    }
}
