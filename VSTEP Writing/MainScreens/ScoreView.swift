import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import SwiftUI

// MARK: - Question Attempt Group Model
struct QuestionAttemptGroup: Identifiable, Hashable {
    var id: String { questionId }
    let questionId: String
    let question: VSTEPQuestion?
    let attempts: [UserSubmission]

    static func == (lhs: QuestionAttemptGroup, rhs: QuestionAttemptGroup)
        -> Bool
    {
        lhs.questionId == rhs.questionId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(questionId)
    }

    var latestAttempt: UserSubmission { attempts[0] }
    var previousAttempts: [UserSubmission] { Array(attempts.dropFirst()) }
    var attemptCount: Int { attempts.count }
    var bestScore: Double? { attempts.compactMap(\.score).max() }
}

// MARK: - Score Tab
enum ScoreTab: String, CaseIterable {
    case submissions = "Submissions"
    case insights = "AI Insights"

    var icon: String {
        switch self {
        case .submissions: return "doc.text.fill"
        case .insights: return "chart.bar.doc.horizontal.fill"
        }
    }
}

// MARK: - ScoreView
struct ScoreView: View {
    @StateObject private var firebaseService = FirebaseService.shared
    @State private var submissions: [UserSubmission] = []
    @Environment(StoreKitManager.self) private var store
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedGroup: QuestionAttemptGroup? = nil
    @State private var selectedTab: ScoreTab = .submissions

    private var groupedByQuestion: [QuestionAttemptGroup] {
        Dictionary(grouping: submissions) { $0.questionId }
            .map { questionId, attempts in
                QuestionAttemptGroup(
                    questionId: questionId,
                    question: firebaseService.questionMap[questionId],
                    attempts: attempts.sorted {
                        $0.submittedAt > $1.submittedAt
                    }
                )
            }
            .sorted {
                $0.latestAttempt.submittedAt > $1.latestAttempt.submittedAt
            }
    }

    private var gradedSubmissions: [UserSubmission] {
        submissions.filter { $0.score != nil }
    }

    private var averageScore: Double? {
        guard !gradedSubmissions.isEmpty else { return nil }
        return gradedSubmissions.reduce(0.0) { $0 + ($1.score ?? 0) }
            / Double(gradedSubmissions.count)
    }

    private var task1Count: Int {
        submissions.filter {
            firebaseService.questionMap[$0.questionId]?.taskType == "task1"
        }.count
    }

    private var task2Count: Int {
        submissions.filter {
            firebaseService.questionMap[$0.questionId]?.taskType == "task2"
        }.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                ScoreHeaderView(
                    averageScore: averageScore,
                    totalSubmissions: submissions.count,
                    task1Count: task1Count,
                    task2Count: task2Count
                )

                // Tab Picker
                Picker("Tab", selection: $selectedTab) {
                    ForEach(ScoreTab.allCases, id: \.self) { tab in
                        Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Content
                switch selectedTab {
                case .submissions:
                    submissionsContent
                case .insights:
                    AnalyticsView()
                        .environment(store)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Score")
        .toolbarTitleDisplayMode(.large)
        .refreshable {
            switch selectedTab {
            case .submissions: await loadSubmissions()
            case .insights: await AnalyticsManager.shared.loadCachedInsights()
            }
        }
        .navigationDestination(item: $selectedGroup) { group in
            if let question = group.question {
                let questionNumber =
                    Int(question.questionId.filter(\.isNumber)) ?? 0
                QuestionDetailView(
                    question: question,
                    questionNumber: questionNumber,
                    latestSubmission: group.latestAttempt,
                    submissionHistory: group.attempts,
                    store: store
                )
            }
        }
        .task {
            if firebaseService.questions.isEmpty {
                try? await firebaseService.fetchQuestions()
            }
            await loadSubmissions()
            AnalyticsManager.shared.loadPreferences()
            await AnalyticsManager.shared.loadCachedInsights()
        }
    }

    // MARK: - Submissions Content

    @ViewBuilder
    private var submissionsContent: some View {
        if isLoading {
            ProgressView("Loading scores…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else if let error = errorMessage {
            ErrorBannerView(message: error) {
                Task { await loadSubmissions() }
            }
        } else if groupedByQuestion.isEmpty {
            ScoreEmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("All Submissions")
                        .font(.title2.bold())
                    Spacer()
                    Text("\(groupedByQuestion.count) questions")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                ForEach(groupedByQuestion) { group in
                    QuestionAttemptCard(group: group) {
                        selectedGroup = group
                    }
                }

                Spacer(minLength: 50)
            }
            .padding(.vertical)
        }
    }

    private func loadSubmissions() async {
        guard firebaseService.currentUserId != nil, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            submissions = try await firebaseService.fetchUserSubmissions()
        } catch {
            errorMessage = "Failed to load scores. Pull down to retry."
            print("[ScoreView] error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Analytics Manager
@MainActor
final class AnalyticsManager: ObservableObject {

    static let shared = AnalyticsManager()

    @Published var insights: UserProgressInsights? = nil
    @Published var isFetching = false
    @Published var errorMessage: String? = nil
    @Published var isCached: Bool = false
    @Published var cachedAt: String? = nil
    @Published var usedCount: Int? = nil
    @Published var weeklyLimit: Int? = nil

    // Bat/tat tu dong refresh sau grading — chi luu preference, khong tu fetch
    @Published var autoRefresh: Bool = false {
        didSet {
            guard oldValue != autoRefresh else { return }
            UserDefaults.standard.set(
                autoRefresh,
                forKey: "analyticsAutoRefresh"
            )
        }
    }

    private lazy var functions = Functions.functions(region: "asia-southeast1")

    private init() {}

    func loadPreferences() {
        autoRefresh = UserDefaults.standard.bool(forKey: "analyticsAutoRefresh")
    }

    // Chi doc Firestore local cache — KHONG goi Cloud Function
    func loadCachedInsights() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let doc = try await Firestore.firestore()
                .collection("users").document(uid)
                .collection("analytics").document("insightUsage")  // Fix: doi tu insightCache -> insightUsage
                .getDocument()

            guard doc.exists, let data = doc.data() else {
                print("[AnalyticsManager] No cached insights found")
                return
            }

            // Firestore luu Timestamp, JSONSerialization khong handle duoc -> convert truoc
            let sanitized = sanitizeFirestoreData(data)
            let jsonData = try JSONSerialization.data(withJSONObject: sanitized)
            let response = try JSONDecoder().decode(
                AnalyzeProgressResponse.self,
                from: jsonData
            )

            self.insights = response.insights
            self.isCached = response.cached
            self.cachedAt = response.updatedAt
            self.usedCount = response.usedCount
            self.weeklyLimit = response.weeklyLimit
        } catch {
            print("[AnalyticsManager] Load cache error: \(error)")
        }
    }

    // Goi Cloud Function — chi khi user bam refresh thu cong hoac autoRefresh = true sau grading
    func fetchInsights(forceRefresh: Bool = false) async {
        guard !isFetching else { return }
        isFetching = true
        errorMessage = nil
        defer { isFetching = false }

        do {
            let result =
                try await functions
                .httpsCallable("analyzeUserProgress")
                .call(["forceRefresh": forceRefresh])

            guard let dict = result.data as? [String: Any] else {
                throw AIChatError.invalidResponseFormat
            }
            let jsonData = try JSONSerialization.data(withJSONObject: dict)
            let response = try JSONDecoder().decode(
                AnalyzeProgressResponse.self,
                from: jsonData
            )

            self.insights = response.insights
            self.isCached = response.cached
            self.cachedAt = response.updatedAt
            self.usedCount = response.usedCount
            self.weeklyLimit = response.weeklyLimit

            await saveCacheToFirestore(dict: dict)
        } catch {
            self.errorMessage = error.localizedDescription
            print(
                "[AnalyticsManager] Fetch error: \(error.localizedDescription)"
            )
        }
    }

    // Goi sau khi grading xong — chi chay neu user bat toggle
    func triggerAutoRefreshIfEnabled() {
        guard autoRefresh else { return }
        Task { await fetchInsights(forceRefresh: true) }
    }

    private func saveCacheToFirestore(dict: [String: Any]) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await Firestore.firestore()
                .collection("users").document(uid)
                .collection("analytics").document("insightUsage")  // Fix: doi tu insightCache -> insightUsage
                .setData(dict, merge: true)  // merge: true de giu weekKey, usedCount tu Cloud Function
        } catch {
            print(
                "[AnalyticsManager] Save cache error: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Xu ly Firestore Timestamp -> String ISO
    private func sanitizeFirestoreData(_ data: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in data {
            switch value {
            case let ts as Timestamp:
                result[key] = ISO8601DateFormatter().string(
                    from: ts.dateValue()
                )
            case let nested as [String: Any]:
                result[key] = sanitizeFirestoreData(nested)
            case let array as [[String: Any]]:
                result[key] = array.map { sanitizeFirestoreData($0) }
            default:
                result[key] = value
            }
        }
        return result
    }
}

// MARK: - Analytics View
struct AnalyticsView: View {

    @StateObject private var manager = AnalyticsManager.shared

    var body: some View {
        VStack(spacing: 20) {

            analyticsHeaderCard
                .padding(.horizontal)

            if manager.isFetching {
                fetchingView
            } else if let insights = manager.insights {
                insightContent(insights: insights)
            } else if let error = manager.errorMessage {
                errorView(message: error)
            } else {
                emptyInsightView
            }

            settingsCard
                .padding(.horizontal)
                .padding(.bottom, 40)
        }
    }

    // MARK: - Header Card

    private var analyticsHeaderCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(BrandColor.muted)
                    .frame(width: 52, height: 52)
                Image(systemName: "chart.bar.doc.horizontal.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(BrandColor.primary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("AI Progress Insights")
                    .font(.headline)
                    .foregroundStyle(BrandColor.primary)

                if manager.isCached, let cachedAt = manager.cachedAt {
                    Text("Updated: \(formattedCachedDate(cachedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Powered by Gemini AI")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let used = manager.usedCount, let limit = manager.weeklyLimit {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(used)/\(limit)")
                        .font(.caption.bold())
                        .foregroundStyle(
                            used >= limit ? .red : BrandColor.primary
                        )
                    Text("this week")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                Task { await manager.fetchInsights(forceRefresh: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BrandColor.primary)
            }
            .disabled(manager.isFetching)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .glassEffect(in: .rect(cornerRadius: 16.0))
    }

    // MARK: - Fetching

    private var fetchingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Analyzing your progress…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Empty State

    private var emptyInsightView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis.ascending.badge.clock")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No insights yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(
                "Submit and get at least 2 essays graded\nto generate your AI progress report."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal)
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Try Again") {
                Task { await manager.fetchInsights(forceRefresh: false) }
            }
            .buttonStyle(.borderedProminent)
            .tint(BrandColor.primary)
        }
        .padding(.vertical, 40)
    }

    // MARK: - Insight Content

    @ViewBuilder
    private func insightContent(insights: UserProgressInsights) -> some View {
        overallCard(insights: insights)
            .padding(.horizontal)

        HStack(alignment: .top, spacing: 12) {
            insightListCard(
                title: "Strengths",
                items: insights.strengths,
                icon: "checkmark.circle.fill",
                color: .green
            )
            insightListCard(
                title: "Weaknesses",
                items: insights.weaknesses,
                icon: "exclamationmark.circle.fill",
                color: .orange
            )
        }
        .padding(.horizontal)

        recommendationsCard(insights: insights)
            .padding(.horizontal)

        nextGoalCard(insights: insights)
            .padding(.horizontal)
    }

    private func overallCard(insights: UserProgressInsights) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Overview")
                    .font(.headline)
                Spacer()
                trendBadge(trend: insights.trendLabel)
            }
            Text(insights.overallInsight)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .glassEffect(in: .rect(cornerRadius: 16.0))
    }

    private func insightListCard(
        title: String,
        items: [String],
        icon: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(color)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(color)
                        .padding(.top, 2)
                    Text(item)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(in: .rect(cornerRadius: 16.0))
    }

    private func recommendationsCard(insights: UserProgressInsights)
        -> some View
    {
        VStack(alignment: .leading, spacing: 12) {
            Text("Targeted Advice")
                .font(.headline)

            ForEach(insights.recommendations) { rec in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption)
                            .foregroundStyle(BrandColor.primary)
                        Text(rec.area)
                            .font(.subheadline.bold())
                    }
                    Text(rec.tip)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                if rec.id != insights.recommendations.last?.id {
                    Divider().padding(.leading, 20)
                }
            }
        }
        .padding(16)
        .glassEffect(in: .rect(cornerRadius: 16.0))
    }

    private func nextGoalCard(insights: UserProgressInsights) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "target")
                .font(.system(size: 28))
                .foregroundStyle(BrandColor.primary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Next Goal")
                    .font(.subheadline.bold())
                Text(insights.nextGoal)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 16.0))
    }

    // MARK: - Settings Card

    private var settingsCard: some View {
        HStack(spacing: 15) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(BrandColor.primary)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("Auto Refresh After Grading")
                    .font(.system(size: 15))
                Text("Automatically fetch new insights when an essay is graded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $manager.autoRefresh)
                .labelsHidden()
                .tint(BrandColor.primary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .glassEffect(in: .rect(cornerRadius: 16.0))
    }

    // MARK: - Helpers

    @ViewBuilder
    private func trendBadge(trend: UserProgressInsights.TrendLabel) -> some View
    {
        Label(trend.label, systemImage: trend.icon)
            .font(.caption.bold())
            .foregroundStyle(trend.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(trend.color.opacity(0.15)))
    }

    private func formattedCachedDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime, .withFractionalSeconds,
        ]
        guard let date = formatter.date(from: iso) else { return iso }
        return date.formatted(
            .dateTime.day().month(.abbreviated).hour().minute()
        )
    }
}

// MARK: - Question Attempt Card
struct QuestionAttemptCard: View {
    let group: QuestionAttemptGroup
    let onNavigate: () -> Void

    @State private var isExpanded = false

    private var taskColor: Color {
        group.question?.taskType == "task1" ? .blue : .purple
    }

    private var taskBadgeText: String {
        switch group.question?.taskType {
        case "task1": return "Task 1"
        case "task2": return "Task 2"
        default: return "Essay"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Color.clear
                    .frame(width: 4, height: 68)
                    .glassEffect(.regular.tint(taskColor), in: Capsule())

                VStack(alignment: .leading, spacing: 6) {
                    Text(group.question?.title ?? group.questionId.uppercased())
                        .font(.headline)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        BadgeLabel(text: taskBadgeText, color: taskColor)

                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(
                            group.latestAttempt.submittedAt,
                            format: .dateTime.day().month(.abbreviated).hour()
                                .minute()
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }

                Spacer()

                AttemptScoreView(submission: group.latestAttempt)

                if !group.previousAttempts.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(
                            systemName: isExpanded
                                ? "chevron.up" : "chevron.down"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                        .padding(.vertical, 12)
                        .padding(.trailing, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .onTapGesture { onNavigate() }

            if isExpanded {
                Divider().padding(.horizontal, 16)

                ForEach(
                    Array(group.previousAttempts.reversed().enumerated()),
                    id: \.element.id
                ) { index, attempt in
                    PreviousAttemptRow(
                        attemptNumber: index + 1,
                        submission: attempt
                    )

                    if index < group.previousAttempts.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }
        }
        .glassEffect(in: .rect(cornerRadius: 16))
        .padding(.horizontal)
    }
}

// MARK: - Previous Attempt Row
struct PreviousAttemptRow: View {
    let attemptNumber: Int
    let submission: UserSubmission

    var body: some View {
        HStack(spacing: 12) {
            Text("#\(attemptNumber)")
                .font(.caption.weight(.bold))
                .foregroundColor(.secondary)
                .frame(width: 32, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                Text(
                    submission.submittedAt,
                    format: .dateTime.day().month(.abbreviated).year().hour()
                        .minute()
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
            }

            Spacer()

            AttemptScoreView(submission: submission, compact: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemGroupedBackground).opacity(0.5))
    }
}

// MARK: - Attempt Score View
struct AttemptScoreView: View {
    let submission: UserSubmission
    var compact: Bool = false

    private var scoreColor: Color {
        guard let score = submission.score else { return .secondary }
        switch score {
        case 8...: return .green
        case 6..<8: return .orange
        default: return .red
        }
    }

    private var statusColor: Color {
        switch submission.status {
        case .submitted: return .blue
        case .grading: return .orange
        case .graded: return .green
        case .failed: return .red
        case .draft: return .secondary
        }
    }

    var body: some View {
        if let score = submission.score {
            VStack(spacing: 1) {
                Text(String(format: "%.1f", score))
                    .font(
                        compact
                            ? .subheadline.bold().monospacedDigit()
                            : .title3.bold().monospacedDigit()
                    )
                    .foregroundColor(scoreColor)
                Text("/ 10")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        } else {
            VStack(spacing: 3) {
                Image(systemName: submission.status.icon)
                    .font(compact ? .caption : .subheadline)
                    .foregroundColor(statusColor)
                Text(submission.status.displayText)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(statusColor)
            }
        }
    }
}

// MARK: - Badge Label
struct BadgeLabel: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(.rect(cornerRadius: 5))
    }
}

// MARK: - Score Header View
struct ScoreHeaderView: View {
    let averageScore: Double?
    let totalSubmissions: Int
    let task1Count: Int
    let task2Count: Int

    private var scoreColor: Color {
        guard let score = averageScore else { return .secondary }
        switch score {
        case 8...: return .green
        case 6..<8: return .orange
        default: return .red
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Overall Score")
                .font(.headline)
                .foregroundColor(.secondary)

            if let score = averageScore {
                Text(String(format: "%.1f", score))
                    .font(.system(size: 60, weight: .bold))
                    .foregroundColor(scoreColor)
                    .contentTransition(.numericText())
            } else {
                Text("—")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundColor(.secondary)
            }

            if totalSubmissions > 0 {
                HStack(spacing: 28) {
                    StatChip(
                        icon: "doc.text.fill",
                        value: "\(totalSubmissions)",
                        label: "Total"
                    )
                    StatChip(
                        icon: "1.circle.fill",
                        value: "\(task1Count)",
                        label: "Task 1",
                        color: .blue
                    )
                    StatChip(
                        icon: "2.circle.fill",
                        value: "\(task2Count)",
                        label: "Task 2",
                        color: .purple
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal)
        .glassEffect(in: .rect(cornerRadius: 16))
        .padding(.horizontal)
    }
}

// MARK: - Stat Chip
struct StatChip: View {
    let icon: String
    let value: String
    let label: String
    var color: Color = .primary

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.subheadline)
            Text(value)
                .font(.title3.bold())
                .foregroundColor(.primary)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Score Empty State
struct ScoreEmptyView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No submissions yet")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Complete your first essay\nto see your score here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}
