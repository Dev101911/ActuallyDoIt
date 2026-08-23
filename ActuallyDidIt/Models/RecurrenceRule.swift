//
//  RecurrenceRule.swift
//  ActuallyDidIt
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

    /// Whether this rule's frequency lets the user pin specific weekdays.
    var supportsWeekdays: Bool { frequency == .weekly }

    init(frequency: Frequency, interval: Int = 1, weekdays: [Int]? = nil) {
        self.frequency = frequency
        self.interval = max(1, interval)
        // Keep the stored days tidy: unique, sorted, and only when there are any.
        if let weekdays, !weekdays.isEmpty {
            self.weekdays = Array(Set(weekdays)).sorted()
        } else {
            self.weekdays = nil
        }
    }

    /// The next occurrence strictly after the given date.
    func nextDate(after date: Date, calendar: Calendar = .current) -> Date? {
        if supportsWeekdays, let weekdays, !weekdays.isEmpty {
            return nextWeekdayOccurrence(after: date, weekdays: Set(weekdays), calendar: calendar)
        }
        switch frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: interval, to: date)
        case .everyNDays:
            return calendar.date(byAdding: .day, value: interval, to: date)
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: interval, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: interval, to: date)
        }
    }

    /// The first due date for a freshly created chore, anchored to the start of a day so reminders
    /// land on whole days. When specific weekdays are chosen, that's today if today is one of them,
    /// otherwise the next matching weekday.
    func firstDueDate(from reference: Date = Date(), calendar: Calendar = .current) -> Date {
        let startOfDay = calendar.startOfDay(for: reference)
        if supportsWeekdays, let weekdays, !weekdays.isEmpty {
            if weekdays.contains(calendar.component(.weekday, from: startOfDay)) {
                return startOfDay
            }
            return nextWeekdayOccurrence(after: startOfDay, weekdays: Set(weekdays), calendar: calendar) ?? startOfDay
        }
        return startOfDay
    }

    /// The next day strictly after `date` whose weekday is in `weekdays`.
    private func nextWeekdayOccurrence(after date: Date, weekdays: Set<Int>, calendar: Calendar) -> Date? {
        for offset in 1...7 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
            if weekdays.contains(calendar.component(.weekday, from: candidate)) {
                return candidate
            }
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
