import SwiftUI

// MARK: - QuestionDetailView
struct QuestionDetailView: View {

    let question: VSTEPQuestion
    var questionNumber: Int = 0
    var latestSubmission: UserSubmission? = nil
    var submissionHistory: [UserSubmission] = []
    let store: StoreKitManager  // Added: for usage limit checks
    var onSubmit: ((String) -> Void)? = nil
    var onRefresh: (() async -> Void)? = nil

    @State private var showHistorySheet = false
    @State private var essayText = ""
    @State private var showSubmitConfirm = false
    @State private var isSubmitting = false
    @State private var isResubmitting = false
    @State private var showLimitAlert = false
    @State private var limitAlertMessage = ""

    private var taskColor: Color {
        question.isTask1 ? BrandColor.light : BrandColor.medium
    }
    private var hasHistory: Bool { !submissionHistory.isEmpty }
    private var wordCount: Int {
        essayText.split(separator: " ").filter { !$0.isEmpty }.count
    }
    private var minWords: Int { question.minWords }

    private var remainingGrading: Int {
        AIUsageManager.shared.remainingGrading(
            for: question.questionId,
            store: store
        )
    }

    private var canSubmitToday: Bool {
        AIUsageManager.shared.canSubmit(
            questionId: question.questionId,
            store: store
        ).isAllowed
    }

    private var shouldShowWritingForm: Bool {
        latestSubmission == nil || isResubmitting
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let submission = latestSubmission, !isResubmitting {
                    SubmissionReviewView(
                        question: question,
                        submission: submission,
                        taskColor: taskColor
                    )
                } else {
                    promptContent
                    writingSection
                }

                Spacer(minLength: 40)
            }
            .padding()
        }
        .refreshable { await onRefresh?() }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Question \(questionNumber)")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    // Placeholder for report action
                } label: {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.red)
                }
            }

            if isResubmitting {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        isResubmitting = false
                        essayText = ""
                    }
                    .tint(.red)
                }
            } else {
                if latestSubmission != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            // Check grading limit before allowing re-submit
                            let check = AIUsageManager.shared.canGrade(
                                questionId: question.questionId,
                                store: store
                            )
                            guard check.isAllowed else {
                                limitAlertMessage =
                                    check.deniedReason ?? "Limit reached."
                                showLimitAlert = true
                                return
                            }
                            essayText = ""
                            isResubmitting = true
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .foregroundStyle(BrandColor.primary)
                        }
                    }
                }

                if hasHistory {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showHistorySheet = true
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(BrandColor.primary)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showHistorySheet) {
            GradingHistorySheet(history: submissionHistory)
        }
        .confirmationDialog(
            isResubmitting
                ? "Re-submit for AI Grading?" : "Submit for AI Grading?",
            isPresented: $showSubmitConfirm,
            titleVisibility: .visible
        ) {
            Button("Submit") {
                isSubmitting = true
                onSubmit?(essayText)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if isResubmitting {
                Text(
                    "This will create a new submission attempt. Your previous result will be saved in history. Results typically appear within 10–30 seconds."
                )
            } else {
                Text(
                    "Your essay will be automatically graded by Gemini AI. Results typically appear within 10–30 seconds. Once submitted, you cannot edit this attempt."
                )
            }
        }
        .alert("Limit Reached", isPresented: $showLimitAlert) {
            Button("OK", role: .cancel) {}
            Button("View Plans") {}  // Can navigate to SubscriptionsView
        } message: {
            Text(limitAlertMessage)
        }
        .onChange(of: latestSubmission) { _, _ in
            isSubmitting = false
            isResubmitting = false
        }
    }

    // MARK: - Prompt Content

    private var promptContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(question.isTask1 ? "Task 1" : "Task 2")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(taskColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .glassEffect(
                            .regular.tint(taskColor.opacity(0.15))
                                .interactive(),
                            in: .rect(cornerRadius: 6)
                        )

                    Text(question.difficulty.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Label("\(question.timeLimit) min", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(question.title)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
            }
            .padding()
            .glassEffect(in: .rect(cornerRadius: 16))

            promptSection
        }
    }

    // MARK: - Prompt Section

    var promptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let situation = question.situation {
                Text(situation)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let task = question.task {
                Text(task)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let topic = question.topic {
                Text(topic)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let instruction = question.instruction {
                Text(instruction)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let requirements = question.requirements, !requirements.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Requirements")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    ForEach(requirements, id: \.self) { req in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(taskColor)
                                .frame(width: 5, height: 5)
                                .padding(.top, 7)
                            Text(req)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if let structure = question.suggestedStructure, !structure.isEmpty {
                Divider()
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(structure, id: \.self) { step in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(taskColor)
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 7)
                                Text(step)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(
                                        horizontal: false,
                                        vertical: true
                                    )
                            }
                        }
                        .padding(.top, 6)
                    }
                } label: {
                    Text("Suggested Structure")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: 16))
    }

    // MARK: - Writing Section

    private var writingSection: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Re-submit info banner
            if isResubmitting {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .foregroundStyle(BrandColor.medium)
                        .font(.subheadline)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("New Attempt")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BrandColor.medium)
                        Text(
                            "You are writing a new attempt. Your previous result is saved in history."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(
                    .regular.tint(BrandColor.muted),
                    in: .rect(cornerRadius: 12)
                )
            }

            // Remaining attempts banner
            usageLimitBanner

            // Beta disclaimer banner
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.subheadline)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Beta feature")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(
                        "In-app writing may have limited experience. For best results, write offline and paste your essay here."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(
                .regular.tint(Color.orange.opacity(0.1)),
                in: .rect(cornerRadius: 12)
            )

            // AI grading info banner
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(BrandColor.primary)  // doi tu .blue
                    .font(.subheadline)

                VStack(alignment: .leading, spacing: 2) {
                    Text("AI-Powered Grading")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BrandColor.primary)  // doi tu .blue

                    Text(
                        "Your essay will be automatically graded by Gemini AI based on VSTEP rubrics. Results typically appear within 10–30 seconds."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(in: .rect(cornerRadius: 16))

            // Word count header
            HStack {
                Text("Your Essay")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(wordCount) / \(minWords) words min")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        wordCount >= minWords ? taskColor : .secondary
                    )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .glassEffect(in: .rect(cornerRadius: 8))
            }

            // TextEditor
            ZStack(alignment: .topLeading) {
                TextEditor(text: $essayText)
                    .frame(minHeight: 220)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                if essayText.isEmpty {
                    Text("Start writing your essay here…")
                        .font(.body)
                        .foregroundStyle(Color(.tertiaryLabel))
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
            }
            .padding(12)
            .glassEffect(in: .rect(cornerRadius: 12))

            // Submit button
            Button {
                let check = AIUsageManager.shared.canGrade(
                    questionId: question.questionId,
                    store: store
                )
                guard check.isAllowed else {
                    limitAlertMessage = check.deniedReason ?? "Limit reached."
                    showLimitAlert = true
                    return
                }
                showSubmitConfirm = true
            } label: {
                Group {
                    if isSubmitting {
                        HStack(spacing: 8) {
                            ProgressView().tint(.primary)
                            Text("Submitting…")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    } else {
                        HStack(spacing: 8) {
                            Image(
                                systemName: isResubmitting
                                    ? "arrow.counterclockwise" : "sparkles"
                            )
                            Text(
                                isResubmitting
                                    ? "Re-submit for AI Grading"
                                    : "Submit for AI Grading"
                            )
                            .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                }
                .glassEffect(
                    .regular.tint(
                        (wordCount < minWords || isSubmitting
                            || !canSubmitToday)
                            ? Color.secondary.opacity(0.1)
                            : BrandColor.primary.opacity(0.15)
                    ).interactive(),
                    in: .rect(cornerRadius: 12)
                )
            }
            .tint(.primary)
            .disabled(wordCount < minWords || isSubmitting || !canSubmitToday)

            if wordCount < minWords {
                Text(
                    "Write at least \(minWords - wordCount) more word\(minWords - wordCount == 1 ? "" : "s") to submit."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: 16))
    }

    // MARK: - Usage Limit Banner

    @ViewBuilder
    private var usageLimitBanner: some View {
        let gradingCheck = AIUsageManager.shared.canGrade(
            questionId: question.questionId,
            store: store
        )
        let submitCheck = AIUsageManager.shared.canSubmit(
            questionId: question.questionId,
            store: store
        )

        if !gradingCheck.isAllowed || !submitCheck.isAllowed {
            // Blocked: show hard limit message
            HStack(spacing: 10) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.subheadline)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily Limit Reached")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                    Text(
                        gradingCheck.deniedReason ?? submitCheck.deniedReason
                            ?? ""
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                NavigationLink {
                    SubscriptionsView()
                } label: {
                    Text("Upgrade")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(BrandColor.primary))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(
                .regular.tint(Color.red.opacity(0.08)),
                in: .rect(cornerRadius: 12)
            )
        } else if remainingGrading <= 1 {
            // Warning: last attempt
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(BrandColor.soft)
                    .font(.subheadline)
                Text(
                    "\(remainingGrading) AI grading attempt\(remainingGrading == 1 ? "" : "s") left for this essay today."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(
                .regular.tint(Color.orange.opacity(0.08)),
                in: .rect(cornerRadius: 12)
            )
        }
    }
}

// MARK: - Submission Review View

private struct SubmissionReviewView: View {

    let question: VSTEPQuestion
    let submission: UserSubmission
    let taskColor: Color

    @State private var criteriaExpanded = true
    @State private var suggestionsExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SubmissionStatusTracker(status: submission.status)
            latestResultCard
            QuestionDetailView(
                question: question,
                questionNumber: 0,
                latestSubmission: nil,
                submissionHistory: [],
                store: StoreKitManager()  // Read-only context, no purchase actions
            ).promptSection
            essaySection
        }
    }

    private var latestResultCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let score = submission.score {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(BrandColor.light)
                    Text("Graded by Gemini AI")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BrandColor.light)
                    Spacer()
                    Text("AI Score")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Divider()

                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(String(format: "%.1f", score))
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(scoreColor(score))
                    Text("/ 10")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(scoreColor(score))
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.systemFill))
                            .frame(height: 6)
                        Capsule()
                            .fill(scoreColor(score))
                            .frame(
                                width: geo.size.width * score / 10,
                                height: 6
                            )
                            .animation(.easeOut(duration: 0.6), value: score)
                    }
                }
                .frame(height: 6)

                Divider()

                let displayComment =
                    submission.overallComment ?? submission.feedback
                if let comment = displayComment, !comment.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Overall Comment", systemImage: "text.bubble")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(comment.markdownAttributed())
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let criteria = submission.criteria, !criteria.isEmpty {
                    Divider()
                    CollapsibleSection(
                        title: "Criteria Breakdown",
                        icon: "list.bullet.clipboard",
                        isExpanded: $criteriaExpanded,
                        count: criteria.count
                    ) {
                        VStack(spacing: 8) {
                            ForEach(criteria, id: \.name) { criterion in
                                CriterionRow(criterion: criterion)
                            }
                        }
                    }
                }

                if let suggestions = submission.suggestions,
                    !suggestions.isEmpty
                {
                    Divider()
                    CollapsibleSection(
                        title: "Suggestions for Improvement",
                        icon: "lightbulb",
                        isExpanded: $suggestionsExpanded,
                        count: suggestions.count
                    ) {
                        VStack(spacing: 8) {
                            ForEach(
                                Array(suggestions.enumerated()),
                                id: \.offset
                            ) {
                                index,
                                suggestion in
                                HStack(alignment: .top, spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(BrandColor.muted)
                                            .frame(width: 24, height: 24)
                                        Text("\(index + 1)")
                                            .font(
                                                .system(size: 12, weight: .bold)
                                            )
                                            .foregroundStyle(BrandColor.primary)
                                    }
                                    Text(suggestion.markdownAttributed())
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .fixedSize(
                                            horizontal: false,
                                            vertical: true
                                        )
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .glassEffect(in: .rect(cornerRadius: 8))
                            }
                        }
                    }
                }

                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(
                        "This score is generated by AI and is for reference only. It may not reflect official VSTEP scoring."
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

            } else {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(BrandColor.light)
                    Text("Gemini AI is reviewing your essay")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BrandColor.light)
                    Spacer()
                }

                Divider()

                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: "clock.fill")
                            .foregroundStyle(.orange)
                            .font(.title3)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Awaiting AI grading")
                            .font(.subheadline.weight(.semibold))
                        Text(
                            "Gemini AI is analyzing your essay against the VSTEP rubric. This typically takes 10–30 seconds."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider()

                Label(
                    "Feedback will appear here once graded",
                    systemImage: "text.bubble"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: 16))
    }

    private var essaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your Submission")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(submission.wordCount) words")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(taskColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .glassEffect(in: .rect(cornerRadius: 8))
            }

            Text(submission.content)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(in: .rect(cornerRadius: 12))
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: 16))
    }

    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 8...: return .green
        case 6..<8: return .orange
        default: return .red
        }
    }
}

// MARK: - Collapsible Section

private struct CollapsibleSection<Content: View>: View {

    let title: String
    let icon: String
    @Binding var isExpanded: Bool
    var count: Int = 0
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if count > 0 {
                        Text("\(count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .glassEffect(in: .capsule)
                    }
                    Image(
                        systemName: isExpanded ? "chevron.up" : "chevron.down"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(
                                with: .move(edge: .top)
                            ),
                            removal: .opacity.combined(with: .move(edge: .top))
                        )
                    )
            }
        }
    }
}

// MARK: - Criterion Row

private struct CriterionRow: View {

    let criterion: SubmissionCriterion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(criterion.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if let band = criterion.band {
                    Text(band)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .glassEffect(in: .capsule)
                }
                if let score = criterion.score {
                    Text(String(format: "%.1f/10", score))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(criterionScoreColor(score))
                }
            }
            if let feedback = criterion.feedback, !feedback.isEmpty {
                Text(feedback.markdownAttributed())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .glassEffect(in: .rect(cornerRadius: 8))
    }

    private func criterionScoreColor(_ score: Double) -> Color {
        switch score {
        case 8...: return .green
        case 6..<8: return .orange
        default: return .red
        }
    }
}

// MARK: - Grading History Sheet

struct GradingHistorySheet: View {

    let history: [UserSubmission]
    @Environment(\.dismiss) private var dismiss

    private var sortedHistory: [UserSubmission] {
        history.sorted { $0.submittedAt > $1.submittedAt }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(BrandColor.light)
                            .font(.subheadline)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI Grading Process")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(BrandColor.light)
                            Text(
                                "All attempts are graded automatically by Gemini AI using VSTEP rubrics. Scores are for reference only."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(
                        .regular.tint(BrandColor.muted),
                        in: .rect(cornerRadius: 16)
                    )

                    ForEach(Array(sortedHistory.enumerated()), id: \.offset) {
                        index,
                        sub in
                        HistoryAttemptCard(
                            submission: sub,
                            attemptNumber: sortedHistory.count - index
                        )
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Grading History")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(BrandColor.primary)
                    }
                }
            }
        }
    }
}

// MARK: - History Attempt Card

private struct HistoryAttemptCard: View {

    let submission: UserSubmission
    let attemptNumber: Int

    @State private var criteriaExpanded = false
    @State private var suggestionsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Attempt #\(attemptNumber)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(BrandColor.light)
                    Text("AI Graded")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BrandColor.light)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .glassEffect(
                    .regular.tint(BrandColor.muted),
                    in: .capsule
                )

                statusBadge
            }

            Divider()

            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("AI Score:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let score = submission.score {
                    Text(String(format: "%.1f / 10", score))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(scoreColor(score))
                } else {
                    Text("Pending AI grading")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("Overall Comment", systemImage: "text.bubble")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let displayComment =
                    submission.overallComment ?? submission.feedback
                if let comment = displayComment, !comment.isEmpty {
                    Text(comment.markdownAttributed())
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(
                        submission.score != nil
                            ? "No comment was provided for this attempt."
                            : "Gemini AI is still processing your essay."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let criteria = submission.criteria, !criteria.isEmpty {
                Divider()
                CollapsibleSection(
                    title: "Criteria Breakdown",
                    icon: "list.bullet.clipboard",
                    isExpanded: $criteriaExpanded,
                    count: criteria.count
                ) {
                    VStack(spacing: 8) {
                        ForEach(criteria, id: \.name) { criterion in
                            CriterionRow(criterion: criterion)
                        }
                    }
                }
            }

            if let suggestions = submission.suggestions, !suggestions.isEmpty {
                Divider()
                CollapsibleSection(
                    title: "Suggestions for Improvement",
                    icon: "lightbulb",
                    isExpanded: $suggestionsExpanded,
                    count: suggestions.count
                ) {
                    VStack(spacing: 8) {
                        ForEach(Array(suggestions.enumerated()), id: \.offset) {
                            index,
                            suggestion in
                            HStack(alignment: .top, spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(BrandColor.muted)
                                        .frame(width: 24, height: 24)
                                    Text("\(index + 1)")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(BrandColor.primary)
                                }
                                Text(suggestion.markdownAttributed())
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .fixedSize(
                                        horizontal: false,
                                        vertical: true
                                    )
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassEffect(in: .rect(cornerRadius: 8))
                        }
                    }
                }
            }

            HStack {
                Label(
                    "\(submission.wordCount) words",
                    systemImage: "text.alignleft"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Text(
                    submission.submittedAt,
                    format: .dateTime.day().month(.abbreviated).year().hour()
                        .minute()
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("AI-generated score. For reference only.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: 14))
    }

    @ViewBuilder
    private var statusBadge: some View {
        Text(submission.status.displayText)
            .font(.caption.weight(.semibold))
            .foregroundStyle(
                submission.score != nil ? BrandColor.light : .orange
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .glassEffect(in: .rect(cornerRadius: 6))
    }

    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 8...: return .green
        case 6..<8: return .orange
        default: return .red
        }
    }
}

// MARK: - Submission Status Tracker

struct SubmissionStatusTracker: View {

    let status: SubmissionStatus

    private var currentStep: Int {
        switch status {
        case .draft: return -1
        case .submitted: return 0
        case .grading: return 1
        case .graded: return 2
        case .failed: return 2
        }
    }

    private var isFailed: Bool { status == .failed }
    private let steps = ["Submitted", "AI Grading", "Done"]

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 0) {
                stepNode(index: 0)
                ShimmerConnector(
                    filled: currentStep > 0,
                    animated: currentStep == 0 && !isFailed
                )
                stepNode(index: 1)
                ShimmerConnector(
                    filled: currentStep > 1,
                    animated: currentStep == 1 && !isFailed
                )
                stepNode(index: 2)
            }

            if status == .grading {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("Gemini AI is analyzing your essay…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .glassEffect()
    }

    private func stepNode(index: Int) -> some View {
        let isActive = index == currentStep
        let isCompleted = index < currentStep

        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(
                        nodeFill(isActive: isActive, isCompleted: isCompleted)
                    )
                    .frame(width: 28, height: 28)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                } else if isActive && isFailed {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                } else if isActive && index == 1 {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                } else if isActive {
                    Circle().fill(.white).frame(width: 9, height: 9)
                }
            }

            Text(steps[index])
                .font(.caption2)
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundStyle(
                    (isActive || isCompleted) ? .primary : Color(.tertiaryLabel)
                )
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func nodeFill(isActive: Bool, isCompleted: Bool) -> Color {
        if isCompleted { return BrandColor.light }
        if isActive && isFailed { return .red }
        if isActive { return BrandColor.primary }
        return Color(.secondarySystemFill)
    }
}

// MARK: - Shimmer Connector

struct ShimmerConnector: View {

    let filled: Bool
    let animated: Bool

    @State private var phase: CGFloat = -0.45

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(filled ? BrandColor.light : Color(.systemFill))
                    .frame(height: 2)

                if animated {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(
                                        color: .white.opacity(0.85),
                                        location: 0.5
                                    ),
                                    .init(color: .clear, location: 1),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * 0.45, height: 2)
                        .offset(x: phase * geo.size.width)
                }
            }
            .frame(height: 2)
            .padding(.top, 13)
            .clipped()
            .onAppear {
                guard animated else { return }
                phase = -0.45
                withAnimation(
                    .linear(duration: 1.0).repeatForever(autoreverses: false)
                ) {
                    phase = 1.0
                }
            }
        }
    }
}

// MARK: - Bullet Label Style

struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            configuration.title
        }
    }
}
