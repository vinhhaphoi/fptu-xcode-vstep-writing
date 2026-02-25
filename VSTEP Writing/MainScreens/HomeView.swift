// HomeView.swift
import SwiftUI
import FirebaseAuth

// MARK: - HomeView
struct HomeView: View {
    @StateObject private var firebaseService = FirebaseService.shared
    @EnvironmentObject var authManager: AuthenticationManager

    @State private var recentSubmissions: [UserSubmission] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedAction: QuickActionType?

    private var displayName: String {
        let user = Auth.auth().currentUser
        return user?.displayName
            ?? user?.email?.components(separatedBy: "@").first
            ?? "Learner"
    }

    private var averageScore: Double? {
        let scores = recentSubmissions.compactMap(\.score)
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                HomeGreetingSection(
                    displayName: displayName,
                    questionsAvailable: firebaseService.questions.count
                )

                if isLoading {
                    LoadingView()
                } else if let error = errorMessage {
                    ErrorBannerView(message: error) {
                        Task { await loadData() }
                    }
                } else {
                    StatsRowSection(
                        totalSubmissions: recentSubmissions.count,
                        averageScore: averageScore
                    )

                    PrimaryActionCard { selectedAction = .practice }

                    SecondaryActionsRow { selectedAction = $0 }

                    RecentActivitySection(
                        submissions: recentSubmissions,
                        questionMap: firebaseService.questionMap
                    )
                }

                Spacer(minLength: 50)
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await loadData() }
        .task { await loadData() }
        // Single navigationDestination at top level to avoid navigation stack conflicts
        .navigationDestination(item: $selectedAction) { actionType in
            switch actionType {
            case .practice: LearnView()
            case .myScores: ScoreView()
            case .grammar:  GrammarView()
            case .tips:     TipsView()
            }
        }
    }

    private func loadData() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await firebaseService.fetchQuestions()
            guard firebaseService.currentUserId != nil else { return }
            try? await firebaseService.fetchUserProgress()
            recentSubmissions = try await firebaseService.fetchUserSubmissions()
        } catch {
            errorMessage = "Failed to load data. Pull down to retry."
            print("[HomeView] loadData error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Greeting Header
struct HomeGreetingSection: View {
    let displayName: String
    let questionsAvailable: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hello, \(displayName)!")
                .font(.title2.bold())
                .foregroundStyle(.primary)

            Text(
                questionsAvailable > 0
                    ? "\(questionsAvailable) questions ready for you"
                    : "Keep practising your writing"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }
}

// MARK: - Stats Row
struct StatsRowSection: View {
    let totalSubmissions: Int
    let averageScore: Double?

    var body: some View {
        HStack(spacing: 12) {
            StatPill(
                icon: "doc.text.fill",
                iconColor: .blue,
                value: "\(totalSubmissions)",
                label: "Essays"
            )
            StatPill(
                icon: "star.fill",
                iconColor: .yellow,
                value: averageScore.map { String(format: "%.1f", $0) } ?? "-",
                label: "Avg Score"
            )
            StatPill(
                icon: "flame.fill",
                iconColor: .orange,
                value: "-",
                label: "Streak"
            )
        }
        .padding(.horizontal)
    }
}

struct StatPill: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(iconColor)
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Primary Action Card
struct PrimaryActionCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Start Writing", systemImage: "pencil.and.outline")
                        .font(.title3.bold())
                        .foregroundStyle(.white)

                    Text("Practise VSTEP Task 1 & Task 2 essays")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(20)
            .background(
                LinearGradient(
                    colors: [.blue, Color(hue: 0.65, saturation: 0.8, brightness: 0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
}

// MARK: - Secondary Actions Row
struct SecondaryActionsRow: View {
    let onSelect: (QuickActionType) -> Void

    private let actions: [(icon: String, color: Color, title: String, type: QuickActionType)] = [
        ("book.closed.fill",  .green,  "Grammar",  .grammar),
        ("chart.bar.fill",    .purple, "Progress", .myScores),
        ("lightbulb.fill",    .yellow, "Tips",     .tips),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Explore")
                .font(.headline)
                .padding(.horizontal)

            HStack(spacing: 12) {
                ForEach(actions, id: \.title) { action in
                    Button { onSelect(action.type) } label: {
                        VStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(action.color.opacity(0.12))
                                    .frame(width: 52, height: 52)
                                Image(systemName: action.icon)
                                    .font(.title3)
                                    .foregroundStyle(action.color)
                            }
                            Text(action.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Quick Action Type
enum QuickActionType: String, Identifiable {
    case practice = "Practice"
    case myScores = "My Scores"
    case grammar  = "Grammar"
    case tips     = "Tips"

    var id: String { rawValue }
}

// MARK: - Recent Activity Section
struct RecentActivitySection: View {
    let submissions: [UserSubmission]
    let questionMap: [String: VSTEPQuestion]

    // Keep only the most recent submission per question, assuming descending sort from Firestore
    private var uniqueSubmissions: [UserSubmission] {
        var seen = Set<String>()
        return submissions.filter { seen.insert($0.questionId).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent Activity")
                    .font(.headline)
                Spacer()
                if !uniqueSubmissions.isEmpty {
                    NavigationLink(destination: ScoreView()) {
                        Text("See All")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding(.horizontal)

            if uniqueSubmissions.isEmpty {
                EmptyActivityView()
            } else {
                VStack(spacing: 10) {
                    ForEach(uniqueSubmissions.prefix(5)) { submission in
                        ActivityRow(
                            submission: submission,
                            question: questionMap[submission.questionId]
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Activity Row
struct ActivityRow: View {
    let submission: UserSubmission
    let question: VSTEPQuestion?

    private var scoreText: String? {
        guard let score = submission.score else { return nil }
        return String(format: "%.1f", score)
    }

    private var scoreColor: Color {
        guard let score = submission.score else { return .secondary }
        switch score {
        case 8...:  return .green
        case 6..<8: return .orange
        default:    return .red
        }
    }

    private var taskBadgeText: String {
        switch question?.taskType {
        case "task1": return "Task 1"
        case "task2": return "Task 2"
        default:      return "Essay"
        }
    }

    private var taskBadgeColor: Color {
        question?.taskType == "task1" ? .blue : .purple
    }

    private var difficultyColor: Color {
        switch question?.difficulty.lowercased() {
        case "easy":   return .green
        case "medium": return .orange
        case "hard":   return .red
        default:       return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            // Left accent bar distinguishes task type at a glance
            RoundedRectangle(cornerRadius: 3)
                .fill(taskBadgeColor)
                .frame(width: 4, height: 64)

            VStack(alignment: .leading, spacing: 6) {
                Text(question?.title ?? submission.questionId.uppercased())
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    BadgeView(text: taskBadgeText, color: taskBadgeColor)

                    if let difficulty = question?.difficulty {
                        BadgeView(text: difficulty.capitalized, color: difficultyColor)
                    }

                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text(submission.submittedAt, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 8)

            // Show numeric score when available, otherwise display status icon
            VStack(spacing: 2) {
                if let scoreText = scoreText {
                    Text(scoreText)
                        .font(.title3.bold().monospacedDigit())
                        .foregroundColor(scoreColor)
                    Text("/ 10")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    StatusBadgeView(status: submission.status)
                }
            }
            .frame(minWidth: 52, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        .padding(.horizontal)
    }
}

// MARK: - Badge View
struct BadgeView: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Status Badge View
struct StatusBadgeView: View {
    let status: SubmissionStatus

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: status.icon)
                .font(.subheadline)
                .foregroundColor(.primary)
            Text(status.displayText)
                .font(.caption2.weight(.medium))
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Loading View
struct LoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading your activity...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Error Banner
struct ErrorBannerView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Button("Retry", action: onRetry)
                .font(.subheadline.weight(.semibold))
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

// MARK: - Empty Activity View
struct EmptyActivityView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("No activity yet")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Complete your first essay to see your progress here.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}

// MARK: - Grammar Placeholder
struct GrammarView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Grammar Guide").font(.largeTitle.bold())
                Text("Coming soon...").foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Grammar")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Tips Placeholder
struct TipsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Writing Tips").font(.largeTitle.bold())
                Text("Coming soon...").foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Tips")
        .navigationBarTitleDisplayMode(.inline)
    }
}
