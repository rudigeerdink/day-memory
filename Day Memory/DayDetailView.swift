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

    let day: Date
    let defaultFallbackCountry: String

    @State private var didLoad = false

    @State private var splitTravelDay = false

    @State private var country0 = "NL"
    @State private var working0 = true
    @State private var country1 = "DE"
    @State private var working1 = false

    @State private var flight = ""
    @State private var depCountry = ""
    @State private var arrCountry = ""
    @State private var ticketImages: [Data] = []
    @State private var pickerItems: [PhotosPickerItem] = []

    @State private var saveError: String?
    @State private var showSaveError = false

    private var calendar: Calendar { .autoupdatingCurrent }

    var body: some View {
        Form {
            Section("This day") {
                Text(day, format: .dateTime.weekday(.wide).day().month(.abbreviated).year())
                countryPicker(title: "Country", selection: $country0)
                Toggle("Working", isOn: $working0)
            }

            Section("Travel (same calendar day, two countries)") {
                Toggle("Split across two countries", isOn: $splitTravelDay)
                if splitTravelDay {
                    countryPicker(title: "Second country", selection: $country1)
                    Toggle("Working in second country", isOn: $working1)
                }
            }

            Section("Trip evidence") {
                TextField("Flight number", text: $flight)
                    .textInputAutocapitalization(.characters)

                TextField("Departure country (optional)", text: $depCountry)
                    .textInputAutocapitalization(.characters)

                TextField("Arrival country (optional)", text: $arrCountry)
                    .textInputAutocapitalization(.characters)

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
        }
        .navigationTitle("Day")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
        .onAppear(perform: load)
        .alert("Cannot save", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    private func countryPicker(title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(Countries.common, id: \.code) { c in
                Text("\(c.name) (\(c.code))").tag(c.code)
            }
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true

        let normalized = ModelValidation.startOfDay(day, calendar: calendar)
        let fd = FetchDescriptor<JournalDay>(predicate: #Predicate { journalDay in
            journalDay.day == normalized
        })

        if let existing = try? modelContext.fetch(fd).first {
            let sorted = existing.segments.sorted { $0.sortOrder < $1.sortOrder }
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
                ticketImages = t.ticketImages.sorted { $0.sortOrder < $1.sortOrder }.compactMap(\.imageData)
            }
        } else {
            let allDescriptor = FetchDescriptor<JournalDay>(sortBy: [SortDescriptor(\.day)])
            let all = (try? modelContext.fetch(allDescriptor)) ?? []
            let snaps = all.map { $0.snapshotForValidation() }
            country0 =
                ModelValidation.lastKnownCountry(
                    before: normalized,
                    priorRecords: snaps,
                    calendar: calendar,
                    fallback: defaultFallbackCountry
                ) ?? defaultFallbackCountry
            working0 = !calendar.isDateInWeekend(normalized)
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
        let normalized = ModelValidation.startOfDay(day, calendar: calendar)

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
            journalDay.day == normalized
        })
        let existing = try? modelContext.fetch(fd).first
        let snapshot = DayRecordSnapshot(
            id: existing?.id ?? UUID(),
            day: normalized,
            segments: segs,
            linkedTripId: existing?.trip?.id
        )

        if let err = snapshot.validationError() {
            saveError = err.errorDescription ?? "This day could not be saved."
            showSaveError = true
            return
        }

        let journal: JournalDay
        if let existing {
            journal = existing
            let tripKeep = existing.trip
            for seg in journal.segments {
                modelContext.delete(seg)
            }
            journal.segments.removeAll()
            journal.trip = tripKeep
        } else {
            journal = JournalDay(day: normalized)
            modelContext.insert(journal)
        }

        for s in segs {
            let seg = PresenceSegment(
                countryCode: s.countryCode,
                isWorking: s.isWorking,
                sortOrder: s.sortOrder,
                journalDay: journal
            )
            journal.segments.append(seg)
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

            let oldImages = Array(trip.ticketImages)
            for img in oldImages {
                modelContext.delete(img)
            }
            trip.ticketImages.removeAll()
            for (i, d) in ticketImages.enumerated() {
                let ti = TripTicketImage(sortOrder: i, imageData: d, trip: trip)
                trip.ticketImages.append(ti)
                modelContext.insert(ti)
            }
        } else if let t = journal.trip {
            journal.trip = nil
            modelContext.delete(t)
        }

        do {
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
        DayDetailView(day: .now, defaultFallbackCountry: "NL")
    }
    .modelContainer(
        for: [EmployerPeriod.self, JournalDay.self, PresenceSegment.self, Trip.self, TripTicketImage.self],
        inMemory: true
    )
}
