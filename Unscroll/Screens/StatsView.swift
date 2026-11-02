import Charts
import SwiftData
import SwiftUI
import UnscrollKit

struct StatsView: View {
    @Query(sort: \WorkoutRecord.date, order: .reverse) private var records: [WorkoutRecord]

    private struct DayTotal: Identifiable {
        let day: Date
        let exercise: Exercise
        let units: Int
        var id: String { "\(day.timeIntervalSince1970)-\(exercise.rawValue)" }
    }

    private var lastSevenDays: [DayTotal] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var totals: [DayTotal] = []
        for offset in (0..<7).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            for exercise in Exercise.allCases {
                let units = records
                    .filter { calendar.isDate($0.date, inSameDayAs: day) && $0.exercise == exercise }
                    .reduce(0) { $0 + $1.units }
                totals.append(DayTotal(day: day, exercise: exercise, units: units))
            }
        }
        return totals
    }

    private var activeDays: Set<Date> { Set(records.map(\.date)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        tile("\(Streaks.current(activeDays: activeDays, today: .now))", "current streak")
                        tile("\(Streaks.longest(activeDays: activeDays))", "longest streak")
                    }
                    HStack(spacing: 12) {
                        tile("\(records.reduce(0) { $0 + $1.units })", "total reps")
                        tile("\(records.reduce(0) { $0 + $1.earnedSeconds } / 60)", "minutes earned")
                    }

                    Card {
                        Text("Last 7 days").font(.headline)
                        Chart(lastSevenDays) { item in
                            BarMark(x: .value("Day", item.day, unit: .day),
                                    y: .value("Reps", item.units))
                                .foregroundStyle(by: .value("Exercise", item.exercise.title))
                                .clipShape(.rect(cornerRadius: 4))
                        }
                        .chartForegroundStyleScale([
                            Exercise.pushups.title: Theme.accent,
                            Exercise.squats.title: Color.cyan,
                            Exercise.plank.title: Color.orange,
                        ])
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day)) { _ in
                                AxisValueLabel(format: .dateTime.weekday(.narrow))
                            }
                        }
                        .frame(height: 200)
                    }

                    if !records.isEmpty {
                        Card {
                            Text("Recent").font(.headline)
                            ForEach(records.prefix(10)) { record in
                                HStack {
                                    Image(systemName: record.exercise.symbolName)
                                        .foregroundStyle(Theme.accent)
                                        .frame(width: 28)
                                    VStack(alignment: .leading) {
                                        Text("\(record.units) \(record.exercise == .plank ? "s" : "×") \(record.exercise.title)")
                                            .font(.subheadline.weight(.semibold))
                                        Text(record.date.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(Theme.secondaryText)
                                    }
                                    Spacer()
                                    Text(formatEarned(record.earnedSeconds))
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("Stats")
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(Theme.number(32))
            Text(label).font(.caption).foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 20))
    }
}
