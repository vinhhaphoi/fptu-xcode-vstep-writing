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

    /// Lấy trực tiếp từ FirebaseAuth — không phụ thuộc AuthenticationManager
    private var displayName: String {
        let user = Auth.auth().currentUser
        return user?.displayName
            ?? user?.email?.components(separatedBy: "@").first
            ?? "Learner"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                QuickActionsSection()

                if isLoading {
                    LoadingView()
                } else if let error = errorMessage {
                    ErrorBannerView(message: error) {
                        Task { await loadData() }
                    }
                } else {
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

// MARK: - Welcome Banner
struct WelcomeBanner: View {
    let displayName: String
    let questionsAvailable: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome back, \(displayName)!")
                .font(.title.bold())
                .foregroundColor(.primary)

            Text(
                questionsAvailable > 0
                    ? "\(questionsAvailable) questions available"
                    : "Continue your writing practice"
            )
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            LinearGradient(
                colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
        .padding(.horizontal)
    }
}

// MARK: - Loading View
struct LoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading your activity…")
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
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

// MARK: - Quick Actions Section
struct QuickActionsSection: View {
    @State private var selectedAction: QuickActionType?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Actions")
                .font(.title2.bold())
                .padding(.horizontal)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 16
            ) {
                ForEach(quickActionsList) { action in
                    Button { selectedAction = action.type } label: {
                        QuickActionCard(action: action)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .navigationDestination(item: $selectedAction) { actionType in
            switch actionType {
            case .practice: LearnView()
            case .myScores: ScoreView()
            case .grammar:  GrammarView()
            case .tips:     TipsView()
            }
        }
    }

    private var quickActionsList: [QuickActionInfo] {
        [
            QuickActionInfo(icon: "pencil.circle.fill",  iconColor: .blue,   title: "New Essay",  type: .practice),
            QuickActionInfo(icon: "book.fill",           iconColor: .green,  title: "Grammar",    type: .grammar),
            QuickActionInfo(icon: "list.clipboard.fill", iconColor: .orange, title: "Practice",   type: .practice),
            QuickActionInfo(icon: "chart.bar.fill",      iconColor: .purple, title: "Progress",   type: .myScores),
        ]
    }
}

// MARK: - Quick Action Card
struct QuickActionCard: View {
    let action: QuickActionInfo

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: action.icon)
                .font(.title)
                .foregroundColor(action.iconColor)
            Text(action.title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Quick Action Models
struct QuickActionInfo: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let title: String
    let type: QuickActionType
}

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

    /// Deduplicate: giữ submission MỚI NHẤT mỗi questionId
    /// submissions đã sort descending từ Firestore → filter lấy cái đầu tiên gặp
    private var uniqueSubmissions: [UserSubmission] {
        var seen = Set<String>()
        return submissions.filter { seen.insert($0.questionId).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent Activity")
                    .font(.title2.bold())
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
            // Color bar — phân biệt Task 1 / Task 2
            RoundedRectangle(cornerRadius: 3)
                .fill(taskBadgeColor)
                .frame(width: 4, height: 64)

            // Info
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

            // Score or Status
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
        .cornerRadius(14)
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
            .cornerRadius(6)
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

// MARK: - Empty Activity View
struct EmptyActivityView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("No recent activity")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Complete your first essay to see progress here.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Grammar & Tips Placeholders
struct GrammarView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("📚 Grammar Guide").font(.largeTitle.bold())
                Text("Coming soon…").foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Grammar")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TipsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("💡 Writing Tips").font(.largeTitle.bold())
                Text("Coming soon…").foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Tips")
        .navigationBarTitleDisplayMode(.inline)
    }
}
