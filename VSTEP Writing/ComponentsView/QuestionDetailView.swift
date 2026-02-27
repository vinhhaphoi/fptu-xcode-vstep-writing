// QuestionDetailView.swift
import SwiftUI

// MARK: - QuestionDetailView

struct QuestionDetailView: View {
    let question: VSTEPQuestion
    var questionNumber: Int = 0
    var latestSubmission: UserSubmission? = nil
    var submissionHistory: [UserSubmission] = []
    var onSubmit: ((String) -> Void)? = nil
    var onRefresh: (() async -> Void)? = nil

    @State private var showHistorySheet = false
    @State private var essayText = ""
    @State private var showSubmitConfirm = false
    @State private var isSubmitting = false

    private var taskColor: Color { question.isTask1 ? .blue : .purple }
    private var hasHistory: Bool { !submissionHistory.isEmpty }
    private var wordCount: Int {
        essayText.split(separator: " ").filter { !$0.isEmpty }.count
    }
    //    private var minWords: Int { question.isTask1 ? 150 : 250 }
    private var minWords: Int { 10 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let submission = latestSubmission {
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
        .refreshable {
            await onRefresh?()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Question \(questionNumber)")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            if hasHistory {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showHistorySheet = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
            }
        }
        .sheet(isPresented: $showHistorySheet) {
            GradingHistorySheet(history: submissionHistory)
        }
        .confirmationDialog(
            "Submit your essay?",
            isPresented: $showSubmitConfirm,
            titleVisibility: .visible
        ) {
            Button("Submit") {
                isSubmitting = true
                onSubmit?(essayText)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Once submitted, you cannot edit this attempt. Make sure your essay is complete."
            )
        }
    }

    // MARK: - Prompt Content

    private var promptContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(question.isTask1 ? "Task 1" : "Task 2")
                        .font(.caption.weight(.bold))
                        .foregroundColor(taskColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .glassEffect(in: .rect(cornerRadius: 6))

                    Text(question.difficulty.capitalized)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Label("\(question.timeLimit) min", systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(question.title)
                    .font(.title3.bold())
                    .foregroundColor(.primary)
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
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let task = question.task {
                Text(task)
                    .font(.body.weight(.medium))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let topic = question.topic {
                Text(topic)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let instruction = question.instruction {
                Text(instruction)
                    .font(.body.weight(.medium))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let requirements = question.requirements, !requirements.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Requirements")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    ForEach(requirements, id: \.self) { req in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(taskColor)
                                .frame(width: 5, height: 5)
                                .padding(.top, 7)
                            Text(req)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
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
                                    .foregroundColor(.secondary)
                                    .fixedSize(
                                        horizontal: false,
                                        vertical: true
                                    )
                            }
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Text("Suggested Structure")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassEffect(in: .rect(cornerRadius: 16))
    }

    // MARK: - Writing Input Section

    private var writingSection: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Disclaimer banner
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.subheadline)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Beta feature")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.orange)
                    Text(
                        "In-app writing may have limited experience. For best results, write offline and paste your essay here."
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )

            // Header row
            HStack {
                Text("Your Essay")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(wordCount) / \(minWords) words min")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(
                        wordCount >= minWords ? taskColor : .secondary
                    )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .glassEffect(in: .rect(cornerRadius: 8))
            }

            // TextEditor with placeholder
            ZStack(alignment: .topLeading) {
                TextEditor(text: $essayText)
                    .frame(minHeight: 220)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)

                if essayText.isEmpty {
                    Text("Start writing your essay here…")
                        .font(.body)
                        .foregroundColor(Color(.tertiaryLabel))
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Submit button
            Button {
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
                        Label("Submit Essay", systemImage: "paperplane.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
            }
            .glassEffect()
            .tint(.primary)
            .disabled(wordCount < minWords || isSubmitting)

            // Hint when disabled
            if wordCount < minWords {
                Text(
                    "Write at least \(minWords - wordCount) more word\(minWords - wordCount == 1 ? "" : "s") to submit."
                )
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: 16))
    }
}

// MARK: - Submission Review View

private struct SubmissionReviewView: View {
    let question: VSTEPQuestion
    let submission: UserSubmission
    let taskColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SubmissionStatusTracker(status: submission.status)
            latestResultCard
            QuestionDetailView(
                question: question,
                questionNumber: 0,
                latestSubmission: nil,
                submissionHistory: []
            ).promptSection
            essaySection
        }
    }

    // MARK: Score + Feedback

    private var latestResultCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let score = submission.score {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(String(format: "%.1f", score))
                        .font(.system(size: 44, weight: .bold))
                        .foregroundColor(scoreColor(score))
                    Text("/ 10")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Spacer()
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 30))
                        .foregroundColor(scoreColor(score))
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.systemFill)).frame(height: 6)
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

                if let feedback = submission.feedback, !feedback.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Feedback", systemImage: "text.bubble")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        Text(feedback)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Label("No feedback provided", systemImage: "text.bubble")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Color.orange.opacity(0.15)).frame(
                            width: 44,
                            height: 44
                        )
                        Image(systemName: "clock.fill")
                            .foregroundColor(.orange)
                            .font(.title3)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Awaiting review")
                            .font(.subheadline.weight(.semibold))
                        Text(
                            "Your essay is with our reviewers. Your score will appear here once ready."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider()

                Label("No feedback yet", systemImage: "text.bubble")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: 16))
    }

    // MARK: Essay Section

    private var essaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your Submission")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(submission.wordCount) words")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(taskColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .glassEffect(in: .rect(cornerRadius: 8))
            }
            Text(submission.content)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
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

// MARK: - Grading History Sheet

struct GradingHistorySheet: View {
    let history: [UserSubmission]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Array(history.enumerated()), id: \.offset) {
                        index,
                        sub in
                        HistoryAttemptCard(
                            submission: sub,
                            attemptNumber: index + 1
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
                    }
                    .tint(.red)
                }
            }
        }
    }
}

// MARK: - History Attempt Card

private struct HistoryAttemptCard: View {
    let submission: UserSubmission
    let attemptNumber: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Attempt #\(attemptNumber)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Spacer()
                statusBadge
            }

            Divider()

            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Score:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let score = submission.score {
                    Text(String(format: "%.1f / 10", score))
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(scoreColor(score))
                } else {
                    Text("Not graded yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("Feedback", systemImage: "text.bubble")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let feedback = submission.feedback, !feedback.isEmpty {
                    Text(feedback)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(
                        submission.score != nil
                            ? "No feedback was provided for this attempt."
                            : "Feedback will appear here once your essay has been reviewed."
                    )
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Label(
                    "\(submission.wordCount) words",
                    systemImage: "text.alignleft"
                )
                .font(.caption)
                .foregroundColor(.secondary)
                Spacer()
                Text(
                    submission.submittedAt,
                    format: .dateTime.day().month(.abbreviated).year().hour()
                        .minute()
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: 14))
    }

    @ViewBuilder
    private var statusBadge: some View {
        Text(submission.status.displayText)
            .font(.caption.weight(.semibold))
            .foregroundColor(submission.score != nil ? .green : .orange)
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
    private let steps = ["Submitted", "In Review", "Done"]

    var body: some View {
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
                        .foregroundColor(.white)
                } else if isActive && isFailed {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                } else if isActive {
                    Circle().fill(.white).frame(width: 9, height: 9)
                }
            }

            Text(steps[index])
                .font(.caption2)
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundColor(
                    (isActive || isCompleted) ? .primary : Color(.tertiaryLabel)
                )
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func nodeFill(isActive: Bool, isCompleted: Bool) -> Color {
        if isCompleted { return .blue.opacity(0.7) }
        if isActive && isFailed { return .red }
        if isActive { return .blue }
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
                    .fill(filled ? Color.blue.opacity(0.7) : Color(.systemFill))
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

// MARK: - Bullet Label Style

struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundColor(.secondary)
                .padding(.top, 6)
            configuration.title
        }
    }
}
