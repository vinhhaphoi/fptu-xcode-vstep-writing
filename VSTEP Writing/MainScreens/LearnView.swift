import SwiftUI

// MARK: - LearnView
struct LearnView: View {

    @StateObject private var firebaseService = FirebaseService.shared
    @Environment(StoreKitManager.self) private var store
    @State private var submittedIds: Set<String> = []
    @State private var latestSubmissions: [String: UserSubmission] = [:]
    @State private var allSubmissions: [String: [UserSubmission]] = [:]
    @State private var showError = false
    @State private var errorMsg = ""
    @State private var selectedRankID: String? = nil
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var isRefreshing = false

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

    private var searchResults: [VSTEPQuestion] {
        guard !searchText.isEmpty else { return [] }
        return firebaseService.questions.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.difficulty.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Body

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
        .searchable(
            text: $searchText,
            isPresented: $isSearchPresented,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search questions..."
        )
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
                if !searchText.isEmpty {
                    searchContent
                } else {
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
                            store: store,
                            onRefresh: {
                                guard !isRefreshing else { return }
                                await loadData()
                            }
                        )
                    }

                    Spacer(minLength: 40)
                }
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Search Content

    private var searchContent: some View {
        Group {
            if searchResults.isEmpty {
                emptySearchBlock
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(
                        Array(searchResults.enumerated()),
                        id: \.element.questionId
                    ) { index, question in
                        SearchResultRow(question: question)
                        if index < searchResults.count - 1 {
                            Divider().padding(.leading, 70)
                        }
                    }
                }
                .glassEffect(in: .rect(cornerRadius: 16))
                .padding(.horizontal)
            }
        }
    }

    private var emptySearchBlock: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No results for \"\(searchText)\"")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .glassEffect(in: .rect(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - Submit Handler
    // Server handles quota enforcement — no local canSubmit check needed

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

        // Optimistic update — show immediately before Firestore confirms
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
                        self.saveLocalCache()
                    },
                    onTimeout: {
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

    private func loadData() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
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

                latestSubmissions = latestMap
                allSubmissions = allMap
                submittedIds = Set(latestMap.keys)
                saveLocalCache()
            }
        } catch {
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

    private func saveLocalCache() {
        guard let userId = firebaseService.currentUserId else { return }
        let key = "\(cacheKey)_\(userId)"
        let toCache = latestSubmissions.filter { $0.value.score != nil }
        if let encoded = try? JSONEncoder().encode(toCache) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }

    private func loadLocalCache() -> [String: UserSubmission] {
        guard let userId = firebaseService.currentUserId else { return [:] }
        let key = "\(cacheKey)_\(userId)"
        guard
            let data = UserDefaults.standard.data(forKey: key),
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
                                    selectedID == nil
                                        ? BrandColor.primary : .clear
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
    let store: StoreKitManager
    var onRefresh: (() async -> Void)? = nil

    private func filtered(_ pool: [VSTEPQuestion]) -> [VSTEPQuestion] {
        pool.filter { rank.difficulties.contains($0.difficulty.lowercased()) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("VSTEP \(rank.cefr)")
                    .font(.headline)
                    .foregroundStyle(BrandColor.primary)
                Text(rank.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            VStack(spacing: 0) {
                ForEach(Array(rank.taskCategories.enumerated()), id: \.offset) {
                    index,
                    category in
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
                            store: store
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
    let store: StoreKitManager
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
                            store: store
                        )
                    }
                    .glassEffect()
                    .padding(.horizontal)
                }

                Spacer(minLength: 60)
            }
            .padding(.top, 16)
            .background(Color(.systemGroupedBackground))
        }
        .refreshable { await onRefresh?() }
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
    let store: StoreKitManager
    var onRefresh: (() async -> Void)? = nil

    var body: some View {
        NavigationLink(
            destination: QuestionDetailView(
                question: question,
                questionNumber: number,
                latestSubmission: isCompleted ? latestSubmission : nil,
                submissionHistory: isCompleted ? submissionHistory : [],
                store: store
            )
        ) {
            HStack(spacing: 15) {
                Text(String(format: "%02d", number))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        isCompleted ? BrandColor.light : Color(.tertiaryLabel)
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
                        .foregroundStyle(BrandColor.primary)
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
        } else {
            // Unstarted question — server manages limits, show neutral state
            HStack(spacing: 3) {
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(BrandColor.soft)
                Text("Start")
                    .font(.caption2)
                    .foregroundStyle(BrandColor.medium)
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
                .tint(BrandColor.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}
