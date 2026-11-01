//
//  DayDetailView.swift
//  Day Memory
//

import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct DayDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \JournalDay.day) private var journalDays: [JournalDay]
    @Query(sort: \EmployerPeriod.startDate) private var employerPeriods: [EmployerPeriod]

    let day: Date
    let defaultFallbackCountry: String
    /// Called when the editor closes after save, delete, or Close. iPhone relies on `dismiss()` alone.
    var onFinished: (() -> Void)? = nil

    @State private var didLoad = false

    @State private var splitTravelDay = false

    @State private var country0 = "NL"
    @State private var working0 = true
    @State private var country1 = "DE"
    @State private var working1 = false
    @State private var nonWorkingReason: DayNonWorkingReason = .none

    @State private var flight = ""
    @State private var depCountry = ""
    @State private var arrCountry = ""
    @State private var ticketImages: [Data] = []
    @State private var pickerItems: [PhotosPickerItem] = []

    @State private var saveError: String?
    @State private var showSaveError = false
    @State private var errorTitle = "Cannot save"
    @State private var hasExistingEntry = false
    @State private var showDeleteConfirmation = false

    private var calendar: Calendar { JournalCalendar.civil }

    var body: some View {
        Form {
            Section("This day") {
                Text(day, format: JournalCalendar.weekdayDayMonthYearFormat)
                CountryPicker(
                    title: "Country",
                    selection: $country0,
                    frequentCodes: frequentCountryCodes(including: country0)
                )
                Toggle("Working", isOn: $working0)
            }

            Section("Travel (same calendar day, two countries)") {
                Toggle("Split across two countries", isOn: $splitTravelDay)
                if splitTravelDay {
                    CountryPicker(
                        title: "Second country",
                        selection: $country1,
                        frequentCodes: frequentCountryCodes(including: country1)
                    )
                    Toggle("Working in second country", isOn: $working1)
                }
            }

            Section("Leave status (independent from working status)") {
                Picker("Leave status", selection: $nonWorkingReason) {
                    ForEach(DayNonWorkingReason.allCases, id: \.rawValue) { reason in
                        Text(reason.title).tag(reason)
                    }
                }
            }

            Section("Trip evidence") {
                TextField("Flight number", text: $flight)
                    .textInputAutocapitalization(.characters)

                CountryPicker(
                    title: "Departure country (optional)",
                    selection: $depCountry,
                    frequentCodes: frequentCountryCodes(including: depCountry),
                    allowsEmpty: true
                )

                CountryPicker(
                    title: "Arrival country (optional)",
                    selection: $arrCountry,
                    frequentCodes: frequentCountryCodes(including: arrCountry),
                    allowsEmpty: true
                )

                Text("Automatic flight lookup can plug in here later.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                PhotosPicker(selection: $pickerItems, maxSelectionCount: 8, matching: .images) {
                    Label("Add ticket photos", systemImage: "photo.on.rectangle.angled")
                }
                .onChange(of: pickerItems) { _, items in
                    Task { await loadPhotos(items) }
                }

                if !ticketImages.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(Array(ticketImages.enumerated()), id: \.offset) { _, data in
                                if let ui = UIImage(data: data) {
                                    Image(uiImage: ui)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 72, height: 96)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets())
                }

                if !flight.isEmpty || !depCountry.isEmpty || !arrCountry.isEmpty || !ticketImages.isEmpty {
                    Button("Clear trip fields & photos", role: .destructive) {
                        flight = ""
                        depCountry = ""
                        arrCountry = ""
                        ticketImages = []
                        pickerItems = []
                    }
                }
            }

            if hasExistingEntry {
                Section {
                    Button("Delete day entry", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                } footer: {
                    Text("Removes this day's journal data and returns it to a fresh state.")
                }
            }
        }
        .navigationTitle("Day")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { closeEditor() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
        .onAppear(perform: load)
        .confirmationDialog("Delete this day entry?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete day entry", role: .destructive) { deleteDayEntry() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all saved country/work and trip details for this date.")
        }
        .alert(errorTitle, isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    private func closeEditor() {
        onFinished?()
        dismiss()
    }

    private func frequentCountryCodes(including code: String) -> [String] {
        Countries.frequentCodes(
            journalDays: journalDays,
            employerPeriods: employerPeriods,
            including: code
        )
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true

        let dayKey = JournalCalendar.dayKey(for: day)
        let fd = FetchDescriptor<JournalDay>(predicate: #Predicate { journalDay in
            journalDay.dayKey == dayKey
        })

        if let existing = try? modelContext.fetch(fd).first {
            hasExistingEntry = true
            nonWorkingReason = existing.nonWorkingReason
            let sorted = existing.orderedSegments
            if let s0 = sorted.first {
                country0 = s0.countryCode
                working0 = s0.isWorking
            }
            if sorted.count == 2 {
                splitTravelDay = true
                country1 = sorted[1].countryCode
                working1 = sorted[1].isWorking
            }
            if let t = existing.trip {
                flight = t.flightDesignator ?? ""
                depCountry = t.departureCountryCode ?? ""
                arrCountry = t.arrivalCountryCode ?? ""
                ticketImages = t.orderedTicketImages.compactMap(\.imageData)
            }
        } else {
            hasExistingEntry = false
            nonWorkingReason = .none
            let allDescriptor = FetchDescriptor<JournalDay>(sortBy: [SortDescriptor(\.day)])
            let all = (try? modelContext.fetch(allDescriptor)) ?? []
            let snaps = all.map { $0.snapshotForValidation() }
            let anchor = JournalCalendar.sortAnchor(dayKey: dayKey)
                ?? ModelValidation.startOfDay(day, calendar: calendar)
            country0 =
                ModelValidation.lastKnownCountry(
                    beforeDayKey: dayKey,
                    priorRecords: snaps,
                    fallback: defaultFallbackCountry
                ) ?? defaultFallbackCountry
            working0 = !calendar.isDateInWeekend(anchor)
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        var data: [Data] = []
        for item in items {
            if let d = try? await item.loadTransferable(type: Data.self) {
                data.append(d)
            }
        }
        await MainActor.run {
            ticketImages.append(contentsOf: data)
            pickerItems = []
        }
    }

    private func save() {
        let dayKey = JournalCalendar.dayKey(for: day)
        let anchor = JournalCalendar.sortAnchor(dayKey: dayKey)
            ?? ModelValidation.startOfDay(day, calendar: calendar)
        let normalized = ModelValidation.startOfDay(anchor, calendar: calendar)

        var segs: [DayPresenceSegmentSnapshot] = [
            DayPresenceSegmentSnapshot(
                id: UUID(),
                countryCode: country0.uppercased(),
                isWorking: working0,
                sortOrder: 0
            ),
        ]
        if splitTravelDay {
            segs.append(
                DayPresenceSegmentSnapshot(
                    id: UUID(),
                    countryCode: country1.uppercased(),
                    isWorking: working1,
                    sortOrder: 1
                )
            )
        }

        let fd = FetchDescriptor<JournalDay>(predicate: #Predicate { journalDay in
            journalDay.dayKey == dayKey
        })
        let existing = try? modelContext.fetch(fd).first
        let snapshot = DayRecordSnapshot(
            id: existing?.id ?? UUID(),
            day: anchor,
            dayKey: dayKey,
            segments: segs,
            linkedTripId: existing?.trip?.id
        )

        if let err = snapshot.validationError() {
            errorTitle = "Cannot save"
            saveError = err.errorDescription ?? "This day could not be saved."
            showSaveError = true
            return
        }

        let journal: JournalDay
        if let existing {
            journal = existing
            journal.nonWorkingReason = nonWorkingReason
            journal.day = anchor
            journal.dayKey = dayKey
            let tripKeep = existing.trip
            for seg in journal.orderedSegments {
                modelContext.delete(seg)
            }
            journal.segments = []
            journal.trip = tripKeep
        } else {
            journal = JournalDay(
                day: anchor,
                dayKey: dayKey,
                nonWorkingReasonRawValue: nonWorkingReason == .none ? nil : nonWorkingReason.rawValue
            )
            modelContext.insert(journal)
        }

        for s in segs {
            let seg = PresenceSegment(
                countryCode: s.countryCode,
                isWorking: s.isWorking,
                sortOrder: s.sortOrder,
                journalDay: journal
            )
            journal.appendSegment(seg)
            modelContext.insert(seg)
        }

        let wantsTrip =
            !flight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !depCountry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !arrCountry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !ticketImages.isEmpty

        if wantsTrip {
            let trip = journal.trip ?? Trip()
            if journal.trip == nil {
                modelContext.insert(trip)
                journal.trip = trip
            }
            let f = flight.trimmingCharacters(in: .whitespacesAndNewlines)
            let dc = depCountry.trimmingCharacters(in: .whitespacesAndNewlines)
            let ac = arrCountry.trimmingCharacters(in: .whitespacesAndNewlines)
            trip.flightDesignator = f.isEmpty ? nil : f.uppercased()
            trip.departureCountryCode = dc.isEmpty ? nil : dc.uppercased()
            trip.arrivalCountryCode = ac.isEmpty ? nil : ac.uppercased()
            trip.departureDay = normalized
            trip.arrivalDay = normalized

            let oldImages = trip.orderedTicketImages
            for img in oldImages {
                modelContext.delete(img)
            }
            trip.ticketImages = []
            for (i, d) in ticketImages.enumerated() {
                let ti = TripTicketImage(sortOrder: i, imageData: d, trip: trip)
                trip.appendTicketImage(ti)
                modelContext.insert(ti)
            }
        } else if let t = journal.trip {
            journal.trip = nil
            modelContext.delete(t)
        }

        do {
            try modelContext.save()
            closeEditor()
        } catch {
            errorTitle = "Cannot save"
            saveError = error.localizedDescription
            showSaveError = true
        }
    }

    private func deleteDayEntry() {
        let dayKey = JournalCalendar.dayKey(for: day)
        let fd = FetchDescriptor<JournalDay>(predicate: #Predicate { journalDay in
            journalDay.dayKey == dayKey
        })

        do {
            guard let existing = try modelContext.fetch(fd).first else {
                closeEditor()
                return
            }

            if let trip = existing.trip {
                existing.trip = nil
                if trip.linkedJournalDays.count <= 1 {
                    modelContext.delete(trip)
                }
            }

            modelContext.delete(existing)
            try modelContext.save()
            closeEditor()
        } catch {
            errorTitle = "Cannot delete day"
            saveError = error.localizedDescription
            showSaveError = true
        }
    }
}

#Preview {
    NavigationStack {
        DayDetailView(day: .now, defaultFallbackCountry: "NL")
    }
    .modelContainer(
        for: [EmployerPeriod.self, JournalDay.self, PresenceSegment.self, Trip.self, TripTicketImage.self, StayLimitRule.self],
        inMemory: true
    )
}
