// LearnView.swift
import SwiftUI

// MARK: - LearnView
struct LearnView: View {
    @StateObject private var firebaseService = FirebaseService.shared
    @State private var submittedIds: Set<String> = []
    @State private var latestSubmissions: [String: UserSubmission] = [:]
    @State private var showError = false
    @State private var errorMsg = ""

    private var task1Questions: [VSTEPQuestion] {
        firebaseService.questions.filter { $0.isTask1 }
    }
    private var task2Questions: [VSTEPQuestion] {
        firebaseService.questions.filter { $0.isTask2 }
    }

    var body: some View {
        Group {
            // ── Loading: FULL SCREEN — không bị nền xám cắt ──────
            if firebaseService.isLoading && firebaseService.questions.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.3)
                    Text("Loading questions…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))

            // ── Empty ─────────────────────────────────────────────
            } else if firebaseService.questions.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No questions available")
                        .foregroundStyle(.secondary)
                    Button("Reload") { Task { await loadData() } }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // ── Content ───────────────────────────────────────────
            } else {
                ScrollView {
                    VStack(spacing: 0) {

                        // Task 1 Section
                        if !task1Questions.isEmpty {
                            TaskSectionHeader(
                                title: "Task 1",
                                subtitle: "Letter / Correspondence · 120+ words · 20 min",
                                color: .blue,
                                count: task1Questions.count
                            )
                            .padding(.top, 8)

                            ForEach(task1Questions, id: \.questionId) { question in
                                LessonCard(
                                    questionNumber: extractNumber(from: question.questionId),
                                    question: question,
                                    latestSubmission: latestSubmissions[question.questionId],
                                    isCompleted: submittedIds.contains(question.questionId)
                                )
                                .padding(.top, 10)
                            }
                        }

                        // Task 2 Section
                        if !task2Questions.isEmpty {
                            TaskSectionHeader(
                                title: "Task 2",
                                subtitle: "Essay / Argument · 250+ words · 40 min",
                                color: .purple,
                                count: task2Questions.count
                            )
                            .padding(.top, 24)

                            ForEach(task2Questions, id: \.questionId) { question in
                                LessonCard(
                                    questionNumber: extractNumber(from: question.questionId),
                                    question: question,
                                    latestSubmission: latestSubmissions[question.questionId],
                                    isCompleted: submittedIds.contains(question.questionId)
                                )
                                .padding(.top, 10)
                            }
                        }

                        Spacer(minLength: 50)
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
                .background(Color(.systemGroupedBackground))
            }
        }
        .navigationTitle("Learn")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await loadData() }
        .task { await loadData() }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMsg)
        }
    }

    /// "Q002" → 2, "Q015" → 15, fallback 0
    private func extractNumber(from questionId: String) -> Int {
        Int(questionId.filter(\.isNumber)) ?? 0
    }

    private func loadData() async {
        do {
            try await firebaseService.fetchQuestions()

            guard firebaseService.currentUserId != nil else { return }
            try? await firebaseService.fetchUserProgress()
            submittedIds = Set(firebaseService.userProgress?.completedQuestions ?? [])

            // Build questionId → latest submission map
            if let allSubs = try? await firebaseService.fetchUserSubmissions() {
                var map: [String: UserSubmission] = [:]
                // fetchUserSubmissions() returns desc → first = newest
                for sub in allSubs where map[sub.questionId] == nil {
                    map[sub.questionId] = sub
                }
                latestSubmissions = map
            }
        } catch {
            errorMsg = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Task Section Header
struct TaskSectionHeader: View {
    let title: String
    let subtitle: String
    let color: Color
    let count: Int

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Color accent bar
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 4, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.title2.bold())
                        .foregroundColor(color)

                    Text("\(count) questions")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(color.opacity(0.12))
                        .cornerRadius(8)
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Lesson Card (Conditional navigation)
struct LessonCard: View {
    let questionNumber: Int
    let question: VSTEPQuestion
    let latestSubmission: UserSubmission?
    let isCompleted: Bool

    private var taskColor: Color { question.isTask1 ? .blue : .purple }

    var body: some View {
        NavigationLink {
            // Điều hướng có điều kiện: submitted → view-only, chưa submit → write [web:122]
            if isCompleted, let submission = latestSubmission {
                SubmissionReviewView(
                    question: question,
                    questionNumber: questionNumber,
                    submission: submission
                )
            } else {
                QuestionDetailView(
                    question: question,
                    questionNumber: questionNumber
                )
            }
        } label: {
            cardLabel
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var cardLabel: some View {
        HStack(spacing: 14) {
            // Icon box
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isCompleted
                          ? Color.green.opacity(0.12)
                          : taskColor.opacity(0.10))
                    .frame(width: 48, height: 48)

                Image(systemName: isCompleted
                      ? "checkmark.circle.fill"
                      : "text.document.fill")
                    .font(.title3)
                    .foregroundColor(isCompleted ? .green : taskColor)
            }

            // Info
            VStack(alignment: .leading, spacing: 5) {
                // "Question 2" bằng số thực, không phải "Q002"
                HStack(spacing: 6) {
                    Text("Question \(questionNumber)")
                        .font(.caption.weight(.bold))
                        .foregroundColor(taskColor)

                    Text(question.difficulty.capitalized)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color(.systemFill))
                        .cornerRadius(4)
                }

                Text(question.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)

                HStack(spacing: 12) {
                    Label("\(question.timeLimit) min", systemImage: "clock")
                    Label("\(question.minWords)+ words", systemImage: "text.alignleft")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer(minLength: 4)

            // Right side: score / status / chevron
            rightAccessory
        }
        .padding()
        .background(Color(.systemBackground))
        .glassEffect()
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isCompleted ? Color.green.opacity(0.35) : Color.gray.opacity(0.15),
                    lineWidth: 1.2
                )
        )
    }

    @ViewBuilder
    private var rightAccessory: some View {
        if let score = latestSubmission?.score {
            // Đã chấm điểm
            VStack(spacing: 1) {
                Text(String(format: "%.1f", score))
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundColor(scoreColor(score))
                Text("/ 10")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        } else if isCompleted {
            // Submitted, chờ chấm
            VStack(spacing: 3) {
                Image(systemName: "clock.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text("Pending")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.orange)
            }
        } else {
            // Chưa làm
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
        }
    }

    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 8...:  return .green
        case 6..<8: return .orange
        default:    return .red
        }
    }
}

// MARK: - Submission Review View (view-only)
struct SubmissionReviewView: View {
    let question: VSTEPQuestion
    let questionNumber: Int
    let submission: UserSubmission
    @State private var navigateToNewAttempt = false

    private var taskColor: Color { question.isTask1 ? .blue : .purple }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // ── Score card ───────────────────────────────────
                if let score = submission.score {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your Score")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(String(format: "%.1f / 10", score))
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(scoreColor(score))
                        }
                        Spacer()
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 40))
                            .foregroundColor(scoreColor(score))
                    }
                    .padding()
                    .background(scoreColor(score).opacity(0.08))
                    .glassEffect()

                    if let feedback = submission.feedback, !feedback.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Feedback")
                                .font(.headline)
                            Text(feedback)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemBackground))
                        .glassEffect()
                    }
                } else {
                    // Chờ chấm
                    HStack(spacing: 12) {
                        Image(systemName: submission.status.icon)
                            .foregroundColor(.orange)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(submission.status.displayText)
                                .font(.headline)
                            Text("Your essay is being reviewed")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08))
                    .glassEffect()
                }

                // ── Question prompt (read-only) ──────────────────
                VStack(alignment: .leading, spacing: 12) {
                    Text(question.situation ?? "")
                        .font(.body)
                        .foregroundColor(.secondary)

                    if let requirements = question.requirements,
                       !requirements.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Requirements:")
                                .font(.headline)
                            ForEach(requirements, id: \.self) { req in
                                Label(req, systemImage: "circle.fill")
                                    .font(.subheadline)
                                    .labelStyle(BulletLabelStyle())
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .glassEffect()

                // ── Submitted essay (read-only) ──────────────────
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Your Submission")
                            .font(.headline)
                        Spacer()
                        Text("\(submission.wordCount) words")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(taskColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(taskColor.opacity(0.10))
                            .cornerRadius(8)
                    }

                    Text(submission.content)
                        .font(.body)
                        .foregroundColor(.primary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                }

                // ── Try Again button ─────────────────────────────
                Button {
                    navigateToNewAttempt = true
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(taskColor)
                        .foregroundColor(.white)
                        .glassEffect()
                }

                Spacer(minLength: 40)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Question \(questionNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToNewAttempt) {
            QuestionDetailView(question: question, questionNumber: questionNumber)
        }
    }

    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 8...:  return .green
        case 6..<8: return .orange
        default:    return .red
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
