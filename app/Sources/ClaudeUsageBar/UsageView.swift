import SwiftUI
import UsageCore

/// The popover contents: limit cards, today/session cards, footer.
struct UsageView: View {
    @ObservedObject var model: UsageModel
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            limitsSection
            statsSection
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 340)
    }

    // MARK: Limits

    @ViewBuilder
    private var limitsSection: some View {
        switch model.snapshot.state {
        case .ok(let limits):
            sectionHeader("Limits")
            ForEach(Array(limitLabels.enumerated()), id: \.offset) { _, entry in
                if let limit = limits[keyPath: entry.keyPath] {
                    LimitCard(label: entry.label, limit: limit)
                }
            }
        case .fetchError:
            sectionHeader("Limits")
            ErrorCard(
                title: "Failed to fetch usage limits",
                cache: model.snapshot.cache)
        case .authError:
            sectionHeader("Limits")
            ErrorCard(
                title: "Sign in to Claude Code (run claude, then /login)",
                cache: model.snapshot.cache)
        }
    }

    // MARK: Stats

    private var statsSection: some View {
        let todayTotals = sumModelCounts(model.snapshot.todayByModel)
        let session = model.snapshot.sessionTotals
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Today")
            StatsCard(
                title: "\(grouped(todayTotals.total)) tokens today",
                detail: breakdownLine(todayTotals),
                costRow: costRow(perModel: model.snapshot.todayByModel))
            sectionHeader("Latest session")
            StatsCard(
                title: "\(grouped(session.total)) tokens",
                detail: breakdownLine(session),
                costRow: nil)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button {
                model.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(model.isRefreshing)
            Spacer()
            Button("Quit", action: onQuit)
        }
        .buttonStyle(.plain)
        .font(.callout)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption)
            .foregroundColor(.secondary)
    }
}

/// A tinted rounded card for one limit, with a severity accent bar and bar gauge.
struct LimitCard: View {
    let label: String
    let limit: Limit

    private var severity: Severity { severityColor(limit.utilization) }
    private var tint: Color { color(for: severity) }

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tint)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(label)
                        .font(.system(.body, design: .rounded).bold())
                        .foregroundColor(tint)
                    Spacer()
                    Text("\(Int(limit.utilization.rounded()))%")
                        .font(.system(.body, design: .rounded).bold())
                        .foregroundColor(tint)
                }
                ProgressBar(fraction: min(limit.utilization, 100) / 100, tint: tint)
                Text("resets \(formatResetTime(limit.resetsAt))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(tint.opacity(0.12)))
    }
}

/// A capsule progress bar tinted by severity.
struct ProgressBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(tint.opacity(0.2))
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, geo.size.width * fraction))
            }
        }
        .frame(height: 6)
    }
}

/// Token total card with dim detail and optional orange cost row.
struct StatsCard: View {
    let title: String
    let detail: String
    let costRow: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(.body, design: .rounded).bold())
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
            if let costRow = costRow {
                Text(costRow)
                    .font(.caption)
                    .foregroundColor(costColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08)))
    }
}

/// Error/auth card showing the message plus cached values or a hint.
struct ErrorCard: View {
    let title: String
    let cache: CacheState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(.body, design: .rounded).bold())
                .foregroundColor(.red)
            cacheLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.1)))
    }

    @ViewBuilder
    private var cacheLine: some View {
        switch cache {
        case .fresh(let limits, let ageSeconds):
            Text("Cached: \(slot(limits.fiveHour)) · \(slot(limits.sevenDay)) (\(formatAge(ageSeconds)) ago)")
                .font(.caption)
                .foregroundColor(.secondary)
        case .missing:
            Text("no cached data yet")
                .font(.caption)
                .foregroundColor(.secondary)
        case .stale:
            EmptyView()
        }
    }

    private func slot(_ limit: Limit?) -> String {
        guard let limit = limit else {
            return "–"
        }
        return "\(Int(limit.utilization.rounded()))%"
    }
}
