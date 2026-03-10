import Foundation

struct RecurrenceSchedule: Codable, Sendable, Hashable {
    var rule: Calendar.RecurrenceRule
    var referenceDate: Date
    /// For monthly rules, matches the first or last day of the month that
    /// falls on one of these weekdays (e.g. Mon-Fri for "first/last workday").
    var matchingWeekdays: MatchingWeekdays?

    struct MatchingWeekdays: Codable, Sendable, Hashable {
        /// Positive = from start (1=first, 2=second), negative = from end (-1=last, -2=second-to-last).
        var ordinal: Int
        var weekdays: Set<Locale.Weekday>
    }

    init(rule: Calendar.RecurrenceRule, referenceDate: Date = Date(), matchingWeekdays: MatchingWeekdays? = nil) {
        self.rule = rule
        self.referenceDate = referenceDate
        self.matchingWeekdays = matchingWeekdays
    }

    func nextFireDate(after date: Date = Date()) -> Date? {
        // "Last matching weekday" mode (e.g. last workday of month)
        if rule.frequency == .monthly, let match = matchingWeekdays, !match.weekdays.isEmpty {
            return nextFireDateForMatchingWeekday(after: date, match: match)
        }

        // FIXME: recurrences(of:in:) is Beta in macOS 26 and hangs
        // indefinitely for monthly rules with .nth weekday (ordinal weekday).
        // dateAfterMatchingWeekOfMonth in Calendar_Enumerate.swift fails to
        // converge. Bypass with manual date computation for these rules.
        // Revisit once Calendar.RecurrenceRule.recurrences(of:in:) ships as
        // stable (non-Beta) and verify .nth rules work.
        // Ref: https://developer.apple.com/documentation/foundation/calendar/recurrencerule/recurrences(of:in:)-8l967
        if rule.frequency == .monthly,
           let wd = rule.weekdays.first,
           case .nth = wd {
            return nextFireDateForOrdinalWeekday(after: date)
        }

        let horizon = date.addingTimeInterval(366 * 24 * 3600)
        return rule.recurrences(of: referenceDate, in: date..<horizon).first { $0 > date }
    }

    private func nextFireDateForOrdinalWeekday(after date: Date) -> Date? {
        guard let weekdaySpec = rule.weekdays.first,
              case .nth(let ordinal, let localeDay) = weekdaySpec
        else { return nil }

        let cal = rule.calendar
        let weekday = localeDay.calendarWeekday
        let hour = rule.hours.first ?? cal.component(.hour, from: referenceDate)
        let minute = rule.minutes.first ?? cal.component(.minute, from: referenceDate)
        let interval = rule.interval

        let startComps = cal.dateComponents([.year, .month], from: date)
        guard let startYear = startComps.year, let startMonth = startComps.month else {
            return nil
        }

        // Check enough months ahead (14 * interval covers edge cases)
        for offset in stride(from: 0, to: 14 * interval, by: interval) {
            let totalMonth = startMonth + offset - 1
            let year = startYear + totalMonth / 12
            let month = (totalMonth % 12) + 1

            if let candidate = resolveOrdinalWeekday(
                calendar: cal, year: year, month: month,
                weekday: weekday, ordinal: ordinal,
                hour: hour, minute: minute
            ), candidate > date {
                return candidate
            }
        }
        return nil
    }

    private func resolveOrdinalWeekday(
        calendar: Calendar, year: Int, month: Int,
        weekday: Int, ordinal: Int, hour: Int, minute: Int
    ) -> Date? {
        if ordinal >= 1 {
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.weekday = weekday
            comps.weekdayOrdinal = ordinal
            comps.hour = hour
            comps.minute = minute
            comps.second = 0
            return calendar.date(from: comps)
        } else if ordinal == -1 {
            // Last weekday of the month: find last day, walk backward
            var endComps = DateComponents()
            endComps.year = year
            endComps.month = month + 1
            endComps.day = 0
            guard let lastDay = calendar.date(from: endComps) else { return nil }
            let lastWeekday = calendar.component(.weekday, from: lastDay)
            var delta = lastWeekday - weekday
            if delta < 0 { delta += 7 }
            guard let targetDay = calendar.date(byAdding: .day, value: -delta, to: lastDay) else { return nil }
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: targetDay)
        }
        return nil
    }

    // MARK: - Matching Weekday (First/Last)

    private func nextFireDateForMatchingWeekday(after date: Date, match: MatchingWeekdays) -> Date? {
        let cal = rule.calendar
        let hour = rule.hours.first ?? 9
        let minute = rule.minutes.first ?? 0
        let interval = rule.interval
        let gregorianDays = Set(match.weekdays.map { $0.calendarWeekday })

        let startComps = cal.dateComponents([.year, .month], from: date)
        guard let startYear = startComps.year, let startMonth = startComps.month else { return nil }

        for offset in stride(from: 0, to: 14 * interval, by: interval) {
            let totalMonth = startMonth + offset - 1
            let year = startYear + totalMonth / 12
            let month = (totalMonth % 12) + 1

            if let candidate = findNthMatchingDay(
                calendar: cal, year: year, month: month,
                gregorianDays: gregorianDays, ordinal: match.ordinal
            ) {
                guard let result = cal.date(bySettingHour: hour, minute: minute, second: 0, of: candidate) else { continue }
                if result > date { return result }
            }
        }
        return nil
    }

    private func findNthMatchingDay(
        calendar cal: Calendar, year: Int, month: Int,
        gregorianDays: Set<Int>, ordinal: Int
    ) -> Date? {
        if ordinal > 0 {
            // Walk forward from 1st of month, count matching days
            var startComps = DateComponents()
            startComps.year = year
            startComps.month = month
            startComps.day = 1
            guard let firstDay = cal.date(from: startComps) else { return nil }
            let daysInMonth = cal.range(of: .day, in: .month, for: firstDay)?.count ?? 31
            var count = 0
            for dayOffset in 0..<daysInMonth {
                guard let candidate = cal.date(byAdding: .day, value: dayOffset, to: firstDay) else { continue }
                if gregorianDays.contains(cal.component(.weekday, from: candidate)) {
                    count += 1
                    if count == ordinal { return candidate }
                }
            }
        } else if ordinal < 0 {
            // Walk backward from last day of month, count matching days
            var endComps = DateComponents()
            endComps.year = year
            endComps.month = month + 1
            endComps.day = 0
            guard let lastDay = cal.date(from: endComps) else { return nil }
            let daysInMonth = cal.component(.day, from: lastDay)
            let target = -ordinal
            var count = 0
            for dayOffset in 0..<daysInMonth {
                guard let candidate = cal.date(byAdding: .day, value: -dayOffset, to: lastDay) else { continue }
                if gregorianDays.contains(cal.component(.weekday, from: candidate)) {
                    count += 1
                    if count == target { return candidate }
                }
            }
        }
        return nil
    }

    // MARK: - Factory Methods

    static func minutely(interval: Int = 30) -> RecurrenceSchedule {
        let rule = Calendar.RecurrenceRule(
            calendar: .current,
            frequency: .minutely,
            interval: max(1, interval)
        )
        return RecurrenceSchedule(rule: rule)
    }

    static func hourly(interval: Int = 1) -> RecurrenceSchedule {
        let rule = Calendar.RecurrenceRule(
            calendar: .current,
            frequency: .hourly,
            interval: max(1, interval)
        )
        return RecurrenceSchedule(rule: rule)
    }

    static func daily(hour: Int = 9, minute: Int = 0) -> RecurrenceSchedule {
        var rule = Calendar.RecurrenceRule(
            calendar: .current,
            frequency: .daily
        )
        rule.hours = [hour]
        rule.minutes = [minute]
        return RecurrenceSchedule(rule: rule)
    }

    static func weekly(
        interval: Int = 1,
        weekdays: [Locale.Weekday] = [.monday],
        hour: Int = 9,
        minute: Int = 0
    ) -> RecurrenceSchedule {
        var rule = Calendar.RecurrenceRule(
            calendar: .current,
            frequency: .weekly,
            interval: max(1, interval)
        )
        rule.weekdays = weekdays.map { .every($0) }
        rule.hours = [hour]
        rule.minutes = [minute]
        return RecurrenceSchedule(rule: rule)
    }

    static func monthly(
        dayOfMonth: Int = 1,
        hour: Int = 9,
        minute: Int = 0
    ) -> RecurrenceSchedule {
        var rule = Calendar.RecurrenceRule(
            calendar: .current,
            frequency: .monthly
        )
        rule.daysOfTheMonth = [dayOfMonth]
        rule.hours = [hour]
        rule.minutes = [minute]
        return RecurrenceSchedule(rule: rule)
    }

    static func monthlyMatching(
        ordinal: Int = -1,
        weekdays: Set<Locale.Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday],
        hour: Int = 9,
        minute: Int = 0
    ) -> RecurrenceSchedule {
        var rule = Calendar.RecurrenceRule(
            calendar: .current,
            frequency: .monthly
        )
        rule.hours = [hour]
        rule.minutes = [minute]
        return RecurrenceSchedule(
            rule: rule,
            matchingWeekdays: MatchingWeekdays(ordinal: ordinal, weekdays: weekdays)
        )
    }

    static func yearly(
        month: Int = 1,
        day: Int = 1,
        hour: Int = 9,
        minute: Int = 0
    ) -> RecurrenceSchedule {
        var rule = Calendar.RecurrenceRule(
            calendar: .current,
            frequency: .yearly
        )
        rule.months = [Calendar.RecurrenceRule.Month(month)]
        rule.daysOfTheMonth = [day]
        rule.hours = [hour]
        rule.minutes = [minute]
        return RecurrenceSchedule(rule: rule)
    }
}

// MARK: - RecurrenceRule.Weekday Helpers

extension Calendar.RecurrenceRule.Weekday {
    var localeWeekday: Locale.Weekday? {
        switch self {
        case .every(let day): day
        case .nth(_, let day): day
        @unknown default: nil
        }
    }
}

// MARK: - Locale.Weekday Helpers

extension Locale.Weekday {
    static let allWeekdays: [Locale.Weekday] = [
        .sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday,
    ]

    static var localeOrdered: [Locale.Weekday] {
        let first = Calendar.current.firstWeekday // 1=Sun, 2=Mon
        let offset = first - 1
        return Array(allWeekdays[offset...]) + Array(allWeekdays[..<offset])
    }

    var calendarWeekday: Int {
        switch self {
        case .sunday: 1
        case .monday: 2
        case .tuesday: 3
        case .wednesday: 4
        case .thursday: 5
        case .friday: 6
        case .saturday: 7
        @unknown default: 1
        }
    }

    var shortLabel: String {
        switch self {
        case .sunday: "Su"
        case .monday: "Mo"
        case .tuesday: "Tu"
        case .wednesday: "We"
        case .thursday: "Th"
        case .friday: "Fr"
        case .saturday: "Sa"
        @unknown default: "?"
        }
    }
}
