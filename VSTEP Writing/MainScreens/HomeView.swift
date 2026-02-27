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
                        onScoreViewTap: { navigateToScore = true },
                        onLearnViewTap: { navigateToPractice = true }
                    )

                    BlogSection()
                }

                Spacer(minLength: 50)
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Home")
        .toolbarTitleDisplayMode(.large)
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
            Text("Ready to practice today?")
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
            // ← REPLACED LinearGradient + clipShape + shadow with glassEffect
            .glassEffect(
                .regular.tint(.blue).interactive(),
                in: .rect(cornerRadius: 18)
            )
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
    let onLearnViewTap: () -> Void

    private var groupedSubmissions:
        [(
            questionId: String, question: VSTEPQuestion?,
            entries: [UserSubmission]
        )]
    {
        var order: [String] = []
        var dict: [String: [UserSubmission]] = [:]
        for s in submissions {
            if dict[s.questionId] == nil { order.append(s.questionId) }
            dict[s.questionId, default: []].append(s)
        }
        return order.prefix(2).map { id in
            (questionId: id, question: questionMap[id], entries: dict[id] ?? [])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.headline)
                .padding(.horizontal)

            if groupedSubmissions.isEmpty {
                EmptyActivityView()
            } else {
                VStack(spacing: 12) {
                    ForEach(groupedSubmissions, id: \.questionId) { group in
                        ActivityStackCard(
                            question: group.question,
                            entries: group.entries,
                            onTap: {
                                if group.entries.first?.score != nil {
                                    onScoreViewTap()
                                } else {
                                    onLearnViewTap()
                                }
                            }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Activity Stack Card
struct ActivityStackCard: View {
    let question: VSTEPQuestion?
    let entries: [UserSubmission]
    let onTap: () -> Void

    @State private var isExpanded = false

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

    private var visibleEntries: [UserSubmission] {
        isExpanded ? Array(entries.prefix(3)) : Array(entries.prefix(1))
    }

    private var hasMore: Bool { entries.count > 3 }

    var body: some View {
        VStack(spacing: 0) {
            // Entry rows
            ForEach(Array(visibleEntries.enumerated()), id: \.element.id) {
                index,
                sub in
                Button(action: onTap) {
                    entryRow(sub: sub, isLatest: index == 0)
                }
                .buttonStyle(.plain)

                if index < visibleEntries.count - 1 {
                    Divider().padding(.leading, 56)
                }
            }

            // Expand / Collapse / Show All controls
            if entries.count > 1 {
                Divider().padding(.leading, 56)

                HStack(spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(
                                systemName: isExpanded
                                    ? "chevron.up" : "chevron.down"
                            )
                            .font(.caption2.bold())
                            Text(
                                isExpanded
                                    ? "Collapse"
                                    : "\(min(entries.count - 1, 2)) more attempt\(entries.count > 2 ? "s" : "")"
                            )
                            .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    Spacer()

                    if isExpanded && hasMore {
                        Button {
                            onTap()
                        } label: {
                            Text("Show all \(entries.count)")
                                .font(.caption.bold())
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }

                    if let best = entries.compactMap(\.score).max() {
                        HStack(spacing: 3) {
                            Image(systemName: "trophy.fill")
                                .font(.caption2)
                                .foregroundColor(.yellow)
                            Text(String(format: "%.1f", best))
                                .font(.caption.bold())
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
            }
        }
        // ← REPLACED .background + .clipShape + .shadow with .glassEffect
        .glassEffect(in: .rect(cornerRadius: 16))
        .padding(.horizontal)
    }

    @ViewBuilder
    private func entryRow(sub: UserSubmission, isLatest: Bool) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 3)
                .fill(isLatest ? taskBadgeColor : taskBadgeColor.opacity(0.4))
                .frame(width: 4, height: 52)

            VStack(alignment: .leading, spacing: 5) {
                if isLatest {
                    Text(question?.title ?? sub.questionId.uppercased())
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    if isLatest {
                        BadgeView(text: taskBadgeText, color: taskBadgeColor)
                        if let diff = question?.difficulty {
                            BadgeView(
                                text: diff.capitalized,
                                color: difficultyColor
                            )
                        }
                    } else {
                        Text("Earlier attempt")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    // CHANGED: replaced style: .relative with formatted absolute datetime
                    Text(
                        sub.submittedAt,
                        format: .dateTime.day().month(.abbreviated).hour()
                            .minute()
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 8)

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
                Button("View All") { /* Navigate to full blog list */  }
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
        // ← REPLACED .background + .clipShape + .shadow with .glassEffect
        .glassEffect(in: .rect(cornerRadius: 16))
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
                .foregroundColor(.blue)
            Text(status.displayText)
                .font(.caption2.weight(.medium))
                .foregroundColor(.blue)
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
        // ← REPLACED .background + .clipShape with .glassEffect
        .glassEffect(in: .rect(cornerRadius: 12))
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
        // ← REPLACED .background + .clipShape with .glassEffect
        .glassEffect(in: .rect(cornerRadius: 16))
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
        .toolbarTitleDisplayMode(.inline)
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
        .toolbarTitleDisplayMode(.inline)
    }
}
