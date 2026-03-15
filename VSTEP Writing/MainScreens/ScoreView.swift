import Charts
import FirebaseAuth
import FirebaseFirestore
import SwiftUI

// MARK: - Score Tab Enum

private enum ScoreTab: String, CaseIterable {
    case submissions
    case analytics
    case insights

    var localizedTitle: String {
        switch self {
        case .submissions: return "Submissions"
        case .analytics: return "Analytics"
        case .insights: return "Insights"
        }
    }

    var icon: String {
        switch self {
        case .submissions: return "doc.text.fill"
        case .analytics: return "chart.line.uptrend.xyaxis"
        case .insights: return "sparkles"
        }
    }
}

// MARK: - ScoreView

struct ScoreView: View {

    @StateObject private var firebaseService = FirebaseService.shared
    @StateObject private var analyticsManager = AnalyticsManager.shared
    @Environment(StoreKitManager.self) private var store

    @State private var selectedGroup: QuestionAttemptGroup? = nil
    @State private var selectedTab: ScoreTab = .submissions

    // Realtime stats from users/{userId} listener
    @State private var serverAverageScore: Double? = nil
    @State private var serverTotalSubmissions: Int = 0
    @State private var serverTask1Count: Int = 0
    @State private var serverTask2Count: Int = 0
    @State private var statsListener: ListenerRegistration? = nil

    private let db = Firestore.firestore()

    private var isSubscriber: Bool {
        store.isPurchased("com.vstep.advanced")
            || store.isPurchased("com.vstep.premier")
    }

    private var groupedByQuestion: [QuestionAttemptGroup] {
        Dictionary(grouping: firebaseService.userSubmissions, by: \.questionId)
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
        firebaseService.userSubmissions.filter { $0.score != nil }.sorted {
            $0.submittedAt < $1.submittedAt
        }
    }

    private var chartDataPoints: [ChartDataPoint] {
        gradedSubmissions.map { sub in
            ChartDataPoint(
                submission: sub,
                taskType: firebaseService.questionMap[sub.questionId]?.taskType
            )
        }
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
            .sorted { $0.avg > $1.avg }
    }

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                ScoreHeaderView(
                    averageScore: serverAverageScore,
                    totalSubmissions: serverTotalSubmissions,
                    task1Count: serverTask1Count,
                    task2Count: serverTask2Count
                )

                // Tab Picker
                Picker(
                    "Selection",
                    selection: $selectedTab
                ) {
                    ForEach(ScoreTab.allCases, id: \.self) { tab in
                        Label(tab.localizedTitle, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Tab Content
                if firebaseService.isLoading && firebaseService.userSubmissions.isEmpty {
                    ProgressView("Loading submissions...")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    tabContentView
                }

                Spacer(minLength: 50)
            }
            .padding(.vertical)
            .background(Color(.systemGroupedBackground))
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Score")
        .toolbarTitleDisplayMode(.large)
        .refreshable { firebaseService.listenUserSubmissions() }
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
            listenServerStats()
            firebaseService.listenUserSubmissions()
            await AIUsageManager.shared.syncUsageFromServer()
        }
        .onDisappear {
            statsListener?.remove()
            statsListener = nil
            // Keep userSubmissionsListener alive — it updates ScoreView from the background.
            // Only stop it if user logs out (handled in VSTEP_WritingApp).
        }
    }

    // MARK: - Tab Content View

    @ViewBuilder
    private var tabContentView: some View {
        switch selectedTab {
        case .submissions:
            submissionsTabContent
        case .analytics:
            analyticsTabContent
        case .insights:
            AIInsightsSection(
                manager: analyticsManager,
                isSubscriber: isSubscriber,
                gradedCount: gradedSubmissions.count,
                store: store
            )
        }
    }

    // MARK: - Submissions Tab

    @ViewBuilder
    private var submissionsTabContent: some View {
        if groupedByQuestion.isEmpty {
            ScoreEmptyView()
        } else {
            AllSubmissionsSection(
                groups: groupedByQuestion,
                onNavigate: { selectedGroup = $0 }
            )
        }
    }

    // MARK: - Analytics Tab

    @ViewBuilder
    private var analyticsTabContent: some View {
        if gradedSubmissions.isEmpty {
            analyticsEmptyView
        } else {
            VStack(spacing: 20) {
                if chartDataPoints.count > 2 {
                    ScoreTrendSection(dataPoints: chartDataPoints)
                }
                if !criteriaAverages.isEmpty {
                    CriteriaBreakdownSection(criteriaAverages: criteriaAverages)
                }
            }
        }
    }

    private var analyticsEmptyView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(BrandColor.muted)
                    .frame(width: 80, height: 80)
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 36))
                    .foregroundStyle(BrandColor.primary)
            }
            Text("No Analytics Yet")
                .font(.headline)
                .foregroundStyle(BrandColor.primary)
            Text("Completed submissions will appear here as a trend chart.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Realtime Stats Listener
    private func listenServerStats() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        statsListener?.remove()
        statsListener = db.collection("users").document(uid)
            .addSnapshotListener { snapshot, _ in
                guard let data = snapshot?.data() else { return }
                if let statsMap = data["stats"] as? [String: Any] {
                    // Fix: Firestore might store averageScore as Int or Double
                    let rawScore = statsMap["averageScore"]
                    self.serverAverageScore =
                        (rawScore as? Double)
                        ?? (rawScore as? Int).map { Double($0) }

                    self.serverTotalSubmissions =
                        statsMap["totalSubmissions"] as? Int ?? 0
                    self.serverTask1Count = statsMap["task1Count"] as? Int ?? 0
                    self.serverTask2Count = statsMap["task2Count"] as? Int ?? 0
                }
                // Note: local recalculation is done in loadSubmissions()
                // where questionMap is guaranteed to be loaded.
            }
    }

    // MARK: - Local Stats Fallback

    private func recalculateStatsLocally() {
        let graded = firebaseService.userSubmissions.filter { $0.status == .graded && $0.score != nil }
        serverAverageScore =
            graded.isEmpty
            ? nil
            : graded.reduce(0.0) { $0 + ($1.score ?? 0) } / Double(graded.count)
        serverTotalSubmissions = graded.count
        serverTask1Count =
            graded.filter {
                firebaseService.questionMap[$0.questionId]?.taskType == "task1"
            }.count
        serverTask2Count =
            graded.filter {
                firebaseService.questionMap[$0.questionId]?.taskType == "task2"
            }.count
    }
}

// MARK: - Score Trend Section

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

            ZStack(alignment: .topLeading) {
                GeometryReader { geo in
                    let drawH = geo.size.height - topPad - bottomPad
                    ForEach(yMarks, id: \.self) { mark in
                        let yPos = topPad + drawH * (1 - mark / 10)
                        Text("\(Int(mark))")
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                            .position(x: 10, y: yPos)
                    }

                    Canvas { context, size in
                        let scores = dataPoints.map(\.score)
                        guard scores.count > 1 else { return }

                        let w = size.width
                        let h = size.height
                        let drawW = w - leftPad - rightPad
                        let drawH = h - topPad - bottomPad
                        let xStep = drawW / CGFloat(scores.count - 1)

                        func point(_ index: Int, _ score: Double) -> CGPoint {
                            CGPoint(
                                x: leftPad + CGFloat(index) * xStep,
                                y: topPad + drawH * (1 - CGFloat(score / 10))
                            )
                        }

                        for mark in yMarks {
                            let y = topPad + drawH * (1 - CGFloat(mark / 10))
                            var gridLine = Path()
                            gridLine.move(to: CGPoint(x: leftPad, y: y))
                            gridLine.addLine(to: CGPoint(x: w - rightPad, y: y))
                            context.stroke(
                                gridLine,
                                with: .color(Color.secondary.opacity(0.12)),
                                style: StrokeStyle(
                                    lineWidth: 0.5,
                                    dash: [4, 3]
                                )
                            )
                        }

                        var area = Path()
                        area.move(to: CGPoint(x: leftPad, y: topPad + drawH))
                        for (i, score) in scores.enumerated() {
                            area.addLine(to: point(i, score))
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

                        var line = Path()
                        for (i, score) in scores.enumerated() {
                            let p = point(i, score)
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

                        for (i, dp) in dataPoints.enumerated() {
                            let p = point(i, dp.score)
                            let isSelected = selectedIndex == i
                            let dotSize: CGFloat = isSelected ? 10 : 7
                            let glowSize: CGFloat = isSelected ? 16 : 12
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

                        if let idx = selectedIndex, idx < dataPoints.count {
                            let dp = dataPoints[idx]
                            let p = point(idx, dp.score)
                            let text = Text(String(format: "%.1f", dp.score))
                                .font(.system(size: 12, weight: .bold))
                                .monospacedDigit().foregroundColor(.white)
                            let resolved = context.resolve(text)
                            let textSize = resolved.measure(
                                in: CGSize(width: 60, height: 30)
                            )

                            let labelW = textSize.width + 12
                            let labelH = textSize.height + 8
                            let labelY = p.y - labelH - 10
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

                            var arrow = Path()
                            arrow.move(
                                to: CGPoint(x: p.x - 4, y: labelY + labelH)
                            )
                            arrow.addLine(
                                to: CGPoint(x: p.x, y: labelY + labelH + 5)
                            )
                            arrow.addLine(
                                to: CGPoint(x: p.x + 4, y: labelY + labelH)
                            )
                            arrow.closeSubpath()
                            context.fill(arrow, with: .color(dp.dotColor))
                            context.draw(
                                resolved,
                                at: CGPoint(x: p.x, y: labelY + labelH / 2),
                                anchor: .center
                            )
                        }
                    }
                    .frame(height: chartHeight)

                    GeometryReader { geo in
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                let count = dataPoints.count
                                guard count > 1 else { return }
                                let drawW = geo.size.width - leftPad - rightPad
                                let xStep = drawW / CGFloat(count - 1)
                                let idx = Int(
                                    ((location.x - leftPad) / xStep).rounded()
                                )
                                let clamped = max(0, min(count - 1, idx))
                                withAnimation(.easeOut(duration: 0.15)) {
                                    selectedIndex =
                                        selectedIndex == clamped ? nil : clamped
                                }
                            }
                            .frame(height: chartHeight)
                    }
                }
                .frame(height: chartHeight)
            }

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
                    Text(mid.date, format: .dateTime.day().month(.abbreviated))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if let last = dataPoints.last {
                    Text(last.date, format: .dateTime.day().month(.abbreviated))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)

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
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption2).foregroundStyle(.secondary)
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
                        Text(item.name).font(.subheadline).foregroundStyle(
                            .primary
                        )
                        Spacer()
                        Text(String(format: "%.1f", item.avg))
                            .font(.subheadline.bold()).monospacedDigit()
                            .foregroundStyle(criteriaColor(item.avg))
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(.systemFill)).frame(height: 6)
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
                        .frame(height: 6)
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

// MARK: - All Submissions Section

private struct AllSubmissionsSection: View {

    let groups: [QuestionAttemptGroup]
    let onNavigate: (QuestionAttemptGroup) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(
                    title: "All Submissions",
                    icon: "doc.text.fill"
                )
                Spacer()
                Text("\(groups.count) Questions")
                .font(.subheadline).foregroundStyle(.secondary)
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
                .font(.headline).foregroundStyle(.secondary)
            if let score = averageScore {
                Text(String(format: "%.1f", score))
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(scoreColor)
                    .contentTransition(.numericText())
            } else {
                Text("–")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            if totalSubmissions > 0 {
                HStack(spacing: 28) {
                    StatChip(
                        icon: "doc.text.fill",
                        value: totalSubmissions,
                        label: "Total"
                    )
                    StatChip(
                        icon: "1.circle.fill",
                        value: task1Count,
                        label: "Task 1",
                        color: BrandColor.light
                    )
                    StatChip(
                        icon: "2.circle.fill",
                        value: task2Count,
                        label: "Task 2",
                        color: BrandColor.medium
                    )
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal)
        .glassEffect(in: .rect(cornerRadius: 16))
        .padding(.horizontal)
    }
}

// MARK: - Stat Chip

struct StatChip: View {

    let icon: String
    let value: Int
    let label: String
    var color: Color = BrandColor.primary

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(color).font(.subheadline)
            Text("\(value)").font(.title3.bold()).foregroundStyle(.primary)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Error Banner View

struct ErrorBannerView: View {

    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BrandColor.soft)
            Text(message).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Button("Retry", action: onRetry)
                .font(.subheadline.bold())
                .foregroundStyle(BrandColor.primary)
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: 16))
        .padding(.horizontal)
    }
}

// MARK: - Empty State

struct ScoreEmptyView: View {
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(BrandColor.muted).frame(width: 80, height: 80)
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 36)).foregroundStyle(BrandColor.primary)
            }
            Text("No Submissions Yet")
                .font(.headline).foregroundStyle(BrandColor.primary)
            Text("Complete your first essay to see your history here.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
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
                        .font(.headline).lineLimit(2)
                    HStack(spacing: 8) {
                        BadgeLabel(text: taskBadgeText, color: taskColor)
                        Image(systemName: "clock").font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(
                            group.latestAttempt.submittedAt,
                            format: .dateTime.day().month(.abbreviated).hour()
                                .minute()
                        )
                        .font(.caption).foregroundStyle(.secondary)
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
                        .font(.caption.weight(.semibold)).foregroundStyle(
                            .secondary
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4).padding(.vertical, 12).padding(
                        .trailing,
                        4
                    )
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
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
            Text("\(attemptNumber)")
                .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                .frame(width: 32, alignment: .center)
            Text(
                submission.submittedAt,
                format: .dateTime.day().month(.abbreviated).year().hour()
                    .minute()
            )
            .font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            AttemptScoreView(submission: submission, compact: true)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
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
                Text("/10").font(.caption2).foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 3) {
                Image(systemName: submission.status.icon)
                    .font(compact ? .caption : .subheadline).foregroundStyle(
                        statusColor
                    )
                Text(submission.status.displayText)
                    .font(.caption2.weight(.medium)).foregroundStyle(
                        statusColor
                    )
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
            .font(.caption2.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(.rect(cornerRadius: 5))
    }
}

// MARK: - AI Insights Section

private struct AIInsightsSection: View {

    @ObservedObject var manager: AnalyticsManager
    let isSubscriber: Bool
    let gradedCount: Int
    let store: StoreKitManager

    @Environment(\.colorScheme) private var colorScheme

    private var remaining: Int {
        max(
            0,
            AIUsageManager.shared.insightLimitPerWeek
                - AIUsageManager.shared.insightUsedThisWeek
        )
    }

    private var weeklyLimit: Int {
        AIUsageManager.shared.insightLimitPerWeek
    }

    private var adaptiveGlassTint: Color {
        colorScheme == .dark ? Color.clear : BrandColor.muted
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isSubscriber {
                insightsLockedCard
            } else if gradedCount < 2 {
                insightsNotEnoughCard
            } else if manager.isFetching {
                insightsSkeleton
            } else if manager.errorMessage == "needmoresubmissions" {
                insightsNotEnoughCard
            } else if manager.errorMessage == "quotaexceeded" {
                quotaExhaustedCard
            } else if let error = manager.errorMessage {
                insightsErrorCard(message: error)
            } else if let insights = manager.insights {
                insightsCard(insights: insights)
            } else {
                insightsReadyCard
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Ready Card

    private var insightsReadyCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(BrandColor.muted).frame(width: 48, height: 48)
                    Image(systemName: "sparkles").font(.title3).foregroundStyle(
                        BrandColor.primary
                    )
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Progress Insights")
                        .font(.body.weight(.semibold)).foregroundStyle(
                            BrandColor.primary
                        )
                    Text("Your AI-powered progress analysis is ready.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            Button {
                manager.loadInsights()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").font(.subheadline)
                    Text("Analyze Progress")
                        .font(.subheadline.bold())
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(BrandColor.primary).clipShape(
                    .rect(cornerRadius: 10)
                )
            }

            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise.circle").font(.caption)
                Text("\(remaining) / \(weeklyLimit) refreshes available this week")
                .font(.caption).foregroundStyle(.secondary)
            }
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
                        .font(.body.weight(.semibold)).foregroundStyle(
                            BrandColor.primary
                        )
                    Text("Advanced")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(
                            .white
                        )
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(BrandColor.soft))
                }
                Text("Unlock deep analysis of your writing style and improvement tips.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            NavigationLink {
                SubscriptionsView()
            } label: {
                Text("Upgrade")
                    .font(.caption.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(BrandColor.primary))
            }
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: 16.0))
    }

    // MARK: - Not Enough Card

    private var insightsNotEnoughCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(BrandColor.muted).frame(width: 44, height: 44)
                Image(systemName: "doc.text.magnifyingglass").foregroundStyle(
                    BrandColor.medium
                )
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Progress Insights")
                    .font(.body.weight(.semibold)).foregroundStyle(
                        BrandColor.primary
                    )
                Text("Complete at least 2 graded submissions to generate AI insights.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: 16.0))
    }

    // MARK: - Quota Exhausted Card

    private var quotaExhaustedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(BrandColor.muted).frame(width: 44, height: 44)
                    Image(systemName: "calendar.badge.clock").foregroundStyle(
                        BrandColor.soft
                    )
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Weekly Insights Quota")
                        .font(.body.weight(.semibold)).foregroundStyle(
                            BrandColor.primary
                        )
                    Text("\(weeklyLimit) / \(weeklyLimit) insights used this week.")
                    .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Text("0 Left")
                    .font(.caption.bold()).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .glassEffect(in: .capsule)
            }

            Text("Your quota resets every Monday. You can still view your last analysis below.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let insights = manager.insights {
                Divider()
                staleInsightsBanner
                insightsContent(insights: insights)
                Divider()
                autoRefreshToggle
            }
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: 16.0))
    }

    // MARK: - Stale Banner

    private var staleInsightsBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.subheadline).foregroundStyle(.orange)
            Text("Showing result from previous week")
                .font(.subheadline)
                .foregroundStyle(.orange)
            Spacer()
            if let ts = manager.cachedAt {
                Text(formattedDate(ts)).font(.caption2).foregroundStyle(
                    .tertiary
                )
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Skeleton

    private var insightsSkeleton: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(BrandColor.light)
                Text("AI is analyzing...")
                    .font(.body.weight(.semibold)).foregroundStyle(
                        BrandColor.primary
                    )
                Spacer()
                ProgressView().scaleEffect(0.7)
            }

            if let progress = manager.analysisProgress {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(progress.label).font(.subheadline).foregroundStyle(
                            .secondary
                        )
                        Spacer()
                        Text("\(progress.step)/\(progress.total)")
                            .font(.caption2.monospacedDigit()).foregroundStyle(
                                .tertiary
                            )
                    }
                    ProgressView(value: progress.percentage)
                        .tint(BrandColor.primary)
                        .animation(
                            .easeInOut(duration: 0.4),
                            value: progress.percentage
                        )
                }
            } else {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15)).frame(height: 12)
                }
            }
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: 16.0))
    }

    // MARK: - Error Card

    private func insightsErrorCard(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(
                BrandColor.soft
            )
            Text(message).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Button("Retry") { manager.loadInsights() }
                .font(.subheadline.bold()).foregroundStyle(BrandColor.primary)
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
                    .font(.body.weight(.semibold)).foregroundStyle(
                        BrandColor.primary
                    )
                Spacer()
                Label(
                    insights.trendLabel.label,
                    systemImage: insights.trendLabel.icon
                )
                .font(.subheadline.bold()).foregroundStyle(
                    insights.trendLabel.color
                )
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(
                    Capsule().fill(insights.trendLabel.color.opacity(0.15))
                )

                quotaBadge
                Button {
                    manager.loadInsights(forceRefresh: true)
                } label: {
                    Image(systemName: "arrow.clockwise").font(.caption)
                        .foregroundStyle(
                            remaining > 0 ? BrandColor.medium : Color.secondary
                        )
                }
                .disabled(remaining <= 0)
            }

            insightsContent(insights: insights)
            Divider()
            autoRefreshToggle
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

    // MARK: - Insights Content

    private func insightsContent(insights: UserProgressInsights) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(insights.overallInsight)
                .font(.body).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(
                    .regular.tint(adaptiveGlassTint),
                    in: .rect(cornerRadius: 10)
                )

            Divider()
            insightCardList(
                title: "Key Strengths",
                count: insights.strengths.count,
                icon: "checkmark.circle.fill",
                accentColor: .green,
                tintColor: Color.green.opacity(0.06),
                items: insights.strengths
            )

            insightCardList(
                title: "Areas for Improvement",
                count: insights.weaknesses.count,
                icon: "exclamationmark.triangle.fill",
                accentColor: .orange,
                tintColor: Color.orange.opacity(0.06),
                items: insights.weaknesses
            )

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Label(
                    "Targeted Advice",
                    systemImage: "lightbulb.fill"
                )
                .font(.subheadline.weight(.semibold)).foregroundStyle(
                    BrandColor.medium
                )

                ForEach(insights.recommendations) { rec in
                    HStack(alignment: .top, spacing: 10) {
                        Text(rec.area).font(.subheadline.bold())
                            .foregroundStyle(BrandColor.primary)
                            .frame(width: 90, alignment: .leading)
                        Text(rec.tip).font(.subheadline).foregroundStyle(
                            .secondary
                        )
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Divider()
            HStack(spacing: 10) {
                Image(systemName: "target").foregroundStyle(BrandColor.primary)
                    .font(.subheadline)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Next Goal")
                        .font(.subheadline.bold()).foregroundStyle(
                            BrandColor.medium
                        )
                    Text(insights.nextGoal).font(.subheadline).foregroundStyle(
                        .primary
                    )
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(
                .regular.tint(adaptiveGlassTint),
                in: .rect(cornerRadius: 10)
            )
        }
    }

    // MARK: - Insight Card List

    private func insightCardList(
        title: String,
        count: Int,
        icon: String,
        accentColor: Color,
        tintColor: Color,
        items: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.subheadline).foregroundStyle(
                    accentColor
                )
                Text(title).font(.subheadline.weight(.semibold))
                    .foregroundStyle(accentColor)
                Text("\(count)").font(.caption.weight(.bold)).foregroundStyle(
                    accentColor.opacity(0.7)
                )
                Spacer()
            }

            VStack(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: icon).font(.system(size: 13))
                            .foregroundStyle(accentColor)
                            .frame(width: 24, height: 24)
                            .background(accentColor.opacity(0.12)).clipShape(
                                Circle()
                            )
                        Text(item).font(.subheadline).foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(tintColor).clipShape(.rect(cornerRadius: 8))
                }
            }
        }
    }

    // MARK: - Quota Badge

    private var quotaBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.clockwise.circle").font(.caption2)
            Text("\(remaining)/\(weeklyLimit)").font(
                .caption2.monospacedDigit()
            )
        }
        .foregroundStyle(
            remaining > 0 ? BrandColor.medium : Color.secondary
        )
        .padding(.horizontal, 7).padding(.vertical, 4)
        .glassEffect(in: .capsule)
    }

    // MARK: - Auto Refresh Toggle

    private var autoRefreshToggle: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Auto-refresh Insights")
                    .font(.body.weight(.medium)).foregroundStyle(.primary)
                Text("Automatically analyze progress when new results are available.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(
                "",
                isOn: Binding(
                    get: { manager.autoRefresh },
                    set: { manager.autoRefresh = $0 }
                )
            )
            .labelsHidden()
            .tint(BrandColor.primary)
        }
        .padding(12)
        .glassEffect(
            .regular.tint(adaptiveGlassTint),
            in: .rect(cornerRadius: 10)
        )
    }

    // MARK: - Helper

    private func formattedDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        guard let date = f.date(from: iso) else { return iso }
        let df = DateFormatter()
        df.dateFormat = "dd/MM HH:mm"
        return df.string(from: date)
    }
}

// MARK: - Safe subscript helper

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
