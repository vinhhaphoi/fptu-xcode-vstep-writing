import FirebaseAuth
import SwiftUI

// MARK: - QuestionDetailView
struct QuestionDetailView: View {

    let question: VSTEPQuestion
    var questionNumber: Int = 0
    var latestSubmission: UserSubmission? = nil
    var submissionHistory: [UserSubmission] = []
    let store: StoreKitManager
    var onRefresh: (() async -> Void)? = nil

    @State private var showHistorySheet = false
    @State private var essayText = ""
    @State private var isSubmitting = false
    @State private var isResubmitting = false
    @State private var showLimitAlert = false
    @State private var limitAlertMessage = ""

    // Grading method flow
    @State private var selectedGradingMethod: GradingMethod = .normal
    @State private var showGradingMethodPicker = false
    @State private var showSubmitConfirm = false
    @State private var showSubmitSuccess = false

    private var taskColor: Color {
        question.isTask1 ? BrandColor.light : BrandColor.medium
    }

    private var hasHistory: Bool { !submissionHistory.isEmpty }

    private var wordCount: Int {
        essayText.split(separator: " ").filter { !$0.isEmpty }.count
    }

    private var minWords: Int { question.minWords }

    private var availableGradingMethods: [GradingMethod] {
        let access = AIUsageManager.shared.canAccessAIFeatures()
        if access.allowed {
            return [.quick, .ai, .normal]
        }
        return [.normal]
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
        .toolbar { toolbarContent }
        .sheet(isPresented: $showHistorySheet) {
            GradingHistorySheet(history: submissionHistory)
        }
        .sheet(isPresented: $showGradingMethodPicker) {
            gradingMethodPicker
        }
        .confirmationDialog(
            confirmTitle,
            isPresented: $showSubmitConfirm,
            titleVisibility: .visible
        ) {
            Button("Submit") {
                Task { await submitWithMethod(selectedGradingMethod) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
        .alert("Limit Reached", isPresented: $showLimitAlert) {
            Button("OK", role: .cancel) {}
            NavigationLink("View Plans") { SubscriptionsView() }
        } message: {
            Text(limitAlertMessage)
        }
        .onChange(of: latestSubmission) {
            isSubmitting = false
            isResubmitting = false
        }
        .task {
            // Set default method based on subscription on appear
            selectedGradingMethod = availableGradingMethods.first ?? .normal
        }
        // Immediate success toast overlay
        .overlay(alignment: .top) {
            if showSubmitSuccess {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                        .font(.subheadline)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Essay submitted!")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("We'll notify you when grading is complete.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(BrandColor.primary)
                .clipShape(.rect(cornerRadius: 14))
                .shadow(color: BrandColor.primary.opacity(0.35), radius: 10, y: 4)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation(.easeOut(duration: 0.4)) {
                            showSubmitSuccess = false
                        }
                    }
                }
            }
        }
        .animation(.spring(duration: 0.4), value: showSubmitSuccess)
    }

    // MARK: - Toolbar
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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

            // Dynamic grading info banner — tap to change method
            gradingInfoBanner

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

            ZStack(alignment: .topLeading) {
                TextEditor(text: $essayText)
                    .frame(minHeight: 220)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)

                if essayText.isEmpty {
                    Text("Start writing your essay here...")
                        .font(.body)
                        .foregroundStyle(Color(.tertiaryLabel))
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
            }
            .padding(12)
            .glassEffect(in: .rect(cornerRadius: 12))

            Button {
                guard wordCount >= minWords, !isSubmitting else { return }
                showSubmitConfirm = true
            } label: {
                Group {
                    if isSubmitting {
                        HStack(spacing: 8) {
                            ProgressView().tint(.primary)
                            Text("Submitting...")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    } else {
                        HStack(spacing: 8) {
                            Image(
                                systemName: isResubmitting
                                    ? "arrow.counterclockwise"
                                    : "paperplane.fill"
                            )
                            Text(
                                isResubmitting
                                    ? "Re-submit Essay" : "Submit Essay"
                            )
                            .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                }
                .glassEffect(
                    .regular.tint(
                        wordCount >= minWords && !isSubmitting
                            ? BrandColor.primary.opacity(0.15)
                            : Color.secondary.opacity(0.1)
                    ).interactive(),
                    in: .rect(cornerRadius: 12)
                )
            }
            .tint(.primary)
            .disabled(wordCount < minWords || isSubmitting)

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

    // MARK: - Grading Info Banner
    @ViewBuilder
    private var gradingInfoBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: selectedGradingMethod.icon)
                .foregroundStyle(methodColor(selectedGradingMethod))
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 2) {
                Text(selectedGradingMethod.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(methodColor(selectedGradingMethod))
                Text(selectedGradingMethod.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button {
                showGradingMethodPicker = true
            } label: {
                Text("Change")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BrandColor.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .glassEffect(in: .rect(cornerRadius: 8))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(
            .regular.tint(methodColor(selectedGradingMethod).opacity(0.08)),
            in: .rect(cornerRadius: 16)
        )
    }

    // MARK: - Grading Method Picker Sheet
    private var gradingMethodPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Choose Grading Method")
                    .font(.title3.bold())
                Spacer()
                Button {
                    showGradingMethodPicker = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
            }
            .padding(.horizontal)
            .padding(.top, 20)

            ForEach([GradingMethod.quick, .ai, .normal], id: \.self) { method in
                let isAvailable = availableGradingMethods.contains(method)

                Button {
                    guard isAvailable else { return }
                    selectedGradingMethod = method
                    showGradingMethodPicker = false
                    showSubmitConfirm = true
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(methodColor(method).opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: method.icon)
                                .font(.system(size: 18))
                                .foregroundStyle(
                                    isAvailable
                                        ? methodColor(method)
                                        : Color.secondary.opacity(0.4)
                                )
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(method.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(
                                        isAvailable
                                            ? .primary
                                            : Color.secondary.opacity(0.6)
                                    )

                                if !isAvailable {
                                    Text("Premium")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule().fill(BrandColor.primary)
                                        )
                                }
                            }

                            Text(method.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        if selectedGradingMethod == method {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(BrandColor.primary)
                        }
                    }
                    .padding(14)
                    .glassEffect(
                        .regular.tint(
                            selectedGradingMethod == method && isAvailable
                                ? methodColor(method).opacity(0.08)
                                : Color.clear
                        ),
                        in: .rect(cornerRadius: 16)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!isAvailable)
                .padding(.horizontal)
            }

            Spacer()
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Confirmation Dialog Strings
    private var confirmTitle: String {
        switch selectedGradingMethod {
        case .quick: return "Submit for Quick Grading?"
        case .ai: return "Submit for AI Grading?"
        case .normal: return "Submit to Normal Queue?"
        }
    }

    private var confirmMessage: String {
        switch selectedGradingMethod {
        case .quick:
            return
                "Your essay will be prioritised. A teacher or AI will grade it immediately. This uses 1 Quick Grading quota."
        case .ai:
            return
                "Gemini AI will grade your essay within 30 seconds based on VSTEP rubrics. This uses 1 AI Grading quota."
        case .normal:
            return
                "Your essay will join the queue and be graded when a teacher is available. No quota required."
        }
    }

    // MARK: - Submit with Method
    private func submitWithMethod(_ method: GradingMethod) async {
        isSubmitting = true

        guard let userId = Auth.auth().currentUser?.uid else {
            isSubmitting = false
            return
        }

        var submission = UserSubmission(
            questionId: question.questionId,
            content: essayText,
            wordCount: wordCount,
            submittedAt: Date()
        )
        submission.status = .submitted
        submission.gradingMethod = method
        submission.priority = (method == .quick) ? .high : .normal

        do {
            // Step 1: Save submission + enqueue
            let submissionId = try await FirebaseService.shared.submitEssay(
                submission
            )

            // Step 2: Trigger AI immediately for .ai method only
            if method == .ai {
                let _ = try await AIUsageManager.shared.requestManualGrading(
                    submissionId: submissionId,
                    targetUserId: userId
                )
            }

            // Step 3: Listen for result (AI: waits for Cloud Function; quick/normal: waits for teacher)
            FirebaseService.shared.listenForGradingResult(
                submissionId: submissionId,
                questionId: question.questionId,
                onChange: { _ in
                    Task { await onRefresh?() }
                },
                onTimeout: {
                    limitAlertMessage = "Grading timed out. Please try again."
                    showLimitAlert = true
                }
            )

            await MainActor.run {
                isSubmitting = false
                withAnimation(.spring(duration: 0.4)) {
                    showSubmitSuccess = true
                }
            }
            await onRefresh?()

        } catch let error as AIUsageError {
            await MainActor.run {
                isSubmitting = false
                limitAlertMessage =
                    error.localizedDescription ?? "An error occurred."
                showLimitAlert = true
            }
        } catch {
            await MainActor.run {
                isSubmitting = false
                limitAlertMessage = error.localizedDescription
                showLimitAlert = true
            }
        }
    }

    // MARK: - Helpers
    private func methodColor(_ method: GradingMethod) -> Color {
        switch method {
        case .quick: return BrandColor.primary
        case .ai: return .blue
        case .normal: return .orange
        }
    }
}

// MARK: - Submission Review View
private struct SubmissionReviewView: View {

    let question: VSTEPQuestion
    let submission: UserSubmission
    let taskColor: Color

    @Environment(StoreKitManager.self) private var store
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
                store: store 
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
                    Text(gradedByLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BrandColor.light)
                    Spacer()
                    Text("Score")
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
                            ) { index, suggestion in
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
                // Awaiting grading
                HStack(spacing: 6) {
                    Image(systemName: submission.gradingMethod.icon)
                        .font(.caption)
                        .foregroundStyle(BrandColor.light)
                    Text(awaitingLabel)
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
                        Text(awaitingTitle)
                            .font(.subheadline.weight(.semibold))
                        Text(awaitingSubtitle)
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

    private var gradedByLabel: String {
        // If explicitly graded by an AI fallback/cron job
        if let gradedBy = submission.gradedBy, gradedBy.starts(with: "ai_") {
            return "Graded by Gemini AI (Fallback)"
        }
        
        switch submission.gradingMethod {
        case .ai: 
            return "Graded by Gemini AI"
        case .quick, .normal:
            let graderStr = submission.gradedByName ?? submission.assignedTeacherEmail
            if let grader = graderStr, !grader.isEmpty, grader != "Teacher" {
                return "Graded by \(grader)"
            }
            return submission.gradingMethod == .quick ? "Graded via Quick Grading" : "Graded by Teacher"
        }
    }

    private var awaitingLabel: String {
        switch submission.gradingMethod {
        case .ai: return "Gemini AI is reviewing your essay"
        case .quick: return "In priority queue — grading soon"
        case .normal: return "In queue — awaiting teacher"
        }
    }

    private var awaitingTitle: String {
        switch submission.gradingMethod {
        case .ai: return "Awaiting AI grading"
        case .quick: return "Awaiting quick grading"
        case .normal: return "Awaiting teacher assignment"
        }
    }

    private var awaitingSubtitle: String {
        switch submission.gradingMethod {
        case .ai:
            return
                "Gemini AI is analyzing your essay against the VSTEP rubric. This typically takes 10–30 seconds."
        case .quick:
            return
                "Your essay is in the priority queue. A teacher or AI will grade it shortly."
        case .normal:
            return
                "Your essay is in the queue. It will be graded when a teacher is available."
        }
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

            let displayComment = criterion.comment ?? criterion.feedback
            if let comment = displayComment, !comment.isEmpty {
                Text(comment.markdownAttributed())
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
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(BrandColor.light)
                            .font(.subheadline)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Submission History")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(BrandColor.light)
                            Text(
                                "All attempts are graded based on your chosen method. AI scores are for reference only."
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
                // Show grading method badge
                HStack(spacing: 4) {
                    Image(systemName: submission.gradingMethod.icon)
                        .font(.caption2)
                        .foregroundStyle(BrandColor.light)
                    Text(submission.gradingMethod.displayName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BrandColor.light)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .glassEffect(.regular.tint(BrandColor.muted), in: .capsule)

                statusBadge
            }

            Divider()

            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Score:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let score = submission.score {
                    Text(String(format: "%.1f / 10", score))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(scoreColor(score))
                } else {
                    Text("Pending grading")
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
                            : "Still processing your essay."
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
    private let steps = ["Submitted", "Grading", "Done"]

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
                    Text("Grading in progress...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .glassEffect()
            }
        }
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
        }
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
