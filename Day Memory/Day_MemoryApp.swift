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
    /// Local SQLite only. CloudKit-backed SwiftData requires optional properties/relationships, no unique
    /// constraints, and optional inverse relations — our schema is not CloudKit-compatible. iCloud Documents
    /// backup (JSON) remains available separately.
    private static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            EmployerPeriod.self,
            JournalDay.self,
            PresenceSegment.self,
            Trip.self,
            TripTicketImage.self,
        ])
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
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
