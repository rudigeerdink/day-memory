//
//  EmployerPeriodsView.swift
//  Day Memory
//

import SwiftData
import SwiftUI

struct EmployerPeriodsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \EmployerPeriod.startDate) private var periods: [EmployerPeriod]

    /// Sheet content must not depend on a separate flag + optional model (race → empty sheet).
    struct EditingEmployerPeriod: Identifiable {
        var id: UUID { period.id }
        let period: EmployerPeriod
    }

    @State private var showAdd = false
    @State private var editing: EditingEmployerPeriod?
    @State private var deleteError: String?
    @State private var showDeleteError = false

    private var usesRegularPadLayout: Bool {
        DayMemoryLayout.isRegularPad(horizontalSizeClass)
    }

    var body: some View {
        editorContainer
    }

    private var editorContainer: some View {
        employerChrome
            .modifier(EmployerEditorChrome(
                usesInspector: usesRegularPadLayout,
                showAdd: $showAdd,
                editing: $editing,
                modelContext: modelContext
            ))
    }

    private var employerChrome: some View {
        employerList
            .navigationTitle("Employers")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = nil
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add employer period")
                }
            }
            .alert("Could not delete", isPresented: $showDeleteError) {
                Button("OK", role: .cancel) { deleteError = nil }
            } message: {
                Text(deleteError ?? "")
            }
    }

    private var employerList: some View {
        List {
            if periods.isEmpty {
                ContentUnavailableView(
                    "No employers yet",
                    systemImage: "building.2",
                    description: Text("Add the company that paid you and its country for a date range. Periods cannot overlap.")
                )
            } else {
                ForEach(periods, id: \.id) { period in
                    if usesRegularPadLayout && editing?.period.id == period.id {
                        employerRow(period)
                            .listRowBackground(Color.accentColor.opacity(0.12))
                    } else {
                        employerRow(period)
                    }
                }
                .onDelete(perform: delete)
            }
        }
    }

    private func employerRow(_ period: EmployerPeriod) -> some View {
        Button {
            showAdd = false
            editing = EditingEmployerPeriod(period: period)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(period.companyName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("\(period.employerCountryCode) · \(period.startDate, format: JournalCalendar.dayMonthYearFormat) – \(period.endDate, format: JournalCalendar.dayMonthYearFormat)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Annual entitlement: \(period.annualLeaveEntitlementDays) days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func delete(at offsets: IndexSet) {
        let removedIDs = Set(offsets.map { periods[$0].id })
        if let editing, removedIDs.contains(editing.period.id) {
            self.editing = nil
        }
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

private struct EmployerEditorChrome: ViewModifier {
    var usesInspector: Bool
    @Binding var showAdd: Bool
    @Binding var editing: EmployerPeriodsView.EditingEmployerPeriod?
    var modelContext: ModelContext

    func body(content: Content) -> some View {
        if usesInspector {
            content
                .inspector(isPresented: presented) {
                    NavigationStack {
                        if showAdd {
                            EmployerPeriodForm(period: nil)
                        } else if let editing {
                            EmployerPeriodForm(period: editing.period)
                                .id(editing.id)
                        }
                    }
                    .environment(\.modelContext, modelContext)
                }
                .inspectorColumnWidth(min: 380, ideal: 460, max: 560)
        } else {
            content
                .sheet(isPresented: $showAdd) {
                    NavigationStack {
                        EmployerPeriodForm(period: nil)
                    }
                    .environment(\.modelContext, modelContext)
                    .padFormSheet()
                }
                .sheet(item: $editing) { selection in
                    NavigationStack {
                        EmployerPeriodForm(period: selection.period)
                    }
                    .environment(\.modelContext, modelContext)
                    .padFormSheet()
                }
        }
    }

    private var presented: Binding<Bool> {
        Binding(
            get: { showAdd || editing != nil },
            set: { isShown in
                if !isShown {
                    showAdd = false
                    editing = nil
                }
            }
        )
    }
}

struct EmployerPeriodForm: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \JournalDay.day) private var journalDays: [JournalDay]
    @Query(sort: \EmployerPeriod.startDate) private var employerPeriods: [EmployerPeriod]

    private var calendar: Calendar { JournalCalendar.civil }

    /// `nil` creates a new period.
    var period: EmployerPeriod?

    @State private var companyName = ""
    @State private var countryCode = Countries.deviceRegionCode
    @State private var startDate = Date.now
    @State private var endDate = Date.now
    @State private var annualLeaveEntitlementDays = 0

    @State private var saveError: String?
    @State private var showSaveError = false

    var body: some View {
        Form {
            Section("Employer") {
                TextField("Company name", text: $companyName)
                CountryPicker(
                    title: "Employer country",
                    selection: $countryCode,
                    frequentCodes: Countries.frequentCodes(
                        journalDays: journalDays,
                        employerPeriods: employerPeriods,
                        including: countryCode
                    )
                )
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
    NavigationStack {
        EmployerPeriodsView()
    }
        .modelContainer(
            for: [EmployerPeriod.self, JournalDay.self, PresenceSegment.self, Trip.self, TripTicketImage.self, StayLimitRule.self],
            inMemory: true
        )
}
