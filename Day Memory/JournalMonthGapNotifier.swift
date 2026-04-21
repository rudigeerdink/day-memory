//
//  JournalMonthGapNotifier.swift
//  Day Memory
//

import Foundation
import SwiftData
import UserNotifications

@MainActor
enum JournalMonthGapNotifier {
    private static let requestId = "daymemory.prevMonthJournalGaps"

    /// Reschedule the monthly reminder: only when the **previous calendar month** has at least one day
    /// without a journal entry. Fires on the **next** 1st of the month at 09:00 (local), one-shot.
    static func refresh(modelContext: ModelContext) async {
        let calendar = Calendar.autoupdatingCurrent
        let now = Date()

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestId])

        let descriptor = FetchDescriptor<JournalDay>(sortBy: [SortDescriptor(\.day)])
        guard let journalDays = try? modelContext.fetch(descriptor) else { return }

        let gapCount = countUnfilledDaysInPreviousMonth(
            journalDays: journalDays,
            calendar: calendar,
            relativeTo: now
        )

        guard gapCount > 0 else { return }

        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            let ok = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard ok else { return }
        }
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }

        guard let fireDate = nextDayOneAtNineAM(from: now, calendar: calendar),
              fireDate > now.addingTimeInterval(5)
        else { return }

        let monthName = previousMonthName(calendar: calendar, relativeTo: now)

        let content = UNMutableNotificationContent()
        content.title = "Day Memory"
        content.body =
            "\(monthName) had \(gapCount) day\(gapCount == 1 ? "" : "s") without a journal entry."

        let triggerDate = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)

        let request = UNNotificationRequest(
            identifier: requestId,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
        } catch {}
    }

    private static func previousMonthName(calendar: Calendar, relativeTo date: Date) -> String {
        guard let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
              let prevStart = calendar.date(byAdding: .month, value: -1, to: thisMonth)
        else {
            return "Last month"
        }
        return prevStart.formatted(.dateTime.month(.wide))
    }

    /// Next 1st at 09:00 local after `now` (this month’s 1st if still upcoming, otherwise following month’s 1st).
    private static func nextDayOneAtNineAM(from now: Date, calendar: Calendar) -> Date? {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))
        else { return nil }
        var dc = calendar.dateComponents([.year, .month], from: monthStart)
        dc.day = 1
        dc.hour = 9
        dc.minute = 0
        dc.second = 0
        guard let thisMonthFirstNine = calendar.date(from: dc) else { return nil }
        if thisMonthFirstNine > now {
            return thisMonthFirstNine
        }
        guard let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
            return nil
        }
        var dc2 = calendar.dateComponents([.year, .month], from: nextMonthStart)
        dc2.day = 1
        dc2.hour = 9
        dc2.minute = 0
        dc2.second = 0
        return calendar.date(from: dc2)
    }

    private static func countUnfilledDaysInPreviousMonth(
        journalDays: [JournalDay],
        calendar: Calendar,
        relativeTo date: Date
    ) -> Int {
        guard let thisMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
              let prevMonthStart = calendar.date(byAdding: .month, value: -1, to: thisMonthStart),
              let range = calendar.range(of: .day, in: .month, for: prevMonthStart)
        else { return 0 }

        var logged: Set<Date> = []
        for jd in journalDays {
            let n = ModelValidation.startOfDay(jd.day, calendar: calendar)
            logged.insert(n)
        }

        var missing = 0
        for day in range {
            guard let d = calendar.date(byAdding: .day, value: day - 1, to: prevMonthStart) else { continue }
            let n = ModelValidation.startOfDay(d, calendar: calendar)
            if !logged.contains(n) {
                missing += 1
            }
        }
        return missing
    }
}
