// ContentView.swift
import SwiftUI

// MARK: - Content View
struct ContentView: View {
    @StateObject private var session = WatchSessionManager.shared

    var body: some View {
        switch session.syncState {
        case .waiting:
            WaitingSyncView()
        case .synced:
            HomeWatchView()
        }
    }
}
// Dung nhat quan cho ca WaitingSyncView va HomeWatchView
private var watchBackground: Color {
    Color(red: 0.92, green: 0.95, blue: 0.94)
}

// MARK: - Waiting Sync View
struct WaitingSyncView: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            watchBackground
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(BrandColor.primary.opacity(0.2), lineWidth: 3)
                        .frame(width: 52, height: 52)
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(BrandColor.primary, lineWidth: 3)
                        .frame(width: 52, height: 52)
                        .rotationEffect(.degrees(isAnimating ? 360 : 0))
                        .animation(
                            .linear(duration: 1.2).repeatForever(
                                autoreverses: false
                            ),
                            value: isAnimating
                        )
                    Image(systemName: "iphone.and.arrow.forward.inward")
                        .font(.system(size: 18))
                        .foregroundStyle(BrandColor.primary)
                }

                Text("Waiting for iPhone")
                    .font(.headline)
                    .foregroundStyle(.black)

                Text("Open VSTEP Writing on your iPhone to sync data")
                    .font(.caption2)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
            }
            .padding(16)
            .glassEffect(in: .rect(cornerRadius: 16.0))
            .padding(.horizontal, 8)
            .onAppear { isAnimating = true }
        }
    }
}

// MARK: - Home Watch View
struct HomeWatchView: View {
    @StateObject private var session = WatchSessionManager.shared

    var body: some View {
        ZStack {
            // iOS systemGroupedBackground light mode equivalent
            watchBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 10) {
                    greetingSection
                    scoreHeaderSection
                    if session.scoreHistory.count >= 2 {
                        scoreTrendChartSection
                    }
                    recentActivitySection
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Greeting
    private var greetingSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            (Text("Hello, ")
                .foregroundStyle(.black)
                + Text(session.displayName)
                .foregroundStyle(BrandColor.primary)
                + Text("!")
                .foregroundStyle(.black))
                .font(.headline)
            Text("Ready to write?")
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .glassEffect(in: .rect(cornerRadius: 16.0))
    }

    // MARK: - Score Header
    private var scoreHeaderSection: some View {
        VStack(spacing: 8) {
            Text("Overall Score")
                .font(.caption2)
                .foregroundStyle(.gray)

            if let avg = session.averageScore {
                Text(String(format: "%.1f", avg))
                    .font(.system(size: 36, weight: .bold).monospacedDigit())
                    .foregroundStyle(scoreColor(avg))
                    .contentTransition(.numericText())
            } else {
                Text("—")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.gray)
            }

            HStack(spacing: 12) {
                WatchStatChip(
                    icon: "doc.text.fill",
                    value: "\(session.totalSubmissions)",
                    label: "Total",
                    color: BrandColor.primary
                )
                WatchStatChip(
                    icon: "1.circle.fill",
                    value: "\(session.task1Count)",
                    label: "Task 1",
                    color: BrandColor.light
                )
                WatchStatChip(
                    icon: "2.circle.fill",
                    value: "\(session.task2Count)",
                    label: "Task 2",
                    color: BrandColor.medium
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .glassEffect(in: .rect(cornerRadius: 16.0))
    }

    // MARK: - Score Trend Chart
    private var scoreTrendChartSection: some View {
        WatchScoreTrendChart(entries: session.scoreHistory)
    }

    // MARK: - Recent Activity
    @ViewBuilder
    private var recentActivitySection: some View {
        if !session.recentTopics.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Recent", systemImage: "clock")
                    .font(.caption.bold())
                    .foregroundStyle(BrandColor.primary)
                    .padding(.horizontal, 4)

                ForEach(Array(session.recentTopics.enumerated()), id: \.offset)
                { index, topic in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(BrandColor.primary)
                            .frame(width: 3, height: 32)
                        Text(topic)
                            .font(.caption)
                            .foregroundStyle(.black)
                            .lineLimit(2)
                        Spacer()
                        if index < session.recentScores.count {
                            Text(
                                String(
                                    format: "%.1f",
                                    session.recentScores[index]
                                )
                            )
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(
                                scoreColor(session.recentScores[index])
                            )
                        }
                    }
                    .padding(8)
                    .glassEffect(in: .rect(cornerRadius: 16.0))
                }
            }
        }
    }

    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 8...: return .green
        case 6..<8: return .orange
        default: return .red
        }
    }
}

// MARK: - Watch Stat Chip
struct WatchStatChip: View {
    let icon: String
    let value: String
    let label: String
    var color: Color = BrandColor.primary

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.caption2)
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(.black)
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(.gray)
        }
    }
}

// MARK: - Watch Score Trend Chart (mirrors iOS ScoreTrendSection Canvas style)
struct WatchScoreTrendChart: View {
    let entries: [ScoreEntry]

    @State private var selectedIndex: Int? = nil

    private let yMarks: [Double] = [0, 5, 10]
    private let chartHeight: CGFloat = 90
    private let leftPad: CGFloat = 20
    private let rightPad: CGFloat = 8
    private let topPad: CGFloat = 16
    private let bottomPad: CGFloat = 8

    private var hasTask1: Bool {
        entries.contains { $0.taskType == "task1" }
    }

    private var hasTask2: Bool {
        entries.contains { $0.taskType == "task2" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header with trend
            HStack {
                Label("Score Trend", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.caption.bold())
                    .foregroundStyle(BrandColor.primary)
                Spacer()
                if let trend = scoreTrend {
                    Label(
                        String(format: "%.1f", abs(trend)),
                        systemImage: trend >= 0
                            ? "arrow.up.right" : "arrow.down.right"
                    )
                    .font(.system(size: 9).bold())
                    .foregroundStyle(trend >= 0 ? .green : .red)
                }
            }
            .padding(.horizontal, 4)

            // Canvas chart — same rendering logic as iOS ScoreTrendSection
            ZStack(alignment: .topLeading) {
                // Y-axis labels
                GeometryReader { geo in
                    let drawH = geo.size.height - topPad - bottomPad
                    ForEach(yMarks, id: \.self) { mark in
                        let yPos = topPad + drawH * (1 - mark / 10)
                        Text("\(Int(mark))")
                            .font(.system(size: 8, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                            .position(x: 8, y: yPos)
                    }
                }

                // Canvas: grid, area, line, dots — mirrors iOS exactly
                Canvas { context, size in
                    let scores = entries.map(\.score)
                    guard scores.count > 1 else { return }

                    let w = size.width
                    let h = size.height
                    let drawW = w - leftPad - rightPad
                    let drawH = h - topPad - bottomPad
                    let xStep = drawW / CGFloat(scores.count - 1)

                    func point(index: Int, score: Double) -> CGPoint {
                        CGPoint(
                            x: leftPad + CGFloat(index) * xStep,
                            y: topPad + drawH * (1 - CGFloat(score) / 10)
                        )
                    }

                    // Grid lines
                    for mark in yMarks {
                        let y = topPad + drawH * (1 - CGFloat(mark) / 10)
                        var gridLine = Path()
                        gridLine.move(to: CGPoint(x: leftPad, y: y))
                        gridLine.addLine(to: CGPoint(x: w - rightPad, y: y))
                        context.stroke(
                            gridLine,
                            with: .color(Color.secondary.opacity(0.12)),
                            style: StrokeStyle(lineWidth: 0.5, dash: [4, 3])
                        )
                    }

                    // Area fill — same gradient as iOS
                    var area = Path()
                    area.move(to: CGPoint(x: leftPad, y: topPad + drawH))
                    for (i, score) in scores.enumerated() {
                        area.addLine(to: point(index: i, score: score))
                    }
                    area.addLine(
                        to: CGPoint(
                            x: leftPad + CGFloat(scores.count - 1) * xStep,
                            y: topPad + drawH
                        )
                    )
                    area.closeSubpath()
                    context.fill(
                        area,
                        with: .linearGradient(
                            Gradient(colors: [
                                BrandColor.primary.opacity(0.18),
                                BrandColor.primary.opacity(0.02),
                            ]),
                            startPoint: CGPoint(x: 0, y: 0),
                            endPoint: CGPoint(x: 0, y: h)
                        )
                    )

                    // Line — same stroke style as iOS
                    var line = Path()
                    for (i, score) in scores.enumerated() {
                        let p = point(index: i, score: score)
                        i == 0 ? line.move(to: p) : line.addLine(to: p)
                    }
                    context.stroke(
                        line,
                        with: .color(BrandColor.primary),
                        style: StrokeStyle(
                            lineWidth: 2.5,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )

                    // Dots colored by task type — same as iOS dotColor logic
                    for (i, entry) in entries.enumerated() {
                        let p = point(index: i, score: entry.score)
                        let isSelected = selectedIndex == i
                        let dotSize: CGFloat = isSelected ? 8 : 5
                        let glowSize: CGFloat = isSelected ? 14 : 10

                        context.fill(
                            Path(
                                ellipseIn: CGRect(
                                    x: p.x - glowSize / 2,
                                    y: p.y - glowSize / 2,
                                    width: glowSize,
                                    height: glowSize
                                )
                            ),
                            with: .color(
                                entry.dotColor.opacity(isSelected ? 0.35 : 0.2)
                            )
                        )
                        context.fill(
                            Path(
                                ellipseIn: CGRect(
                                    x: p.x - dotSize / 2,
                                    y: p.y - dotSize / 2,
                                    width: dotSize,
                                    height: dotSize
                                )
                            ),
                            with: .color(entry.dotColor)
                        )

                        // Tooltip bubble khi tap — same style as iOS
                        if isSelected {
                            let text = Text(String(format: "%.1f", entry.score))
                                .font(.system(size: 10, weight: .bold))
                                .monospacedDigit()
                                .foregroundColor(.white)
                            let resolved = context.resolve(text)
                            let textSize = resolved.measure(
                                in: CGSize(width: 40, height: 20)
                            )
                            let labelW = textSize.width + 10
                            let labelH = textSize.height + 6
                            let labelY = p.y - labelH - 8

                            let bubbleRect = CGRect(
                                x: p.x - labelW / 2,
                                y: labelY,
                                width: labelW,
                                height: labelH
                            )
                            context.fill(
                                Path(roundedRect: bubbleRect, cornerRadius: 5),
                                with: .color(entry.dotColor)
                            )

                            var arrow = Path()
                            arrow.move(
                                to: CGPoint(x: p.x - 3, y: labelY + labelH)
                            )
                            arrow.addLine(
                                to: CGPoint(x: p.x, y: labelY + labelH + 4)
                            )
                            arrow.addLine(
                                to: CGPoint(x: p.x + 3, y: labelY + labelH)
                            )
                            arrow.closeSubpath()
                            context.fill(arrow, with: .color(entry.dotColor))

                            context.draw(
                                resolved,
                                at: CGPoint(x: p.x, y: labelY + labelH / 2),
                                anchor: .center
                            )
                        }
                    }
                }
                .frame(height: chartHeight)

                // Tap gesture overlay
                GeometryReader { geo in
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            let count = entries.count
                            guard count > 1 else { return }
                            let drawW = geo.size.width - leftPad - rightPad
                            let xStep = drawW / CGFloat(count - 1)
                            let relX = location.x - leftPad
                            let idx = Int((relX / xStep).rounded())
                            let clamped = max(0, min(count - 1, idx))
                            withAnimation(.easeOut(duration: 0.15)) {
                                selectedIndex =
                                    selectedIndex == clamped ? nil : clamped
                            }
                        }
                }
                .frame(height: chartHeight)
            }

            // X-axis date labels — mirrors iOS
            HStack {
                if let first = entries.first {
                    Text(
                        first.date,
                        format: .dateTime.day().month(.abbreviated)
                    )
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if let last = entries.last {
                    Text(last.date, format: .dateTime.day().month(.abbreviated))
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)

            // Legend — mirrors iOS legend
            if hasTask1 || hasTask2 {
                HStack(spacing: 12) {
                    Spacer()
                    if hasTask1 {
                        HStack(spacing: 4) {
                            Circle().fill(BrandColor.light).frame(
                                width: 6,
                                height: 6
                            )
                            Text("Task 1").font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if hasTask2 {
                        HStack(spacing: 4) {
                            Circle().fill(BrandColor.medium).frame(
                                width: 6,
                                height: 6
                            )
                            Text("Task 2").font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            }
        }
        .padding(10)
        .glassEffect(in: .rect(cornerRadius: 16.0))
    }

    // Trend: compare last 3 vs previous 3 (same logic as iOS)
    private var scoreTrend: Double? {
        guard entries.count >= 2 else { return nil }
        let latest = entries.prefix(3).map(\.score)
        let previous = entries.dropFirst(3).prefix(3).map(\.score)
        guard !previous.isEmpty else { return nil }
        let latestAvg = latest.reduce(0, +) / Double(latest.count)
        let previousAvg = previous.reduce(0, +) / Double(previous.count)
        return latestAvg - previousAvg
    }
}
