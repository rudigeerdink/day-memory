//
//  BackupSettingsView.swift
//  Day Memory
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BackupSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage(BackupPreferences.autoICloudBackupKey) private var autoICloudBackup = false

    /// Sheet content must not depend on a separate flag + optional URL (race → empty view / grey sheet).
    private struct PreparedExport: Identifiable {
        let id = UUID()
        let url: URL
    }

    @State private var preparedExport: PreparedExport?
    @State private var exportError = false
    @State private var exportErrorMessage = ""

    @State private var showImporter = false
    @State private var importError = false
    @State private var importErrorMessage = ""
    @State private var showReplaceImportConfirm = false
    @State private var pendingImportURL: URL?

    @State private var iCloudBackupMessage: String?
    @State private var iCloudBusy = false

    private var lastBackupSummary: String {
        guard let d = BackupPreferences.lastICloudBackupDate else { return "Never" }
        return d.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Export") {
                    Text(
                        "Creates a JSON file with employers, journal days, segments, trips, and ticket photos. Treat it as private."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    Button {
                        Task { await runExport() }
                    } label: {
                        Label("Export backup…", systemImage: "square.and.arrow.up")
                    }
                }

                Section("Import") {
                    Text("Replaces all data in this app with the backup file. This cannot be undone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button {
                        showImporter = true
                    } label: {
                        Label("Import from file…", systemImage: "square.and.arrow.down")
                    }
                }

                Section("iCloud Drive") {
                    Toggle("Automatic backup (about once per day)", isOn: $autoICloudBackup)

                    Text(
                        "When the app goes to the background, Day Memory tries to save DayMemory-backup.json in this app’s iCloud Drive folder. Turn on the iCloud capability (Documents) in Xcode and sign in to iCloud on the device."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    LabeledContent("Last iCloud backup") {
                        Text(lastBackupSummary)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        Task { await manualICloudBackup() }
                    } label: {
                        Label("Backup to iCloud now", systemImage: "icloud.and.arrow.up")
                    }
                    .disabled(iCloudBusy)

                    if let msg = iCloudBackupMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Backup")
            .sheet(item: $preparedExport) { prepared in
                ShareSheet(activityItems: [prepared.url])
            }
            .alert("Export failed", isPresented: $exportError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportErrorMessage)
            }
            .alert("Import failed", isPresented: $importError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importErrorMessage)
            }
            .confirmationDialog(
                "Replace all data?",
                isPresented: $showReplaceImportConfirm,
                titleVisibility: .visible
            ) {
                Button("Import and replace everything", role: .destructive) {
                    Task { await performImport() }
                }
                Button("Cancel", role: .cancel) {
                    pendingImportURL = nil
                }
            } message: {
                Text("Your current employers and journal will be deleted and replaced by the backup.")
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    pendingImportURL = url
                    showReplaceImportConfirm = true
                case .failure(let error):
                    importErrorMessage = error.localizedDescription
                    importError = true
                }
            }
        }
    }

    @MainActor
    private func runExport() async {
        do {
            let data = try DayMemoryBackupService.exportData(modelContext: modelContext)
            let url = try DayMemoryBackupService.exportFileURL()
            try data.write(to: url, options: .atomic)
            preparedExport = PreparedExport(url: url)
        } catch {
            exportErrorMessage = error.localizedDescription
            exportError = true
        }
    }

    @MainActor
    private func performImport() async {
        defer { pendingImportURL = nil }
        guard let url = pendingImportURL else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer {
            if access {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let data = try Data(contentsOf: url)
            try DayMemoryBackupService.importData(data, modelContext: modelContext)
        } catch {
            importErrorMessage = error.localizedDescription
            importError = true
        }
    }

    @MainActor
    private func manualICloudBackup() async {
        iCloudBusy = true
        iCloudBackupMessage = nil
        defer { iCloudBusy = false }
        do {
            let data = try DayMemoryBackupService.exportData(modelContext: modelContext)
            try DayMemoryBackupService.writeToICloudDocuments(data: data)
            BackupPreferences.lastICloudBackupDate = Date()
            iCloudBackupMessage = "Saved to iCloud Drive (Day Memory folder)."
        } catch DayMemoryBackupError.iCloudUnavailable {
            iCloudBackupMessage =
                "iCloud container not available. Enable the iCloud Documents capability and matching container in Xcode."
        } catch {
            iCloudBackupMessage = error.localizedDescription
        }
    }
}

#Preview {
    BackupSettingsView()
        .modelContainer(
            for: [EmployerPeriod.self, JournalDay.self, PresenceSegment.self, Trip.self, TripTicketImage.self],
            inMemory: true
        )
}
