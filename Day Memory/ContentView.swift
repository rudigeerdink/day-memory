
//
//  ContentView.swift
//  Day Memory
//
//  Created by MotionSpace - Development on 20/04/2026.
//

import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            JournalCalendarView()
                .tabItem { Label("Journal", systemImage: "calendar") }

            YearOverviewView()
                .tabItem { Label("Work view", systemImage: "chart.pie") }

            LeaveDashboardView()
                .tabItem { Label("Leave view", systemImage: "chart.bar.doc.horizontal") }

            EmployerPeriodsView()
                .tabItem { Label("Employers", systemImage: "building.2") }

            BackupSettingsView()
                .tabItem { Label("Backup", systemImage: "externaldrive") }
        }
        .task {
            await JournalMonthGapNotifier.refresh(modelContext: modelContext)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await JournalMonthGapNotifier.refresh(modelContext: modelContext) }
            }
            if phase == .background {
                DayMemoryBackupService.performAutomaticICloudBackupIfNeeded(modelContext: modelContext)
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(
            for: [EmployerPeriod.self, JournalDay.self, PresenceSegment.self, Trip.self, TripTicketImage.self],
            inMemory: true
        )
}
