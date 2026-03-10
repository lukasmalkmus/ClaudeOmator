import SwiftUI

struct ScheduleEditorView: View {
    let schedule: RecurrenceSchedule
    let onChange: (RecurrenceSchedule) -> Void

    private enum Frequency: String, CaseIterable, Identifiable {
        case minutely = "Every N Minutes"
        case hourly = "Hourly"
        case daily = "Daily"
        case weekly = "Weekly"
        case monthly = "Monthly"
        case yearly = "Yearly"

        var id: Self { self }
    }

    private enum MonthlyMode: String, CaseIterable, Identifiable {
        case dayOfMonth = "Day of month"
        case weekday = "Weekday"

        var id: Self { self }
    }

    var body: some View {
        Picker("Frequency", selection: frequencyBinding) {
            ForEach(Frequency.allCases) { freq in
                Text(freq.rawValue).tag(freq)
            }
        }

        intervalRow
        timeRow
        weekdayPicker
        monthlyControls
        yearlyControls
    }

    // MARK: - Frequency Binding

    private var frequencyBinding: Binding<Frequency> {
        Binding(
            get: {
                switch schedule.rule.frequency {
                case .minutely: .minutely
                case .hourly: .hourly
                case .daily: .daily
                case .weekly: .weekly
                case .monthly: .monthly
                case .yearly: .yearly
                @unknown default: .daily
                }
            },
            set: { freq in
                switch freq {
                case .minutely: onChange(.minutely(interval: 30))
                case .hourly: onChange(.hourly())
                case .daily: onChange(.daily())
                case .weekly: onChange(.weekly())
                case .monthly: onChange(.monthly())
                case .yearly: onChange(.yearly())
                }
            }
        )
    }

    // MARK: - Interval

    @ViewBuilder
    private var intervalRow: some View {
        let freq = schedule.rule.frequency
        if freq == .minutely || freq == .hourly || freq == .weekly || schedule.rule.interval > 1 {
            LabeledContent("Every") {
                HStack {
                    TextField("", value: intervalBinding, format: .number)
                        .frame(width: 60)
                    Text(intervalUnitLabel)
                }
            }
        }
    }

    private var intervalBinding: Binding<Int> {
        Binding(
            get: { schedule.rule.interval },
            set: { value in
                var updated = schedule
                updated.rule.interval = max(1, value)
                onChange(updated)
            }
        )
    }

    private var intervalUnitLabel: String {
        switch schedule.rule.frequency {
        case .minutely: "minutes"
        case .hourly: "hours"
        case .daily: "days"
        case .weekly: "weeks"
        case .monthly: "months"
        case .yearly: "years"
        @unknown default: ""
        }
    }

    // MARK: - Time Picker

    @ViewBuilder
    private var timeRow: some View {
        let freq = schedule.rule.frequency
        if freq == .daily || freq == .weekly || freq == .monthly || freq == .yearly {
            DatePicker("At", selection: timeBinding, displayedComponents: .hourAndMinute)
        }
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                let hour = schedule.rule.hours.first ?? 9
                let minute = schedule.rule.minutes.first ?? 0
                var components = DateComponents()
                components.hour = hour
                components.minute = minute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { date in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                var updated = schedule
                updated.rule.hours = [comps.hour ?? 9]
                updated.rule.minutes = [comps.minute ?? 0]
                onChange(updated)
            }
        )
    }

    // MARK: - Weekday Picker

    @ViewBuilder
    private var weekdayPicker: some View {
        let freq = schedule.rule.frequency
        if freq == .weekly || freq == .daily {
            let selectedDays = Set(schedule.rule.weekdays.compactMap { $0.localeWeekday })
            LabeledContent("Days") {
                HStack(spacing: 4) {
                    ForEach(Locale.Weekday.localeOrdered, id: \.self) { day in
                        Toggle(isOn: weekdayToggle(day: day, selected: selectedDays)) {
                            Text(day.shortLabel)
                                .font(.caption)
                                .frame(width: 28, height: 28)
                        }
                        .toggleStyle(.button)
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private func weekdayToggle(day: Locale.Weekday, selected: Set<Locale.Weekday>) -> Binding<Bool> {
        Binding(
            get: { selected.contains(day) },
            set: { isOn in
                var newDays = selected
                if isOn {
                    newDays.insert(day)
                } else if newDays.count > 1 {
                    newDays.remove(day)
                }
                var updated = schedule
                updated.rule.weekdays = newDays.sorted(by: { $0.calendarWeekday < $1.calendarWeekday })
                    .map { .every($0) }
                onChange(updated)
            }
        )
    }

    // MARK: - Monthly Controls

    @ViewBuilder
    private var monthlyControls: some View {
        if schedule.rule.frequency == .monthly {
            Picker("On", selection: monthlyModeBinding) {
                ForEach(MonthlyMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            if currentMonthlyMode == .weekday {
                monthlyWeekdayControls
            } else {
                dayOfMonthPicker
            }
        }
    }

    private var currentMonthlyMode: MonthlyMode {
        if schedule.matchingWeekdays != nil || !schedule.rule.weekdays.isEmpty {
            return .weekday
        }
        return .dayOfMonth
    }

    private var monthlyModeBinding: Binding<MonthlyMode> {
        Binding(
            get: { currentMonthlyMode },
            set: { mode in
                let hour = schedule.rule.hours.first ?? 9
                let minute = schedule.rule.minutes.first ?? 0
                switch mode {
                case .dayOfMonth:
                    onChange(.monthly(dayOfMonth: 1, hour: hour, minute: minute))
                case .weekday:
                    onChange(.monthlyMatching(ordinal: 1, hour: hour, minute: minute))
                }
            }
        )
    }

    @ViewBuilder
    private var dayOfMonthPicker: some View {
        Picker("Day", selection: dayOfMonthBinding) {
            ForEach(1...31, id: \.self) { day in
                Text("\(day)").tag(day)
            }
            Text("Last day").tag(-1)
        }
    }

    private var dayOfMonthBinding: Binding<Int> {
        Binding(
            get: { schedule.rule.daysOfTheMonth.first ?? 1 },
            set: { day in
                var updated = schedule
                updated.rule.daysOfTheMonth = [day]
                onChange(updated)
            }
        )
    }

    // MARK: - Monthly Weekday Controls

    private static let monthlyOrdinals: [(label: String, value: Int)] = [
        ("1st", 1), ("2nd", 2), ("3rd", 3), ("4th", 4), ("5th", 5),
        ("Last", -1), ("2nd last", -2), ("3rd last", -3),
    ]

    @ViewBuilder
    private var monthlyWeekdayControls: some View {
        Picker("Which", selection: monthlyWeekdayOrdinalBinding) {
            ForEach(Self.monthlyOrdinals, id: \.value) { item in
                Text(item.label).tag(item.value)
            }
        }

        let selectedDays = effectiveMonthlyWeekdays
        LabeledContent("Days") {
            HStack(spacing: 4) {
                ForEach(Locale.Weekday.localeOrdered, id: \.self) { day in
                    Toggle(isOn: monthlyWeekdayToggle(day: day, selected: selectedDays)) {
                        Text(day.shortLabel)
                            .font(.caption)
                            .frame(width: 28, height: 28)
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var monthlyWeekdayOrdinalBinding: Binding<Int> {
        Binding(
            get: {
                if let match = schedule.matchingWeekdays { return match.ordinal }
                if case .nth(let n, _) = schedule.rule.weekdays.first { return n }
                return 1
            },
            set: { newOrdinal in
                let days = effectiveMonthlyWeekdays
                onChange(.monthlyMatching(
                    ordinal: newOrdinal,
                    weekdays: days,
                    hour: schedule.rule.hours.first ?? 9,
                    minute: schedule.rule.minutes.first ?? 0
                ))
            }
        )
    }

    private var effectiveMonthlyWeekdays: Set<Locale.Weekday> {
        if let match = schedule.matchingWeekdays { return match.weekdays }
        if let day = schedule.rule.weekdays.first?.localeWeekday { return [day] }
        return [.monday]
    }

    private func monthlyWeekdayToggle(day: Locale.Weekday, selected: Set<Locale.Weekday>) -> Binding<Bool> {
        Binding(
            get: { selected.contains(day) },
            set: { isOn in
                var newDays = selected
                if isOn {
                    newDays.insert(day)
                } else if newDays.count > 1 {
                    newDays.remove(day)
                }
                let ordinal = schedule.matchingWeekdays?.ordinal ?? {
                    if case .nth(let n, _) = schedule.rule.weekdays.first { return n }
                    return 1
                }()
                onChange(.monthlyMatching(
                    ordinal: ordinal,
                    weekdays: newDays,
                    hour: schedule.rule.hours.first ?? 9,
                    minute: schedule.rule.minutes.first ?? 0
                ))
            }
        )
    }

    // MARK: - Yearly Controls

    @ViewBuilder
    private var yearlyControls: some View {
        if schedule.rule.frequency == .yearly {
            Picker("Month", selection: yearlyMonthBinding) {
                ForEach(1...12, id: \.self) { m in
                    Text(Calendar.current.monthSymbols[m - 1]).tag(m)
                }
            }
            Picker("Day", selection: yearlyDayBinding) {
                ForEach(1...31, id: \.self) { d in
                    Text("\(d)").tag(d)
                }
            }
        }
    }

    private var yearlyMonthBinding: Binding<Int> {
        Binding(
            get: { schedule.rule.months.first?.index ?? 1 },
            set: { m in
                var updated = schedule
                updated.rule.months = [Calendar.RecurrenceRule.Month(m)]
                onChange(updated)
            }
        )
    }

    private var yearlyDayBinding: Binding<Int> {
        Binding(
            get: { schedule.rule.daysOfTheMonth.first ?? 1 },
            set: { d in
                var updated = schedule
                updated.rule.daysOfTheMonth = [d]
                onChange(updated)
            }
        )
    }
}
