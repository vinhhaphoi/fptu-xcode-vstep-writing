import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import SwiftUI

// MARK: - AnalyticsManager

@MainActor
final class AnalyticsManager: ObservableObject {

    @Published var insights: UserProgressInsights? = nil
    @Published var isFetching = false
    @Published var errorMessage: String? = nil
    @Published var isCached: Bool = false
    @Published var cachedAt: String? = nil
    @Published var autoRefresh: Bool = false {
        didSet {
            guard oldValue != autoRefresh else { return }
            saveAutoRefreshPreference()
        }
    }

    /// Prevents concurrent calls to the cloud function
    private var activeFetchTask: Task<Void, Never>? = nil

    private lazy var functions = Functions.functions(region: "asia-southeast1")
    private let firestore = Firestore.firestore()

    init() {
        Task {
            await loadAutoRefreshPreference()
            await loadCachedInsights()
        }
    }

    // MARK: - Load Insights (delegates quota check to AIUsageManager)

    func loadInsights(forceRefresh: Bool = false, store: StoreKitManager) {
        // Prevent concurrent calls — cancel-safe
        guard !isFetching, activeFetchTask == nil else { return }

        // Client-side quota guard before network call
        if forceRefresh {
            let check = AIUsageManager.shared.canRefreshInsights(store: store)
            guard check.isAllowed else {
                errorMessage = "quota_exceeded"
                return
            }
        }

        isFetching = true
        errorMessage = nil

        activeFetchTask = Task {
            defer {
                self.isFetching = false
                self.activeFetchTask = nil
            }
            do {
                let data: [String: Any] = ["forceRefresh": forceRefresh]
                let result =
                    try await functions
                    .httpsCallable("analyzeUserProgress")
                    .call(data)

                guard let resultDict = result.data as? [String: Any] else {
                    throw NSError(domain: "AnalyticsManager", code: -1)
                }

                let jsonData = try JSONSerialization.data(
                    withJSONObject: resultDict
                )
                let response = try JSONDecoder().decode(
                    AnalyzeProgressResponse.self,
                    from: jsonData
                )

                self.insights = response.insights
                self.isCached = response.cached
                self.cachedAt = response.updatedAt

                // Record usage only when Gemini returned fresh result
                if !response.cached {
                    await AIUsageManager.shared.recordInsightRefresh()
                }

            } catch let error as NSError {
                let code = FunctionsErrorCode(rawValue: error.code)
                switch code {
                case .failedPrecondition:
                    self.errorMessage = "need_more_submissions"
                case .resourceExhausted: self.errorMessage = "quota_exceeded"
                case .permissionDenied: self.errorMessage = "not_subscribed"
                default: self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - AutoRefresh Preference (synced to Firestore)

    private func saveAutoRefreshPreference() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        firestore
            .collection("users").document(uid)
            .collection("analytics").document("insightUsage")
            .setData(["autoRefresh": autoRefresh], merge: true)
    }

    private func loadAutoRefreshPreference() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let snap =
            try? await firestore
            .collection("users").document(uid)
            .collection("analytics").document("insightUsage")
            .getDocument()
        self.autoRefresh = snap?.data()?["autoRefresh"] as? Bool ?? false
    }

    // MARK: - Load Cached Insights from Firestore

    func loadCachedInsights() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let snap =
            try? await firestore
            .collection("users").document(uid)
            .collection("analytics").document("insightUsage")
            .getDocument()

        guard let data = snap?.data(),
            let insightsMap = data["insights"] as? [String: Any]
        else { return }

        do {
            let jsonData = try JSONSerialization.data(
                withJSONObject: insightsMap
            )
            let decoded = try JSONDecoder().decode(
                UserProgressInsights.self,
                from: jsonData
            )
            self.insights = decoded
            self.isCached = data["cached"] as? Bool ?? true

            // Read updatedAt from insightUsage document
            if let ts = data["updatedAt"] as? Timestamp {
                let formatter = ISO8601DateFormatter()
                self.cachedAt = formatter.string(from: ts.dateValue())
            } else if let tsStr = data["updatedAt"] as? String {
                self.cachedAt = tsStr
            }
        } catch {
            // Cache decode failed — not critical, user can refresh manually
        }
    }
}

// MARK: - QuestionAttemptGroup

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

    func hash(into hasher: inout Hasher) { hasher.combine(questionId) }

    var latestAttempt: UserSubmission { attempts[0] }
    var previousAttempts: [UserSubmission] { Array(attempts.dropFirst()) }
    var attemptCount: Int { attempts.count }
    var bestScore: Double? { attempts.compactMap(\.score).max() }
}

// MARK: - Chart Data Point

struct ChartDataPoint: Identifiable {
    var id: String { submission.id ?? UUID().uuidString }
    let submission: UserSubmission
    let taskType: String?

    var score: Double { submission.score ?? 0 }
    var date: Date { submission.submittedAt }

    var dotColor: Color {
        switch taskType {
        case "task1": return BrandColor.light
        case "task2": return BrandColor.medium
        default: return BrandColor.primary
        }
    }
}

// MARK: - ScoreView

struct ScoreView: View {

    @StateObject private var firebaseService = FirebaseService.shared
    @StateObject private var analyticsManager = AnalyticsManager()
    @Environment(StoreKitManager.self) private var store

    @State private var submissions: [UserSubmission] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var selectedGroup: QuestionAttemptGroup? = nil

    private var isSubscriber: Bool {
        store.isPurchased("com.vstep.advanced")
            || store.isPurchased("com.vstep.premier")
    }

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
            .sorted { $0.submittedAt < $1.submittedAt }
    }

    /// Chart data points with task type info
    private var chartDataPoints: [ChartDataPoint] {
        gradedSubmissions.map { sub in
            ChartDataPoint(
                submission: sub,
                taskType: firebaseService.questionMap[sub.questionId]?.taskType
            )
        }
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

    private var criteriaAverages: [(name: String, avg: Double)] {
        var map: [String: [Double]] = [:]
        for sub in gradedSubmissions {
            for c in sub.criteria ?? [] {
                if let score = c.score {
                    map[c.name, default: []].append(score)
                }
            }
        }
        return
            map
            .map {
                (
                    name: $0.key,
                    avg: $0.value.reduce(0, +) / Double($0.value.count)
                )
            }
            .sorted { $0.avg < $1.avg }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                // [1] Score header — always visible
                ScoreHeaderView(
                    averageScore: averageScore,
                    totalSubmissions: submissions.count,
                    task1Count: task1Count,
                    task2Count: task2Count
                )

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

                    // [2] All submissions list — moved up
                    AllSubmissionsSection(
                        groups: groupedByQuestion,
                        onNavigate: { selectedGroup = $0 }
                    )

                    // [3] Score trend chart — between submissions and insights
                    if chartDataPoints.count >= 2 {
                        ScoreTrendSection(dataPoints: chartDataPoints)
                    }

                    // [4] Criteria breakdown
                    if !criteriaAverages.isEmpty {
                        CriteriaBreakdownSection(
                            criteriaAverages: criteriaAverages
                        )
                    }

                    // [5] AI Insights — last
                    AIInsightsSection(
                        manager: analyticsManager,
                        isSubscriber: isSubscriber,
                        gradedCount: gradedSubmissions.count,
                        store: store
                    )
                }

                Spacer(minLength: 50)
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Score")
        .toolbarTitleDisplayMode(.large)
        .refreshable { await loadSubmissions() }
        .navigationDestination(item: $selectedGroup) { group in
            if let question = group.question {
                QuestionDetailView(
                    question: question,
                    questionNumber: Int(question.questionId.filter(\.isNumber))
                        ?? 0,
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
        }
    }
}

// MARK: - Score Trend Section (Enhanced)

private struct ScoreTrendSection: View {

    let dataPoints: [ChartDataPoint]
    @State private var selectedIndex: Int? = nil

    private let yMarks: [Double] = [0, 2, 4, 6, 8, 10]
    private let chartHeight: CGFloat = 180
    private let leftPad: CGFloat = 28
    private let rightPad: CGFloat = 12
    private let topPad: CGFloat = 24
    private let bottomPad: CGFloat = 12
    private var hasTask1: Bool {
        dataPoints.contains { $0.taskType == "task1" }
    }
    private var hasTask2: Bool {
        dataPoints.contains { $0.taskType == "task2" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Score Trend",
                icon: "chart.line.uptrend.xyaxis"
            )

            // Chart
            ZStack(alignment: .topLeading) {
                // Y-axis labels
                GeometryReader { geo in
                    let drawH = geo.size.height - topPad - bottomPad
                    ForEach(yMarks, id: \.self) { mark in
                        let yPos = topPad + drawH * (1 - mark / 10)
                        Text("\(Int(mark))")
                            .font(
                                .system(size: 10, weight: .medium)
                                    .monospacedDigit()
                            )
                            .foregroundStyle(.tertiary)
                            .position(x: 10, y: yPos)
                    }
                }

                // Canvas: grid + line + area + dots
                Canvas { context, size in
                    let scores = dataPoints.map(\.score)
                    guard scores.count >= 2 else { return }

                    let w = size.width
                    let h = size.height
                    let drawW = w - leftPad - rightPad
                    let drawH = h - topPad - bottomPad
                    let xStep = drawW / CGFloat(scores.count - 1)

                    func point(index: Int, score: Double) -> CGPoint {
                        CGPoint(
                            x: leftPad + CGFloat(index) * xStep,
                            y: topPad + drawH * (1 - CGFloat(score / 10))
                        )
                    }

                    // Horizontal grid lines
                    for mark in yMarks {
                        let y = topPad + drawH * (1 - CGFloat(mark / 10))
                        var gridLine = Path()
                        gridLine.move(to: CGPoint(x: leftPad, y: y))
                        gridLine.addLine(to: CGPoint(x: w - rightPad, y: y))
                        context.stroke(
                            gridLine,
                            with: .color(Color.secondary.opacity(0.12)),
                            style: StrokeStyle(lineWidth: 0.5, dash: [4, 3])
                        )
                    }

                    // Filled area under line
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

                    // Line
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

                    // Dots — colored by task type
                    for (i, dp) in dataPoints.enumerated() {
                        let p = point(index: i, score: dp.score)
                        let isSelected = selectedIndex == i
                        let dotSize: CGFloat = isSelected ? 10 : 7
                        let glowSize: CGFloat = isSelected ? 16 : 12

                        // Outer glow
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
                                dp.dotColor.opacity(isSelected ? 0.35 : 0.2)
                            )
                        )

                        // Inner dot
                        context.fill(
                            Path(
                                ellipseIn: CGRect(
                                    x: p.x - dotSize / 2,
                                    y: p.y - dotSize / 2,
                                    width: dotSize,
                                    height: dotSize
                                )
                            ),
                            with: .color(dp.dotColor)
                        )
                    }

                    // Selected score label
                    if let idx = selectedIndex, idx < dataPoints.count {
                        let dp = dataPoints[idx]
                        let p = point(index: idx, score: dp.score)
                        let text = Text(String(format: "%.1f", dp.score))
                            .font(
                                .system(size: 12, weight: .bold)
                                    .monospacedDigit()
                            )
                            .foregroundColor(.white)
                        let resolved = context.resolve(text)
                        let textSize = resolved.measure(
                            in: CGSize(width: 60, height: 30)
                        )

                        let labelW = textSize.width + 12
                        let labelH = textSize.height + 8
                        let labelY = p.y - labelH - 10

                        // Bubble background
                        let bubbleRect = CGRect(
                            x: p.x - labelW / 2,
                            y: labelY,
                            width: labelW,
                            height: labelH
                        )
                        context.fill(
                            Path(roundedRect: bubbleRect, cornerRadius: 6),
                            with: .color(dp.dotColor)
                        )

                        // Arrow
                        var arrow = Path()
                        arrow.move(to: CGPoint(x: p.x - 4, y: labelY + labelH))
                        arrow.addLine(
                            to: CGPoint(x: p.x, y: labelY + labelH + 5)
                        )
                        arrow.addLine(
                            to: CGPoint(x: p.x + 4, y: labelY + labelH)
                        )
                        arrow.closeSubpath()
                        context.fill(arrow, with: .color(dp.dotColor))

                        // Text
                        context.draw(
                            resolved,
                            at: CGPoint(x: p.x, y: labelY + labelH / 2),
                            anchor: .center
                        )
                    }
                }
                .frame(height: chartHeight)

                // Tap gesture overlay
                GeometryReader { geo in
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            let count = dataPoints.count
                            guard count >= 2 else { return }
                            let drawW = geo.size.width - leftPad - rightPad
                            let xStep = drawW / CGFloat(count - 1)
                            let relX = location.x - leftPad
                            let idx = Int(round(relX / xStep))
                            let clampedIdx = max(0, min(count - 1, idx))
                            withAnimation(.easeOut(duration: 0.15)) {
                                if selectedIndex == clampedIdx {
                                    selectedIndex = nil
                                } else {
                                    selectedIndex = clampedIdx
                                }
                            }
                        }
                }
            }

            // X-axis labels
            HStack {
                if let first = dataPoints.first {
                    Text(
                        first.date,
                        format: .dateTime.day().month(.abbreviated)
                    )
                    .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if dataPoints.count > 2,
                    let mid = dataPoints[safe: dataPoints.count / 2]
                {
                    Text(
                        mid.date,
                        format: .dateTime.day().month(.abbreviated)
                    )
                    .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if let last = dataPoints.last {
                    Text(
                        last.date,
                        format: .dateTime.day().month(.abbreviated)
                    )
                    .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)

            // Legend
            if hasTask1 || hasTask2 {
                HStack(spacing: 16) {
                    Spacer()
                    if hasTask1 {
                        legendItem(color: BrandColor.light, label: "Task 1")
                    }
                    if hasTask2 {
                        legendItem(color: BrandColor.medium, label: "Task 2")
                    }
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: 16.0))
        .padding(.horizontal)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Criteria Breakdown Section

private struct CriteriaBreakdownSection: View {

    let criteriaAverages: [(name: String, avg: Double)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Criteria Breakdown",
                icon: "list.bullet.clipboard"
            )

            ForEach(criteriaAverages, id: \.name) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(item.name)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(String(format: "%.1f", item.avg))
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(criteriaColor(item.avg))
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(.systemFill))
                                .frame(height: 6)
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            BrandColor.primary,
                                            criteriaColor(item.avg),
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(
                                    width: geo.size.width * item.avg / 10,
                                    height: 6
                                )
                                .animation(
                                    .easeOut(duration: 0.6),
                                    value: item.avg
                                )
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: 16.0))
        .padding(.horizontal)
    }

    private func criteriaColor(_ score: Double) -> Color {
        switch score {
        case 8...: return .green
        case 6..<8: return BrandColor.soft
        default: return .orange
        }
    }
}

// MARK: - AI Insights Section

private struct AIInsightsSection: View {

    @ObservedObject var manager: AnalyticsManager
    let isSubscriber: Bool
    let gradedCount: Int
    let store: StoreKitManager

    private var remaining: Int {
        AIUsageManager.shared.remainingInsightRefreshes(store: store)
    }

    private var weeklyLimit: Int {
        AIUsageManager.shared.limits(for: store).insightRefreshesPerWeek
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isSubscriber {
                insightsLockedCard
            } else if gradedCount < 2 {
                insightsNotEnoughCard
            } else if manager.isFetching {
                insightsSkeleton
            } else if manager.errorMessage == "need_more_submissions" {
                insightsNotEnoughCard
            } else if manager.errorMessage == "quota_exceeded" {
                quotaExhaustedCard
            } else if let error = manager.errorMessage {
                insightsErrorCard(message: error)
            } else if let insights = manager.insights {
                insightsCard(insights: insights)
            } else {
                // No auto-trigger — show a manual load button instead
                insightsReadyCard
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Ready Card (manual trigger)

    private var insightsReadyCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(BrandColor.muted).frame(width: 48, height: 48)
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundStyle(BrandColor.primary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Progress Insights")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(BrandColor.primary)
                    Text("Tap below to analyze your writing progress with AI.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            Button {
                manager.loadInsights(store: store)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.subheadline)
                    Text("Analyze My Progress")
                        .font(.subheadline.bold())
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(BrandColor.primary)
                .clipShape(.rect(cornerRadius: 10))
            }

            // Quota info
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise.circle")
                    .font(.caption)
                Text(
                    "\(remaining)/\(weeklyLimit) refreshes available this week"
                )
                .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: 16.0))
    }

    // MARK: - Locked Card

    private var insightsLockedCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(BrandColor.muted).frame(width: 44, height: 44)
                Image(systemName: "lock.fill").foregroundStyle(
                    BrandColor.primary
                )
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("AI Progress Insights")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(BrandColor.primary)
                    Text("Advanced+")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(BrandColor.soft))
                }
                Text(
                    "Upgrade to get AI-powered analysis of your writing progress."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer()
            NavigationLink {
                SubscriptionsView()
            } label: {
                Text("Upgrade")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(BrandColor.primary))
            }
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: 16.0))
    }

    // MARK: - Not Enough Submissions

    private var insightsNotEnoughCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(BrandColor.muted).frame(width: 44, height: 44)
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(BrandColor.medium)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Progress Insights")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(BrandColor.primary)
                Text(
                    "Submit and get at least 2 graded essays to unlock AI coaching."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: 16.0))
    }

    // MARK: - Quota Exhausted

    private var quotaExhaustedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(BrandColor.muted).frame(width: 44, height: 44)
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(BrandColor.soft)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Weekly Limit Reached")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(BrandColor.primary)
                    Text(
                        "\(weeklyLimit)/\(weeklyLimit) refreshes used this week"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Text("0 left")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .glassEffect(in: .capsule)
            }

            Text(
                "Your AI insight refreshes reset every Monday. You can still view your last analysis below."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            // Show stale insights if still in memory
            if let insights = manager.insights {
                Divider()
                staleInsightsBanner
                insightsContent(insights: insights)
            }

            Divider()
            autoRefreshToggle
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: 16.0))
    }

    private var staleInsightsBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.subheadline)
                .foregroundStyle(.orange)
            Text("Showing previous analysis")
                .font(.subheadline)
                .foregroundStyle(.orange)
            Spacer()
            if let ts = manager.cachedAt {
                Text(formattedDate(ts))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Skeleton

    private var insightsSkeleton: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(BrandColor.light)
                Text("Analyzing your progress…")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(BrandColor.primary)
                Spacer()
                ProgressView().scaleEffect(0.7)
            }
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 12)
            }
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: 16.0))
    }

    // MARK: - Error Card

    private func insightsErrorCard(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BrandColor.soft)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Retry") { manager.loadInsights(store: store) }
                .font(.subheadline.bold())
                .foregroundStyle(BrandColor.primary)
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: 16.0))
    }

    // MARK: - Full Insights Card

    private func insightsCard(insights: UserProgressInsights) -> some View {
        VStack(alignment: .leading, spacing: 16) {

            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(BrandColor.light)
                Text("AI Progress Insights")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(BrandColor.primary)
                Spacer()

                // Trend badge
                Label(
                    insights.trendLabel.label,
                    systemImage: insights.trendLabel.icon
                )
                .font(.subheadline.bold())
                .foregroundStyle(insights.trendLabel.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(insights.trendLabel.color.opacity(0.15))
                )

                // Weekly quota badge
                quotaBadge

                // Refresh button — disabled when limit reached
                Button {
                    manager.loadInsights(forceRefresh: true, store: store)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(
                            remaining == 0 ? Color.secondary : BrandColor.medium
                        )
                }
                .disabled(remaining == 0)
            }

            insightsContent(insights: insights)

            Divider()
            autoRefreshToggle

            // Cache timestamp
            if manager.isCached, let ts = manager.cachedAt {
                HStack(spacing: 4) {
                    Image(systemName: "clock").font(.caption2)
                    Text("Last analyzed: \(formattedDate(ts))").font(.caption2)
                }
                .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: 16.0))
    }

    // MARK: - Insights Content (reused in card + stale state)

    private func insightsContent(insights: UserProgressInsights) -> some View {
        VStack(alignment: .leading, spacing: 16) {

            Text(insights.overallInsight)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(
                    .regular.tint(BrandColor.muted),
                    in: .rect(cornerRadius: 10)
                )

            Divider()

            // ── Redesigned Strengths & Weaknesses ──

            // Strengths
            insightCardList(
                title: "Strengths",
                count: insights.strengths.count,
                icon: "checkmark.circle.fill",
                accentColor: .green,
                tintColor: Color.green.opacity(0.06),
                items: insights.strengths
            )

            // Weaknesses
            insightCardList(
                title: "Weaknesses",
                count: insights.weaknesses.count,
                icon: "exclamationmark.triangle.fill",
                accentColor: .orange,
                tintColor: Color.orange.opacity(0.06),
                items: insights.weaknesses
            )

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Label("Targeted Advice", systemImage: "lightbulb.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BrandColor.medium)

                ForEach(insights.recommendations) { rec in
                    HStack(alignment: .top, spacing: 10) {
                        Text(rec.area)
                            .font(.subheadline.bold())
                            .foregroundStyle(BrandColor.primary)
                            .frame(width: 90, alignment: .leading)
                        Text(rec.tip)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Divider()

            HStack(spacing: 10) {
                Image(systemName: "target")
                    .foregroundStyle(BrandColor.primary)
                    .font(.subheadline)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Next Goal")
                        .font(.subheadline.bold())
                        .foregroundStyle(BrandColor.medium)
                    Text(insights.nextGoal)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(
                .regular.tint(BrandColor.muted),
                in: .rect(cornerRadius: 10)
            )
        }
    }

    // MARK: - Insight Card List (Strengths / Weaknesses)

    private func insightCardList(
        title: String,
        count: Int,
        icon: String,
        accentColor: Color,
        tintColor: Color,
        items: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header with count badge
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(accentColor)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accentColor)
                Text("· \(count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accentColor.opacity(0.7))
                Spacer()
            }

            // Card rows
            VStack(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: icon)
                            .font(.system(size: 13))
                            .foregroundStyle(accentColor)
                            .frame(width: 24, height: 24)
                            .background(accentColor.opacity(0.12))
                            .clipShape(Circle())

                        Text(item)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(tintColor)
                    .clipShape(.rect(cornerRadius: 8))
                }
            }
        }
    }

    // MARK: - Quota Badge

    private var quotaBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.clockwise.circle")
                .font(.caption2)
            Text("\(remaining)/\(weeklyLimit)")
                .font(.caption2.monospacedDigit())
        }
        .foregroundStyle(remaining == 0 ? Color.secondary : BrandColor.medium)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .glassEffect(in: .capsule)
    }

    // MARK: - Auto Refresh Toggle

    private var autoRefreshToggle: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Auto-refresh after grading")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text("Uses 1 quota when a new essay is graded")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $manager.autoRefresh)
                .labelsHidden()
                .tint(BrandColor.primary)
        }
        .padding(12)
        .glassEffect(
            .regular.tint(BrandColor.muted),
            in: .rect(cornerRadius: 10)
        )
    }

    // MARK: - Helpers

    private func formattedDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        guard let date = f.date(from: iso) else { return iso }
        let df = DateFormatter()
        df.dateFormat = "dd/MM HH:mm"
        return df.string(from: date)
    }
}

// MARK: - All Submissions Section

private struct AllSubmissionsSection: View {

    let groups: [QuestionAttemptGroup]
    let onNavigate: (QuestionAttemptGroup) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "All Submissions", icon: "doc.text.fill")
                Spacer()
                Text("\(groups.count) questions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            ForEach(groups) { group in
                QuestionAttemptCard(group: group) { onNavigate(group) }
            }
        }
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(BrandColor.primary)
    }
}

// MARK: - Question Attempt Card

struct QuestionAttemptCard: View {

    let group: QuestionAttemptGroup
    let onNavigate: () -> Void
    @State private var isExpanded = false

    private var taskColor: Color {
        group.question?.taskType == "task1"
            ? BrandColor.light : BrandColor.medium
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
                            .foregroundStyle(.secondary)
                        Text(
                            group.latestAttempt.submittedAt,
                            format: .dateTime.day().month(.abbreviated).hour()
                                .minute()
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .center)

            Text(
                submission.submittedAt,
                format: .dateTime.day().month(.abbreviated).year().hour()
                    .minute()
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

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
        case .submitted: return BrandColor.light
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
                    .foregroundStyle(scoreColor)
                Text("/ 10")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 3) {
                Image(systemName: submission.status.icon)
                    .font(compact ? .caption : .subheadline)
                    .foregroundStyle(statusColor)
                Text(submission.status.displayText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(statusColor)
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
            .foregroundStyle(color)
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
                .foregroundStyle(.secondary)

            if let score = averageScore {
                Text(String(format: "%.1f", score))
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(scoreColor)
                    .contentTransition(.numericText())
            } else {
                Text("—")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(.secondary)
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
                        color: BrandColor.light
                    )
                    StatChip(
                        icon: "2.circle.fill",
                        value: "\(task2Count)",
                        label: "Task 2",
                        color: BrandColor.medium
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
    var color: Color = BrandColor.primary

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(color).font(.subheadline)
            Text(value).font(.title3.bold()).foregroundStyle(.primary)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Empty State

struct ScoreEmptyView: View {
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(BrandColor.muted).frame(width: 80, height: 80)
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 36))
                    .foregroundStyle(BrandColor.primary)
            }
            Text("No submissions yet")
                .font(.headline)
                .foregroundStyle(BrandColor.primary)
            Text("Complete your first essay\nto see your score here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Safe subscript helper

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
