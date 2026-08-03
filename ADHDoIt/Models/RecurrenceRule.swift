//
//  RecurrenceRule.swift
//  ADHDoIt
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

    init(frequency: Frequency, interval: Int = 1) {
        self.frequency = frequency
        self.interval = max(1, interval)
    }

    /// The next occurrence strictly after the given date.
    func nextDate(after date: Date, calendar: Calendar = .current) -> Date? {
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

    /// A short human-readable description, e.g. "Every 2 weeks".
    var summary: String {
        switch frequency {
        case .daily:
            return interval == 1 ? "Daily" : "Every \(interval) days"
        case .everyNDays:
            return "Every \(interval) days"
        case .weekly:
            return interval == 1 ? "Weekly" : "Every \(interval) weeks"
        case .monthly:
            return interval == 1 ? "Monthly" : "Every \(interval) months"
        }
    }
}
