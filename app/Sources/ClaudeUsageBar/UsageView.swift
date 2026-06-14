import SwiftUI
import UsageCore

/// The popover contents: the two usage-limit cards and a footer.
struct UsageView: View {
    @ObservedObject var model: UsageModel
    var onQuit: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 12) {
                header
                limitsSection
                usageSection
                Divider()
                footer
            }
            .padding(16)
            ClawdPeeker()
        }
        .frame(width: 340)
        .background(Palette.cream)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var header: some View {
        Text("CLAUDE USAGE")
            .font(.caption2).bold()
            .tracking(1.5)
            .foregroundColor(Palette.clay)
    }

    @ViewBuilder
    private var limitsSection: some View {
        switch model.snapshot.state {
        case .ok(let limits):
            ForEach(Array(limitLabels.enumerated()), id: \.offset) { _, entry in
                if let limit = limits[keyPath: entry.keyPath] {
                    LimitCard(label: entry.label, limit: limit)
                }
            }
        case .fetchError:
            MessageCard(text: "Couldn't refresh limits — will retry.", tint: Palette.inkDim)
        case .authError:
            MessageCard(text: "Sign in to Claude Code (run claude, then /login).", tint: Palette.color(for: .high))
        }
    }

    /// Token usage from local transcripts — always shown, independent of the
    /// limits fetch (so it stays useful even when the API is rate-limited).
    private var usageSection: some View {
        let today = sumModelCounts(model.snapshot.todayByModel)
        let active = model.snapshot.activeSessions
        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Today")
            StatsCard(title: "\(grouped(today.total)) tokens",
                      detail: breakdownLine(today))
            sectionHeader("Active sessions · \(active.count)")
            SessionsCard(sessions: active)
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption)
            .foregroundColor(Palette.inkDim)
    }

    private var footer: some View {
        HStack {
            Button {
                model.refresh(force: true)
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(model.isRefreshing)
            Spacer()
            Button("Quit", action: onQuit)
        }
        .buttonStyle(.plain)
        .font(.callout)
        .foregroundColor(Palette.ink)
    }
}

/// A tinted rounded card for one limit, with a severity accent bar and bar gauge.
struct LimitCard: View {
    let label: String
    let limit: Limit

    private var severity: Severity { severityLevel(limit.utilization) }
    private var tint: Color { Palette.color(for: severity) }

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tint)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(label)
                        .font(.system(.body, design: .rounded).bold())
                        .foregroundColor(Palette.ink)
                    Spacer()
                    Text("\(Int(limit.utilization.rounded()))%")
                        .font(.system(.body, design: .rounded).bold())
                        .foregroundColor(tint)
                }
                ProgressBar(fraction: min(limit.utilization, 100) / 100, tint: tint)
                Text(formatReset(limit.resetsAt))
                    .font(.caption)
                    .foregroundColor(Palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(tint.opacity(0.18)))
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
                    .fill(Palette.ink.opacity(0.12))
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, geo.size.width * fraction))
            }
        }
        .frame(height: 6)
    }
}

/// Per-session usage with tab switching: a tab per active session (plus "All"
/// for the combined total when there's more than one), showing the selected
/// session's tokens and in/out/cache breakdown.
struct SessionsCard: View {
    let sessions: [SessionSummary]
    @State private var selectedIndex = 0

    /// The switchable views: "All" (combined) first when there are several,
    /// then one per session.
    private var entries: [(label: String, counts: Counts)] {
        var result: [(String, Counts)] = []
        if sessions.count > 1 {
            let combined = sessions.reduce(into: zeroCounts()) { $0.add($1.counts) }
            result.append(("All", combined))
        }
        result.append(contentsOf: sessions.map { ($0.label, $0.counts) })
        return result
    }

    private var safeIndex: Int {
        min(max(selectedIndex, 0), max(entries.count - 1, 0))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if entries.isEmpty {
                Text("No active sessions")
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(Palette.inkDim)
            } else {
                if entries.count > 1 {
                    FlowLayout(spacing: 6) {
                        ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                            SessionTab(
                                label: entry.label,
                                selected: index == safeIndex,
                                action: { selectedIndex = index })
                        }
                    }
                }
                let entry = entries[safeIndex]
                Text(entry.label.uppercased())
                    .font(.caption2)
                    .foregroundColor(Palette.inkDim)
                    .lineLimit(1)
                Text("\(grouped(entry.counts.total)) tokens")
                    .font(.system(.body, design: .rounded).bold())
                    .foregroundColor(Palette.ink)
                Text(breakdownLine(entry.counts))
                    .font(.caption)
                    .foregroundColor(Palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Palette.panel))
    }
}

/// A left-aligned flow layout that wraps its subviews onto new rows — used so
/// any number of session tabs fits the fixed-width popover without scrolling.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(maxWidth, widest), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// A pill tab for one session; clay when selected, cream otherwise.
struct SessionTab: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption).bold()
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selected ? Palette.clay : Palette.cream))
                .foregroundColor(selected ? Palette.cream : Palette.ink)
        }
        .buttonStyle(.plain)
    }
}

/// A token-total card: bold total with a dim in/out/cache breakdown.
struct StatsCard: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(.body, design: .rounded).bold())
                .foregroundColor(Palette.ink)
            Text(detail)
                .font(.caption)
                .foregroundColor(Palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Palette.panel))
    }
}

/// A simple message card for the error / auth states.
struct MessageCard: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(.body, design: .rounded))
            .foregroundColor(tint)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Palette.panel))
    }
}
