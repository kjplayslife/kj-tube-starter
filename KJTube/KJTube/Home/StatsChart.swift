import Charts
import SwiftUI

/// Screen Time style stats (D147): the week's daily average, how it compares with the week
/// before, and one bar per day. Arrows step back through older weeks.
/// Sits at the top of the Inbox ⓘ page (D149).
struct StatsChart: View {
    @Environment(AppStore.self) private var store
    @State private var weeksAgo = 0
    @State private var selected: Date?

    var body: some View {
        let engine = store.engine
        let now = Date.now
        let week = engine.weekStats(weeksAgo: weeksAgo, now: now)
        let change = week.change(from: engine.weekStats(weeksAgo: weeksAgo + 1, now: now))
        let oldest = engine.oldestStatsWeek(now: now)
        let picked = selected.flatMap { s in week.days.first { engine.calendar.isDate($0.date, inSameDayAs: s) } }

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(picked.map { $0.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) } ?? "Daily Average")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                weekStepper(week, oldest: oldest)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Self.short(picked?.watched ?? week.dailyAverage))
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .contentTransition(.numericText())
                if let picked {
                    Text("of \(Self.short(picked.budget))")
                        .font(.footnote)
                        .foregroundStyle(picked.isOver ? Color.orange : .secondary)
                } else if let change, abs(change) >= 0.005 {
                    Label(
                        "\(Int((abs(change) * 100).rounded()))% from \(weeksAgo == 0 ? "last week" : "the week before")",
                        systemImage: change < 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }

            chart(week, picked: picked)
        }
        .padding(.vertical, 6)
        .animation(.snappy, value: weeksAgo)
    }

    private func weekStepper(_ week: WeekStats, oldest: Int) -> some View {
        HStack(spacing: 10) {
            Button { step(1) } label: { Image(systemName: "chevron.left") }
                .disabled(weeksAgo >= oldest)
                .accessibilityLabel("Earlier week")
            Text(Self.weekLabel(week, weeksAgo: weeksAgo))
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
            Button { step(-1) } label: { Image(systemName: "chevron.right") }
                .disabled(weeksAgo == 0)
                .accessibilityLabel("Later week")
        }
        // Without this, a tap anywhere on the Form row presses both arrows.
        .buttonStyle(.borderless)
    }

    private func step(_ by: Int) {
        selected = nil
        weeksAgo += by
    }

    private func chart(_ week: WeekStats, picked: WeekStats.Day?) -> some View {
        Chart {
            ForEach(week.days) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Watched", day.watched / 60),
                    width: .ratio(0.6)
                )
                .foregroundStyle((day.isOver ? Color.orange : Color.accentColor).opacity(picked == nil || picked == day ? 1 : 0.35))
                .cornerRadius(4)
            }
            if week.dailyAverage > 0 {
                RuleMark(y: .value("Average", week.dailyAverage / 60))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.green)
                    .annotation(position: .top, alignment: .trailing, spacing: 2) {
                        Text("avg").font(.caption2).foregroundStyle(.green)
                    }
            }
        }
        .chartXSelection(value: $selected)
        .chartXScale(domain: week.days[0].date...week.days[6].date.addingTimeInterval(86_400))
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel { if let m = value.as(Double.self) { Text("\(Int(m))m") } }
            }
        }
        .frame(height: 150)
    }

    /// "42m", "1h 5m", "2h": the compact style Screen Time uses.
    static func short(_ seconds: TimeInterval) -> String {
        let total = Int((seconds / 60).rounded())
        if total < 60 { return "\(total)m" }
        return total % 60 == 0 ? "\(total / 60)h" : "\(total / 60)h \(total % 60)m"
    }

    static func weekLabel(_ week: WeekStats, weeksAgo: Int) -> String {
        switch weeksAgo {
        case 0: "This Week"
        case 1: "Last Week"
        default: "\(Self.day(week.days[0].date)) – \(Self.day(week.days[6].date))"
        }
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }
}
