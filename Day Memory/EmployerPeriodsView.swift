//
//  EmployerPeriodsView.swift
//  Day Memory
//

import SwiftData
import SwiftUI

struct EmployerPeriodsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \EmployerPeriod.startDate) private var periods: [EmployerPeriod]

    @State private var showAdd = false
    @State private var showEditSheet = false
    @State private var editing: EmployerPeriod?
    @State private var deleteError: String?
    @State private var showDeleteError = false

    var body: some View {
        NavigationStack {
            List {
                if periods.isEmpty {
                    ContentUnavailableView(
                        "No employers yet",
                        systemImage: "building.2",
                        description: Text("Add the company that paid you and its country for a date range. Periods cannot overlap.")
                    )
                } else {
                    ForEach(periods, id: \.id) { period in
                        Button {
                            editing = period
                            showEditSheet = true
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(period.companyName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("\(period.employerCountryCode) · \(period.startDate, format: .dateTime.day().month(.abbreviated).year()) – \(period.endDate, format: .dateTime.day().month(.abbreviated).year())")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("Annual entitlement: \(period.annualLeaveEntitlementDays) days")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
            .navigationTitle("Employers")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add employer period")
                }
            }
            .sheet(isPresented: $showAdd) {
                NavigationStack {
                    EmployerPeriodForm(period: nil)
                }
                .environment(\.modelContext, modelContext)
            }
            .sheet(isPresented: $showEditSheet, onDismiss: { editing = nil }) {
                NavigationStack {
                    if let period = editing {
                        EmployerPeriodForm(period: period)
                    }
                }
                .environment(\.modelContext, modelContext)
            }
            .alert("Could not delete", isPresented: $showDeleteError) {
                Button("OK", role: .cancel) { deleteError = nil }
            } message: {
                Text(deleteError ?? "")
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let p = periods[index]
            modelContext.delete(p)
        }
        do {
            try modelContext.save()
        } catch {
            deleteError = error.localizedDescription
            showDeleteError = true
        }
    }
}

struct EmployerPeriodForm: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private var calendar: Calendar { .autoupdatingCurrent }

    /// `nil` creates a new period.
    var period: EmployerPeriod?

    @State private var companyName = ""
    @State private var countryCode = "NL"
    @State private var startDate = Date.now
    @State private var endDate = Date.now
    @State private var annualLeaveEntitlementDays = 0

    @State private var saveError: String?
    @State private var showSaveError = false

    var body: some View {
        Form {
            Section("Employer") {
                TextField("Company name", text: $companyName)
                Picker("Employer country", selection: $countryCode) {
                    ForEach(Countries.common, id: \.code) { c in
                        Text("\(c.name) (\(c.code))").tag(c.code)
                    }
                }
            }
            Section("Period") {
                DatePicker("Start", selection: $startDate, displayedComponents: .date)
                DatePicker("End", selection: $endDate, displayedComponents: .date)
            }
            Section("Leave entitlement") {
                Stepper(value: $annualLeaveEntitlementDays, in: 0...365) {
                    Text("Annual leave days: \(annualLeaveEntitlementDays)")
                }
            }
        }
        .navigationTitle(period == nil ? "New period" : "Edit period")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
        .onAppear {
            if let period {
                companyName = period.companyName
                countryCode = period.employerCountryCode
                startDate = period.startDate
                endDate = period.endDate
                annualLeaveEntitlementDays = period.annualLeaveEntitlementDays
            }
        }
        .alert("Cannot save", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    private func save() {
        let trimmed = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            saveError = "Enter a company name."
            showSaveError = true
            return
        }

        let code = countryCode.uppercased()
        guard ModelValidation.isValidCountryCode(code) else {
            saveError = "Use a two-letter employer country code (for example NL or DE)."
            showSaveError = true
            return
        }

        let (ns, ne) = ModelValidation.normalizedInclusiveRange(start: startDate, end: endDate, calendar: calendar)

        let descriptor = FetchDescriptor<EmployerPeriod>(sortBy: [SortDescriptor(\.startDate)])
        let all = (try? modelContext.fetch(descriptor)) ?? []

        if ModelValidation.employerRangeOverlapsPersistedPeriods(
            normalizedStart: ns,
            normalizedEnd: ne,
            persistedPeriods: all,
            excludingEmployerId: period?.id,
            calendar: calendar
        ) {
            saveError = "This period overlaps another. Adjust dates so each day has only one employer."
            showSaveError = true
            return
        }

        do {
            if let existing = period {
                existing.companyName = trimmed
                existing.employerCountryCode = code
                existing.startDate = ns
                existing.endDate = ne
                existing.annualLeaveEntitlementDays = annualLeaveEntitlementDays
            } else {
                let newPeriod = EmployerPeriod(
                    id: UUID(),
                    companyName: trimmed,
                    employerCountryCode: code,
                    startDate: ns,
                    endDate: ne,
                    annualLeaveEntitlementDaysRaw: annualLeaveEntitlementDays
                )
                modelContext.insert(newPeriod)
            }
            try modelContext.save()
            dismiss()
        } catch {
            saveError = error.localizedDescription
            showSaveError = true
        }
    }
}

#Preview {
    EmployerPeriodsView()
        .modelContainer(
            for: [EmployerPeriod.self, JournalDay.self, PresenceSegment.self, Trip.self, TripTicketImage.self],
            inMemory: true
        )
}
