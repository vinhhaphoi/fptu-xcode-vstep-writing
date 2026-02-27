// LearnView.swift
import SwiftUI

// MARK: - LearnView

struct LearnView: View {
    @StateObject private var firebaseService = FirebaseService.shared
    @State private var submittedIds: Set<String> = []
    @State private var latestSubmissions: [String: UserSubmission] = [:]
    @State private var allSubmissions: [String: [UserSubmission]] = [:]
    @State private var showError = false
    @State private var errorMsg = ""
    @State private var selectedRankID: String? = nil

    // Cache key — chi dung cho offline fallback, KHONG inject nguoc khi online
    private let cacheKey = "cached_latest_submissions"

    private var task1Questions: [VSTEPQuestion] {
        firebaseService.questions.filter { $0.isTask1 }
    }

    private var task2Questions: [VSTEPQuestion] {
        firebaseService.questions.filter { $0.isTask2 }
    }

    private var displayedRanks: [VSTEPRank] {
        guard let id = selectedRankID else { return VSTEPRank.allRanks }
        return VSTEPRank.allRanks.filter { $0.id == id }
    }

    var body: some View {
        Group {
            if firebaseService.isLoading && firebaseService.questions.isEmpty {
                LearnLoadingView()
            } else if firebaseService.questions.isEmpty {
                LearnEmptyView { Task { await loadData() } }
            } else {
                mainContent
            }
        }
        .navigationTitle("Learn")
        .toolbarTitleDisplayMode(.large)
        .background(Color(.systemGroupedBackground))
        .refreshable { await loadData() }
        .task { await loadData() }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMsg)
        }
        .onDisappear {
            firebaseService.stopAllListeners()
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                RankFilterRow(
                    ranks: VSTEPRank.allRanks,
                    selectedID: $selectedRankID
                )

                ForEach(displayedRanks) { rank in
                    RankSection(
                        rank: rank,
                        task1Questions: task1Questions,
                        task2Questions: task2Questions,
                        submittedIds: submittedIds,
                        latestSubmissions: latestSubmissions,
                        allSubmissions: allSubmissions,
                        onSubmit: handleSubmit,
                        onRefresh: loadData
                    )
                }

                Spacer(minLength: 40)
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Submit Handler

    private func handleSubmit(question: VSTEPQuestion, essayText: String) {
        let wordCount =
            essayText
            .split(separator: " ")
            .filter { !$0.isEmpty }
            .count

        let newSubmission = UserSubmission(
            questionId: question.questionId,
            content: essayText,
            wordCount: wordCount,
            submittedAt: Date(),
            score: nil,
            feedback: nil,
            status: .submitted
        )

        // Optimistic update — hien thi ngay tren UI truoc khi Firestore confirm
        latestSubmissions[question.questionId] = newSubmission
        allSubmissions[question.questionId, default: []].insert(
            newSubmission,
            at: 0
        )
        submittedIds.insert(question.questionId)

        Task { [firebaseService] in
            do {
                let docId = try await firebaseService.submitEssay(newSubmission)

                firebaseService.listenForGradingResult(
                    submissionId: docId,
                    questionId: question.questionId,
                    onChange: { updated in
                        self.latestSubmissions[question.questionId] = updated
                        if var history = self.allSubmissions[
                            question.questionId
                        ],
                            !history.isEmpty
                        {
                            history[0] = updated
                            self.allSubmissions[question.questionId] = history
                        }
                        // Luu cache moi lan AI cap nhat trang thai
                        self.saveLocalCache()
                    },
                    onTimeout: {
                        // Timeout: danh dau failed, giu lai content
                        var timedOut = newSubmission
                        timedOut.status = .failed
                        self.latestSubmissions[question.questionId] = timedOut
                        if var history = self.allSubmissions[
                            question.questionId
                        ],
                            !history.isEmpty
                        {
                            history[0] = timedOut
                            self.allSubmissions[question.questionId] = history
                        }
                        self.saveLocalCache()
                        self.errorMsg =
                            "AI grading timed out after 2 minutes. Please try again."
                        self.showError = true
                    }
                )
            } catch {
                // Rollback optimistic update neu submit that bai
                await MainActor.run {
                    latestSubmissions.removeValue(forKey: question.questionId)
                    allSubmissions[question.questionId]?.removeFirst()
                    if allSubmissions[question.questionId]?.isEmpty == true {
                        allSubmissions.removeValue(forKey: question.questionId)
                    }
                    submittedIds.remove(question.questionId)
                    errorMsg = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    // MARK: - Data Loading
    // Firestore la source of truth — cache chi dung khi offline (fetch that bai)

    private func loadData() async {
        do {
            try await firebaseService.fetchQuestions()
            guard firebaseService.currentUserId != nil else { return }
            try? await firebaseService.fetchUserProgress()

            if let subs = try? await firebaseService.fetchUserSubmissions() {
                var latestMap: [String: UserSubmission] = [:]
                var allMap: [String: [UserSubmission]] = [:]

                for sub in subs {
                    if latestMap[sub.questionId] == nil {
                        latestMap[sub.questionId] = sub
                    }
                    allMap[sub.questionId, default: []].append(sub)
                }

                // Firestore = source of truth
                // KHONG inject cache nguoc — neu Firestore khong co record thi khong hien
                latestSubmissions = latestMap
                allSubmissions = allMap
                submittedIds = Set(latestMap.keys)

                // Cap nhat cache theo Firestore hien tai (overwrite, khong merge)
                saveLocalCache()
            } else {
                // fetchUserSubmissions tra ve nil nhung khong throw
                // Giu nguyen UI hien tai, khong thay doi gi
            }
        } catch {
            // Fetch that bai hoan toan (offline / network error)
            // Fallback ve cache de hien thi du lieu cu
            let cached = loadLocalCache()
            if !cached.isEmpty {
                latestSubmissions = cached
                allSubmissions = cached.mapValues { [$0] }
                submittedIds = Set(cached.keys)
            }
            errorMsg = error.localizedDescription
            showError = true
        }
    }

    // MARK: - Local Cache Helpers
    // Cache chi luu submission co score (graded) de dung khi offline

    private func saveLocalCache() {
        guard let userId = firebaseService.currentUserId else { return }
        let key = "\(cacheKey)_\(userId)"
        // Chi luu graded submission (co score) — bo qua submitted/grading/failed
        let toCache = latestSubmissions.filter { $0.value.score != nil }
        if let encoded = try? JSONEncoder().encode(toCache) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }

    private func loadLocalCache() -> [String: UserSubmission] {
        guard let userId = firebaseService.currentUserId else { return [:] }
        let key = "\(cacheKey)_\(userId)"
        guard let data = UserDefaults.standard.data(forKey: key),
            let decoded = try? JSONDecoder().decode(
                [String: UserSubmission].self,
                from: data
            )
        else { return [:] }
        return decoded
    }
}

// MARK: - Rank Filter Row

struct RankFilterRow: View {
    let ranks: [VSTEPRank]
    @Binding var selectedID: String?

    private func selectAll() {
        withAnimation(.easeInOut(duration: 0.2)) { selectedID = nil }
    }

    private func toggle(_ rankID: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedID = selectedID == rankID ? nil : rankID
        }
    }

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button(action: selectAll) {
                        Text("All")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(
                                selectedID == nil ? .white : .primary
                            )
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .glassEffect(
                                .regular.tint(
                                    selectedID == nil ? .blue : .clear
                                ).interactive(),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)

                    ForEach(ranks) { rank in
                        Button(action: { toggle(rank.id) }) {
                            Text(rank.cefr)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(
                                    selectedID == rank.id ? .white : .primary
                                )
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .glassEffect(
                                    .regular.tint(
                                        selectedID == rank.id
                                            ? rank.color : .clear
                                    ).interactive(),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .background(Color(.systemGroupedBackground))
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Rank Section

struct RankSection: View {
    let rank: VSTEPRank
    let task1Questions: [VSTEPQuestion]
    let task2Questions: [VSTEPQuestion]
    let submittedIds: Set<String>
    let latestSubmissions: [String: UserSubmission]
    let allSubmissions: [String: [UserSubmission]]
    var onSubmit: ((VSTEPQuestion, String) -> Void)? = nil
    var onRefresh: (() async -> Void)? = nil

    private func filtered(_ pool: [VSTEPQuestion]) -> [VSTEPQuestion] {
        pool.filter { rank.difficulties.contains($0.difficulty.lowercased()) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("VSTEP \(rank.cefr)")
                    .font(.headline)
                Text(rank.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            VStack(spacing: 0) {
                ForEach(
                    Array(rank.taskCategories.enumerated()),
                    id: \.offset
                ) { index, category in
                    let pool =
                        category.taskType == "task1"
                        ? filtered(task1Questions)
                        : filtered(task2Questions)

                    NavigationLink(
                        destination: TaskQuestionListView(
                            title: category.title,
                            questions: pool,
                            submittedIds: submittedIds,
                            latestSubmissions: latestSubmissions,
                            allSubmissions: allSubmissions,
                            onSubmit: onSubmit,
                            onRefresh: onRefresh
                        )
                    ) {
                        HStack(spacing: 15) {
                            Image(systemName: category.icon)
                                .font(.system(size: 24))
                                .foregroundStyle(category.color)
                                .frame(width: 40)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(category.title)
                                    .font(.system(size: 17, weight: .regular))
                                    .foregroundStyle(.primary)
                                Text(category.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if !pool.isEmpty {
                                Text("\(pool.count)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(category.color)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(category.color.opacity(0.1))
                                    .clipShape(Capsule())
                            }

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(.tertiaryLabel))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                    .buttonStyle(.plain)
                    .disabled(pool.isEmpty)

                    if index < rank.taskCategories.count - 1 {
                        Divider().padding(.leading, 70)
                    }
                }
            }
            .glassEffect(in: .rect(cornerRadius: 16.0))
            .padding(.horizontal)
        }
    }
}

// MARK: - Task Question List

struct TaskQuestionListView: View {
    let title: String
    let questions: [VSTEPQuestion]
    let submittedIds: Set<String>
    let latestSubmissions: [String: UserSubmission]
    let allSubmissions: [String: [UserSubmission]]
    var onSubmit: ((VSTEPQuestion, String) -> Void)? = nil
    var onRefresh: (() async -> Void)? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                if questions.isEmpty {
                    emptyBlock
                } else {
                    ForEach(
                        Array(questions.enumerated()),
                        id: \.element.questionId
                    ) { index, question in
                        QuestionRow(
                            number: extractNumber(from: question.questionId),
                            question: question,
                            latestSubmission: latestSubmissions[
                                question.questionId
                            ],
                            submissionHistory: allSubmissions[
                                question.questionId
                            ] ?? [],
                            isCompleted: submittedIds.contains(
                                question.questionId
                            ),
                            onSubmit: { essayText in
                                onSubmit?(question, essayText)
                            },
                            onRefresh: onRefresh
                        )
                        .glassEffect()
                        .padding(.horizontal)
                    }
                }
                Spacer(minLength: 60)
            }
            .padding(.top, 16)
            .background(Color(.systemGroupedBackground))
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
        .toolbarTitleDisplayMode(.inline)
    }

    private var emptyBlock: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No questions available for this level")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .glassEffect(in: .rect(cornerRadius: 16.0))
        .padding(.horizontal)
    }

    private func extractNumber(from questionId: String) -> Int {
        Int(questionId.filter(\.isNumber)) ?? 0
    }
}

// MARK: - Question Row

private struct QuestionRow: View {
    let number: Int
    let question: VSTEPQuestion
    let latestSubmission: UserSubmission?
    let submissionHistory: [UserSubmission]
    let isCompleted: Bool
    var onSubmit: ((String) -> Void)? = nil
    var onRefresh: (() async -> Void)? = nil

    var body: some View {
        NavigationLink(
            destination: QuestionDetailView(
                question: question,
                questionNumber: number,
                latestSubmission: isCompleted ? latestSubmission : nil,
                submissionHistory: isCompleted ? submissionHistory : [],
                onSubmit: onSubmit,
                onRefresh: onRefresh
            )
        ) {
            HStack(spacing: 15) {
                Text(String(format: "%02d", number))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        isCompleted ? .green : Color(.tertiaryLabel)
                    )
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text(question.title)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(question.difficulty.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                trailingView

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var trailingView: some View {
        if let score = latestSubmission?.score {
            VStack(spacing: 1) {
                Text(String(format: "%.1f", score))
                    .font(.subheadline.bold())
                    .foregroundStyle(scoreColor(score))
                Text("/ 10")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if isCompleted {
            if latestSubmission?.status == .grading {
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.6)
                    Text("AI Grading")
                        .font(.callout)
                        .foregroundStyle(.blue)
                }
            } else {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                    Text("Pending")
                        .font(.callout)
                        .foregroundStyle(.orange)
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

// MARK: - Loading View

struct LearnLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView().scaleEffect(1.2)
            Text("Loading questions")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Empty View

struct LearnEmptyView: View {
    let onReload: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No questions available")
                .foregroundStyle(.secondary)
            Button("Reload", action: onReload)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - VSTEP Rank Model

struct VSTEPRank: Identifiable {
    let id: String
    let cefr: String
    let displayName: String
    let color: Color
    let difficulties: [String]
    let taskCategories: [TaskCategory]

    struct TaskCategory {
        let title: String
        let subtitle: String
        let icon: String
        let color: Color
        let taskType: String
    }
}

extension VSTEPRank {
    static let allRanks: [VSTEPRank] = [
        VSTEPRank(
            id: "b1",
            cefr: "B1",
            displayName: "Pre-Intermediate",
            color: .blue,
            difficulties: ["easy"],
            taskCategories: [
                TaskCategory(
                    title: "Task 1 - Visual Description",
                    subtitle: "Describe a chart, graph or table",
                    icon: "chart.bar",
                    color: .blue,
                    taskType: "task1"
                ),
                TaskCategory(
                    title: "Task 2 - Opinion Essay",
                    subtitle: "Give your opinion on a familiar topic",
                    icon: "text.bubble",
                    color: .indigo,
                    taskType: "task2"
                ),
            ]
        ),
        VSTEPRank(
            id: "b2",
            cefr: "B2",
            displayName: "Upper-Intermediate",
            color: .purple,
            difficulties: ["medium"],
            taskCategories: [
                TaskCategory(
                    title: "Task 1 - Data Analysis",
                    subtitle: "Analyse trends and compare data",
                    icon: "chart.line.uptrend.xyaxis",
                    color: .purple,
                    taskType: "task1"
                ),
                TaskCategory(
                    title: "Task 2 - Argumentative Essay",
                    subtitle: "Argue both sides of a complex issue",
                    icon: "text.book.closed",
                    color: .orange,
                    taskType: "task2"
                ),
            ]
        ),
        VSTEPRank(
            id: "c1",
            cefr: "C1",
            displayName: "Advanced",
            color: .red,
            difficulties: ["hard"],
            taskCategories: [
                TaskCategory(
                    title: "Task 1 - Complex Visuals",
                    subtitle: "Synthesise data from multiple charts",
                    icon: "chart.pie",
                    color: .red,
                    taskType: "task1"
                ),
                TaskCategory(
                    title: "Task 2 - Critical Essay",
                    subtitle: "Evaluate ideas with advanced vocabulary",
                    icon: "doc.richtext",
                    color: .pink,
                    taskType: "task2"
                ),
            ]
        ),
    ]
}
