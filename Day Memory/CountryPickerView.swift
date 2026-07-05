//
//  CountryPickerView.swift
//  Day Memory
//

import SwiftUI

/// Form row that opens a searchable country list with frequently used codes at the top.
struct CountryPicker: View {
    let title: String
    @Binding var selection: String
    var frequentCodes: [String]
    var allowsEmpty: Bool = false

    @State private var showPicker = false

    var body: some View {
        Button {
            showPicker = true
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                countryValueLabel
            }
        }
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                CountryPickerSheet(
                    selection: $selection,
                    frequentCodes: frequentCodes,
                    allowsEmpty: allowsEmpty
                )
            }
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private var countryValueLabel: some View {
        let normalized = selection.uppercased()
        if allowsEmpty && normalized.isEmpty {
            Text("Not set")
                .foregroundStyle(.secondary)
        } else if let entry = Countries.entry(for: normalized) {
            HStack(spacing: 8) {
                CountryColorDot(code: entry.code)
                Text("\(entry.name) (\(entry.code))")
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(normalized.isEmpty ? "Choose country" : normalized)
                .foregroundStyle(.secondary)
        }
    }
}

struct CountryPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selection: String
    let frequentCodes: [String]
    var allowsEmpty: Bool = false

    @State private var searchText = ""

    private var normalizedSelection: String { selection.uppercased() }

    private var frequentSet: Set<String> {
        Set(frequentCodes.map { $0.uppercased() })
    }

    private var frequentEntries: [Countries.Entry] {
        frequentCodes.compactMap { Countries.entry(for: $0) }
    }

    private var filteredAll: [Countries.Entry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return Countries.all }
        return Countries.all.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.code.localizedCaseInsensitiveContains(query)
        }
    }

    private var remainingEntries: [Countries.Entry] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return filteredAll.filter { !frequentSet.contains($0.code) }
        }
        return filteredAll
    }

    var body: some View {
        List {
            if allowsEmpty && searchText.isEmpty {
                Section {
                    clearRow
                }
            }

            if !frequentEntries.isEmpty && searchText.isEmpty {
                Section("Often used") {
                    ForEach(frequentEntries, id: \.code) { entry in
                        countryRow(entry)
                    }
                }
            }

            Section(searchText.isEmpty ? "All countries" : "Results") {
                ForEach(remainingEntries, id: \.code) { entry in
                    countryRow(entry)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search name or code")
        .navigationTitle("Country")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private var clearRow: some View {
        Button {
            selection = ""
            dismiss()
        } label: {
            HStack {
                Text("Not set")
                Spacer()
                if normalizedSelection.isEmpty {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .foregroundStyle(.primary)
    }

    private func countryRow(_ entry: Countries.Entry) -> some View {
        Button {
            selection = entry.code
            dismiss()
        } label: {
            HStack(spacing: 10) {
                CountryColorDot(code: entry.code)
                Text(entry.name)
                Spacer()
                Text(entry.code)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if entry.code == normalizedSelection {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .foregroundStyle(.primary)
    }
}
