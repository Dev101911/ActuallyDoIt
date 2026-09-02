//
//  RecurrenceRule.swift
//  ActuallyDoIt
//
//  Describes how a Chore repeats. A task with no RecurrenceRule is a one-off ToDo.
//

import Foundation

/// A repeating schedule for a Chore.
///
/// Stored as a `Codable` value on the task model, so it must stay a simple value type.
struct RecurrenceRule: Codable, Hashable {
    enum Frequency: String, Codable, CaseIterable {
        case daily
        case weekly
        case monthly
        case everyNDays

        var label: String {
            switch self {
            case .daily: return "Daily"
            case .weekly: return "Weekly"
            case .monthly: return "Monthly"
            case .everyNDays: return "Every N days"
            }
        }
    }

    var frequency: Frequency
    /// The multiplier for the frequency, e.g. every 2 weeks. Also used as N for `everyNDays`.
    var interval: Int
    /// For a `weekly` frequency, the specific days the chore repeats on, as `Calendar` weekday
    /// numbers (1 = Sunday … 7 = Saturday). `nil` or empty means "any day this week" and the
    /// occurrence simply advances a week at a time. Optional so older stored rules that predate
    /// this field decode cleanly (a missing key becomes `nil`).
    var weekdays: [Int]?

    /// The day the schedule is allowed to begin on. The first occurrence lands on or after this
    /// date; `nil` means "start today". Optional so older stored rules decode cleanly.
    var startDate: Date?

    /// The last day the schedule may run. Occurrences after this date are dropped, so the chore
    /// stops repeating; `nil` means "repeat forever". Optional so older stored rules decode cleanly.
    var endDate: Date?

    /// Whether this rule's frequency lets the user pin specific weekdays.
    var supportsWeekdays: Bool { frequency == .weekly }

    init(frequency: Frequency, interval: Int = 1, weekdays: [Int]? = nil, startDate: Date? = nil, endDate: Date? = nil) {
        self.frequency = frequency
        self.interval = max(1, interval)
        // Keep the stored days tidy: unique, sorted, and only when there are any.
        if let weekdays, !weekdays.isEmpty {
            self.weekdays = Array(Set(weekdays)).sorted()
        } else {
            self.weekdays = nil
        }
        // Pin start/end to the beginning of their day so they compare cleanly against whole-day dues.
        self.startDate = startDate.map { Calendar.current.startOfDay(for: $0) }
        self.endDate = endDate.map { Calendar.current.startOfDay(for: $0) }
    }

    /// The next occurrence strictly after the given date, or `nil` once the schedule passes its
    /// end date (if one is set).
    func nextDate(after date: Date, calendar: Calendar = .current) -> Date? {
        let candidate: Date?
        if supportsWeekdays, let weekdays, !weekdays.isEmpty {
            candidate = nextWeekdayOccurrence(after: date, weekdays: Set(weekdays), calendar: calendar)
        } else {
            switch frequency {
            case .daily, .everyNDays:
                candidate = calendar.date(byAdding: .day, value: interval, to: date)
            case .weekly:
                candidate = calendar.date(byAdding: .weekOfYear, value: interval, to: date)
            case .monthly:
                candidate = calendar.date(byAdding: .month, value: interval, to: date)
            }
        }
        // Stop repeating once the schedule runs past its end date.
        if let candidate, let endDate, candidate > endDate {
            return nil
        }
        return candidate
    }

    /// The first due date for a freshly created chore, anchored to the start of a day so reminders
    /// land on whole days. When specific weekdays are chosen, that's the start day if it's one of
    /// them, otherwise the next matching weekday. A `startDate` in the future pushes the first
    /// occurrence out to that day; one in the past still anchors the schedule's phase, so the first
    /// due date is the first occurrence on or after the reference that lands on the chosen cadence
    /// (e.g. an every-2-weeks chore started last Wednesday next falls due a fortnight later, not
    /// today).
    func firstDueDate(from reference: Date = Date(), calendar: Calendar = .current) -> Date {
        let referenceDay = calendar.startOfDay(for: reference)
        // The day the schedule is pinned to; without an explicit start we anchor to the reference.
        let anchor = startDate.map { calendar.startOfDay(for: $0) } ?? referenceDay

        // The first candidate occurrence, honouring any chosen weekdays.
        var occurrence: Date
        if supportsWeekdays, let weekdays, !weekdays.isEmpty {
            if weekdays.contains(calendar.component(.weekday, from: anchor)) {
                occurrence = anchor
            } else {
                occurrence = nextWeekdayOccurrence(after: anchor, weekdays: Set(weekdays), calendar: calendar) ?? anchor
            }
        } else {
            occurrence = anchor
        }

        // Step forward along the cadence until we reach the first occurrence on or after the
        // reference, so a start day in the past fixes the schedule's phase rather than its date.
        while occurrence < referenceDay {
            guard let next = nextDate(after: occurrence, calendar: calendar) else { break }
            occurrence = next
        }
        return occurrence
    }

    /// The next day strictly after `date` whose weekday is in `weekdays`, respecting `interval`.
    ///
    /// For a weekly interval greater than one the schedule only fires in weeks that are a whole
    /// number of intervals from the anchor week (the rule's `startDate`, falling back to `date`),
    /// so "every 2 weeks on Wed" skips the off weeks instead of firing every Wednesday.
    private func nextWeekdayOccurrence(after date: Date, weekdays: Set<Int>, calendar: Calendar) -> Date? {
        let anchorWeekStart = calendar.dateInterval(of: .weekOfYear, for: startDate ?? date)?.start
        // Scan far enough to clear a full skipped span plus one active week.
        let horizon = interval * 7 + 7
        for offset in 1...horizon {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
            guard weekdays.contains(calendar.component(.weekday, from: candidate)) else { continue }
            // With a multi-week interval, only accept candidates that land in an on-phase week.
            if interval > 1, let anchorWeekStart,
               let candidateWeekStart = calendar.dateInterval(of: .weekOfYear, for: candidate)?.start {
                let weeks = calendar.dateComponents([.weekOfYear], from: anchorWeekStart, to: candidateWeekStart).weekOfYear ?? 0
                if weeks % interval != 0 { continue }
            }
            return candidate
        }
        return nil
    }

    /// A short human-readable description, e.g. "Every 2 weeks" or "Weekly on Mon, Wed".
    var summary: String {
        switch frequency {
        case .daily:
            return interval == 1 ? "Daily" : "Every \(interval) days"
        case .everyNDays:
            return "Every \(interval) days"
        case .weekly:
            let base = interval == 1 ? "Weekly" : "Every \(interval) weeks"
            if let weekdays, !weekdays.isEmpty {
                return "\(base) on \(Self.weekdayNames(for: weekdays))"
            }
            return base
        case .monthly:
            return interval == 1 ? "Monthly" : "Every \(interval) months"
        }
    }

    /// A comma-separated list of short weekday names for the given weekday numbers, in week order.
    static func weekdayNames(for weekdays: [Int], calendar: Calendar = .current) -> String {
        let symbols = calendar.shortWeekdaySymbols   // index 0 = Sunday (weekday 1)
        return weekdays.sorted().compactMap { weekday in
            let index = weekday - 1
            return symbols.indices.contains(index) ? symbols[index] : nil
        }.joined(separator: ", ")
    }
}
