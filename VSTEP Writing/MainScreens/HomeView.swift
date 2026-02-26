import FirebaseAuth
import SwiftUI

// MARK: - HomeView
struct HomeView: View {
    @StateObject private var firebaseService = FirebaseService.shared
    @EnvironmentObject var authManager: AuthenticationManager

    @State private var recentSubmissions: [UserSubmission] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    // Navigation destinations
    @State private var navigateToGrammar = false
    @State private var navigateToScore = false
    @State private var navigateToTips = false
    @State private var navigateToPractice = false

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
                // Greeting + Start Writing sát nhau
                HomeGreetingSection(displayName: displayName)
                PrimaryActionCard { navigateToPractice = true }

                if isLoading {
                    LoadingView()
                } else if let error = errorMessage {
                    ErrorBannerView(message: error) {
                        Task { await loadData() }
                    }
                } else {
                    RecentActivitySection(
                        submissions: recentSubmissions,
                        questionMap: firebaseService.questionMap,
                        onScoreViewTap: { navigateToScore = true }
                    )

                    BlogSection()
                }

                Spacer(minLength: 50)
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { ToolBarItems }
        .refreshable { await loadData() }
        .task { await loadData() }
        .navigationDestination(isPresented: $navigateToPractice) { LearnView() }
        .navigationDestination(isPresented: $navigateToGrammar) {
            GrammarView()
        }
        .navigationDestination(isPresented: $navigateToScore) { ScoreView() }
        .navigationDestination(isPresented: $navigateToTips) { TipsView() }
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

    // MARK: - Toolbar
    @ToolbarContentBuilder
    private var ToolBarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                navigateToGrammar = true
            } label: {
                Image(systemName: "text.book.closed")
            }
            .tint(.green)
        }

        ToolbarSpacer(.fixed, placement: .topBarTrailing)

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                navigateToScore = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "star")
                    if let avg = averageScore {
                        Text(String(format: "%.1f", avg))
                            .font(.caption.bold())
                    }
                }
            }
            .tint(.orange)
        }

        ToolbarSpacer(.fixed, placement: .topBarTrailing)

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                navigateToTips = true
            } label: {
                Image(systemName: "lightbulb")
            }
            .tint(.yellow)
        }
    }
}

// MARK: - Greeting Header
struct HomeGreetingSection: View {
    let displayName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hello, \(displayName)!")
                .font(.title2.bold())
                .foregroundStyle(.primary)
            Text("Ready to practise today?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
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
                    Text("Practise VSTEP writing essays")
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
                    colors: [
                        .blue,
                        Color(hue: 0.65, saturation: 0.8, brightness: 0.85),
                    ],
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

// MARK: - Recent Activity Section
struct RecentActivitySection: View {
    let submissions: [UserSubmission]
    let questionMap: [String: VSTEPQuestion]
    let onScoreViewTap: () -> Void

    /// Group submissions by questionId, sorted: newest group first, max 2 groups shown
    private var groupedSubmissions:
        [(question: VSTEPQuestion?, entries: [UserSubmission])]
    {
        // Group by questionId, preserving order of first appearance (submissions already desc)
        var order: [String] = []
        var dict: [String: [UserSubmission]] = [:]
        for s in submissions {
            if dict[s.questionId] == nil { order.append(s.questionId) }
            dict[s.questionId, default: []].append(s)
        }
        return order.prefix(2).map { id in
            (question: questionMap[id], entries: dict[id] ?? [])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent Activity")
                    .font(.headline)
                Spacer()
                if !submissions.isEmpty {
                    Button("See All", action: onScoreViewTap)
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal)

            if groupedSubmissions.isEmpty {
                EmptyActivityView()
            } else {
                VStack(spacing: 10) {
                    ForEach(groupedSubmissions, id: \.entries.first?.id) {
                        group in
                        ActivityGroupRow(
                            question: group.question,
                            entries: group.entries
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Activity Group Row (stacked submissions for same question)
struct ActivityGroupRow: View {
    let question: VSTEPQuestion?
    let entries: [UserSubmission]

    private var latest: UserSubmission? { entries.first }

    private var taskBadgeText: String {
        switch question?.taskType {
        case "task1": return "Task 1"
        case "task2": return "Task 2"
        default: return "Essay"
        }
    }

    private var taskBadgeColor: Color {
        question?.taskType == "task1" ? .blue : .purple
    }

    private var difficultyColor: Color {
        switch question?.difficulty.lowercased() {
        case "easy": return .green
        case "medium": return .orange
        case "hard": return .red
        default: return .secondary
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Latest submission row
            if let sub = latest {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(taskBadgeColor)
                        .frame(width: 4, height: 56)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(question?.title ?? sub.questionId.uppercased())
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            BadgeView(
                                text: taskBadgeText,
                                color: taskBadgeColor
                            )
                            if let diff = question?.difficulty {
                                BadgeView(
                                    text: diff.capitalized,
                                    color: difficultyColor
                                )
                            }
//                            Image(systemName: "clock")
//                                .font(.caption2)
//                                .foregroundColor(.secondary)
//                            Text(sub.submittedAt, style: .relative)
//                                .font(.caption)
//                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer(minLength: 8)

                    // Score hoặc status
                    if let score = sub.score {
                        VStack(spacing: 1) {
                            Text(String(format: "%.1f", score))
                                .font(.title3.bold().monospacedDigit())
                                .foregroundColor(scoreColor(score))
                            Text("/ 10")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(minWidth: 48, alignment: .trailing)
                    } else {
                        StatusBadgeView(status: sub.status)
                            .frame(minWidth: 48, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            // Nếu có nhiều hơn 1 lần submit, hiển thị dòng count nhỏ
            if entries.count > 1 {
                Divider().padding(.leading, 34)
                HStack {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(
                        "\(entries.count - 1) earlier attempt\(entries.count > 2 ? "s" : "")"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    Spacer()
                    // Hiển thị score cao nhất nếu có
                    if let best = entries.compactMap(\.score).max() {
                        Text("Best: \(String(format: "%.1f", best))")
                            .font(.caption.bold())
                            .foregroundColor(.green)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        .padding(.horizontal)
    }

    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 8...: return .green
        case 6..<8: return .orange
        default: return .red
        }
    }
}

// MARK: - Blog Section
struct BlogPost: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let category: String
    let categoryColor: Color
    let systemImage: String
    let imageColor: Color
}

struct BlogSection: View {
    // Placeholder data — thay bằng Firebase fetch thực tế sau
    private let blogs: [BlogPost] = [
        BlogPost(
            id: "1",
            title: "How to Score 8.0 in Task 2",
            subtitle: "Master argument structure and cohesion",
            category: "Strategy",
            categoryColor: .blue,
            systemImage: "doc.text.magnifyingglass",
            imageColor: .blue
        ),
        BlogPost(
            id: "2",
            title: "Common Grammar Mistakes",
            subtitle: "Top 10 errors VSTEP candidates make",
            category: "Grammar",
            categoryColor: .green,
            systemImage: "checkmark.seal",
            imageColor: .green
        ),
        BlogPost(
            id: "3",
            title: "Task 1 Vocabulary Boost",
            subtitle: "Essential phrases for letter writing",
            category: "Vocabulary",
            categoryColor: .purple,
            systemImage: "text.quote",
            imageColor: .purple
        ),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Blog")
                    .font(.headline)
                Spacer()
                Button("View All") {
                    // Navigate to full blog list
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(blogs) { post in
                        BlogCard(post: post)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
        }
    }
}

struct BlogCard: View {
    let post: BlogPost

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Icon area
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(post.imageColor.opacity(0.12))
                    .frame(height: 80)
                Image(systemName: post.systemImage)
                    .font(.system(size: 32))
                    .foregroundStyle(post.imageColor)
            }

            BadgeView(text: post.category, color: post.categoryColor)

            Text(post.title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(post.subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(14)
        .frame(width: 180)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 5, x: 0, y: 2)
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

// MARK: - Quick Action Type
enum QuickActionType: String, Identifiable {
    case practice = "Practice"
    case myScores = "My Scores"
    case grammar = "Grammar"
    case tips = "Tips"

    var id: String { rawValue }
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
