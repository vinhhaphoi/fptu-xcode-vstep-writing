import SwiftUI

struct HomeView: View {
    @StateObject private var firebaseService = FirebaseService.shared
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var recentSubmissions: [UserSubmission] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Welcome Banner
                WelcomeBanner()

                // Quick Actions (Refactored)
                QuickActionsSection()

                // Recent Activity
                RecentActivitySection(submissions: recentSubmissions)

                Spacer(minLength: 50)
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await loadData()
        }
        .task {
            await loadData()
        }
    }

    private func loadData() async {
        do {
            try await firebaseService.fetchQuestions()

            if firebaseService.currentUserId != nil {
                try? await firebaseService.fetchUserProgress()
                recentSubmissions =
                    try await firebaseService.fetchUserSubmissions()
            }
        } catch {
            print("Error loading data: \(error)")
        }
    }
}

// MARK: - Welcome Banner
struct WelcomeBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Welcome Back!")
                .font(.title.bold())

            Text("Continue your writing practice")
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

// MARK: - Quick Actions Section (Grid Layout, Clean Structure)
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
                    Button {
                        selectedAction = action.type
                    } label: {
                        QuickActionCard(action: action)
                    }
                }
            }
            .padding(.horizontal)
        }
        .navigationDestination(item: $selectedAction) { actionType in
            switch actionType {
            case .practice:
                LearnView()
            case .myScores:
                ScoreView()
            case .grammar:
                GrammarView()
            case .tips:
                TipsView()
            }
        }
    }

    private var quickActionsList: [QuickActionInfo] {
        return [
            QuickActionInfo(
                icon: "pencil",
                iconColor: .blue,
                title: "New Essay",
                type: .practice
            ),
            QuickActionInfo(
                icon: "book",
                iconColor: .green,
                title: "Grammar",
                type: .grammar
            ),
            QuickActionInfo(
                icon: "list.clipboard",
                iconColor: .orange,
                title: "Practice",
                type: .practice
            ),
            QuickActionInfo(
                icon: "chart.bar",
                iconColor: .purple,
                title: "Progress",
                type: .myScores
            ),
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
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

// MARK: - Supporting Models
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
    case grammar = "Grammar"
    case tips = "Tips"

    var id: String { rawValue }
}

// MARK: - Recent Activity Section
struct RecentActivitySection: View {
    let submissions: [UserSubmission]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Activity")
                .font(.title2.bold())
                .padding(.horizontal)

            if !submissions.isEmpty {
                ForEach(Array(submissions.prefix(5).enumerated()), id: \.offset)
                { index, submission in
                    ActivityRow(
                        index: index,
                        questionId: submission.questionId,
                        submittedAt: submission.submittedAt,
                        score: submission.score
                    )
                }
            } else {
                ForEach(0..<5) { index in
                    ActivityRow(index: index)
                }
            }
        }
    }
}

// MARK: - Activity Row
struct ActivityRow: View {
    let index: Int
    var questionId: String?
    var submittedAt: Date?
    var score: Double?

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "doc.text.fill")
                .foregroundColor(.blue)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                if let questionId = questionId {
                    Text(questionId.uppercased())
                        .font(.headline)
                } else {
                    Text("Essay \(index + 1)")
                        .font(.headline)
                }

                if let submittedAt = submittedAt {
                    Text(submittedAt, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Completed 2 days ago")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if let score = score {
                Text(String(format: "%.0f%%", score * 10))
                    .font(.headline)
                    .foregroundColor(.green)
            } else {
                Text("85%")
                    .font(.headline)
                    .foregroundColor(.green)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

// MARK: - Placeholder Views
struct GrammarView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("📚 Grammar Guide")
                    .font(.largeTitle.bold())
                Text("Coming soon...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
                Text("💡 Writing Tips")
                    .font(.largeTitle.bold())
                Text("Coming soon...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Tips")
        .navigationBarTitleDisplayMode(.inline)
    }
}
