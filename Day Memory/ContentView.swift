
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
        root
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

    @ViewBuilder
    private var root: some View {
        if DayMemoryLayout.isPad {
            PadSidebarRoot()
        } else {
            phoneTabs
        }
    }

    private var phoneTabs: some View {
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
                .tabItem { Label("Manage", systemImage: "gearshape.2") }
        }
    }
}

private enum PadSection: String, Hashable, Identifiable {
    case journal
    case work
    case leave
    case employers
    case manage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .journal: "Journal"
        case .work: "Work view"
        case .leave: "Leave view"
        case .employers: "Employers"
        case .manage: "Manage"
        }
    }

    var subtitle: String {
        switch self {
        case .journal: "Days, travel, and tickets"
        case .work: "Presence by country"
        case .leave: "Entitlement and use"
        case .employers: "Who paid you, and when"
        case .manage: "Backup and reports"
        }
    }

    var symbol: String {
        switch self {
        case .journal: "calendar"
        case .work: "chart.pie"
        case .leave: "chart.bar.doc.horizontal"
        case .employers: "building.2"
        case .manage: "gearshape.2"
        }
    }
}

/// iPad navigation column. iPhone keeps the tab bar in `ContentView`.
private struct PadSidebarRoot: View {
    @State private var section: PadSection? = .journal

    var body: some View {
        NavigationSplitView {
            List(selection: sectionBinding) {
                Section {
                    sidebarRow(.journal)
                }

                Section("Summaries") {
                    sidebarRow(.work)
                    sidebarRow(.leave)
                }

                Section("Setup") {
                    sidebarRow(.employers)
                    sidebarRow(.manage)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Day Memory")
            .navigationSplitViewColumnWidth(min: 248, ideal: 292, max: 340)
        } detail: {
            detail(for: section ?? .journal)
        }
        .navigationSplitViewStyle(.balanced)
    }

    /// Keeps a section chosen. The iOS list selection binding is optional, and a tap should not clear the menu.
    private var sectionBinding: Binding<PadSection?> {
        Binding(
            get: { section },
            set: { newValue in
                if let newValue {
                    section = newValue
                }
            }
        )
    }

    private func sidebarRow(_ item: PadSection) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body.weight(.medium))
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 3)
        } icon: {
            Image(systemName: item.symbol)
                .font(.body.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 28, height: 28)
        }
        .tag(item)
        .accessibilityLabel(item.title)
        .accessibilityHint(item.subtitle)
    }

    @ViewBuilder
    private func detail(for section: PadSection) -> some View {
        switch section {
        case .journal:
            JournalCalendarView()
        case .work:
            YearOverviewView()
        case .leave:
            LeaveDashboardView()
        case .employers:
            EmployerPeriodsView()
        case .manage:
            BackupSettingsView()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(
            for: [EmployerPeriod.self, JournalDay.self, PresenceSegment.self, Trip.self, TripTicketImage.self, StayLimitRule.self],
            inMemory: true
        )
}
