import SwiftUI

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

// MARK: - Waiting Sync View
struct WaitingSyncView: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.2), lineWidth: 3)
                    .frame(width: 52, height: 52)
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(Color.blue, lineWidth: 3)
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
                    .foregroundStyle(.blue)
            }

            Text("Waiting for iPhone")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("Open VSTEP Writing on your iPhone to sync data")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .glassEffect(in: .rect(cornerRadius: 16.0))
        .padding(.horizontal, 8)
        .onAppear { isAnimating = true }
    }
}

// MARK: - Home Watch View (only shown after sync)
struct HomeWatchView: View {
    @StateObject private var session = WatchSessionManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                greetingSection
                scoreSection
                recentActivitySection
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Greeting
    private var greetingSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Hello, \(session.displayName)!")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("Ready to write?")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .glassEffect(in: .rect(cornerRadius: 16.0))
    }

    // MARK: - Score
    private var scoreSection: some View {
        HStack(spacing: 8) {
            VStack(spacing: 2) {
                if let avg = session.averageScore {
                    Text(String(format: "%.1f", avg))
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(scoreColor(avg))
                    Text("Avg Score")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("--")
                        .font(.title2.bold())
                        .foregroundStyle(.secondary)
                    Text("No Score")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .glassEffect(in: .rect(cornerRadius: 16.0))

            VStack(spacing: 2) {
                Text("\(session.totalSubmissions)")
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(.blue)
                Text("Essays")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .glassEffect(in: .rect(cornerRadius: 16.0))
        }
    }

    // MARK: - Recent Activity
    @ViewBuilder
    private var recentActivitySection: some View {
        if !session.recentTopics.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recent")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                ForEach(Array(session.recentTopics.enumerated()), id: \.offset)
                { index, topic in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.blue)
                            .frame(width: 3, height: 32)
                        Text(topic)
                            .font(.caption)
                            .foregroundStyle(.primary)
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
