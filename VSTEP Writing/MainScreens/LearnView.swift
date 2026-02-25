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

    private var task1Questions: [VSTEPQuestion] {
        firebaseService.questions.filter { $0.isTask1 }
    }
    private var task2Questions: [VSTEPQuestion] {
        firebaseService.questions.filter { $0.isTask2 }
    }

    var body: some View {
        Group {
            if firebaseService.isLoading && firebaseService.questions.isEmpty {
                loadingView
            } else if firebaseService.questions.isEmpty {
                emptyView
            } else {
                questionList
            }
        }
        .navigationTitle("Learn")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await loadData() }
        .task { await loadData() }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: { Text(errorMsg) }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().scaleEffect(1.2)
            Text("Loading questions…")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("No questions available")
                .foregroundStyle(.secondary)
            Button("Reload") { Task { await loadData() } }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Question List

    private var questionList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                if !task1Questions.isEmpty {
                    TaskHeader(title: "Task 1", count: task1Questions.count, color: .blue)
                        .padding(.horizontal)
                        .padding(.top, 20)
                        .padding(.bottom, 12)

                    ForEach(task1Questions, id: \.questionId) { question in
                        QuestionRow(
                            number: extractNumber(from: question.questionId),
                            question: question,
                            latestSubmission: latestSubmissions[question.questionId],
                            submissionHistory: allSubmissions[question.questionId] ?? [],
                            isCompleted: submittedIds.contains(question.questionId)
                        )
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                }

                if !task2Questions.isEmpty {
                    TaskHeader(title: "Task 2", count: task2Questions.count, color: .purple)
                        .padding(.horizontal)
                        .padding(.top, 32)
                        .padding(.bottom, 12)

                    ForEach(task2Questions, id: \.questionId) { question in
                        QuestionRow(
                            number: extractNumber(from: question.questionId),
                            question: question,
                            latestSubmission: latestSubmissions[question.questionId],
                            submissionHistory: allSubmissions[question.questionId] ?? [],
                            isCompleted: submittedIds.contains(question.questionId)
                        )
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                }

                Spacer(minLength: 60)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Helpers

    private func extractNumber(from questionId: String) -> Int {
        Int(questionId.filter(\.isNumber)) ?? 0
    }

    private func loadData() async {
        do {
            try await firebaseService.fetchQuestions()
            guard firebaseService.currentUserId != nil else { return }
            try? await firebaseService.fetchUserProgress()
            submittedIds = Set(firebaseService.userProgress?.completedQuestions ?? [])

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
                allSubmissions    = allMap
            }
        } catch {
            errorMsg = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Task Header
// Section title with count — no subtitle noise

private struct TaskHeader: View {
    let title: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(.title2.bold())
                .foregroundColor(color)

            Text("\(count)")
                .font(.caption.weight(.bold))
                .foregroundColor(color)
                .frame(width: 22, height: 22)
                .background(color.opacity(0.12))
                .clipShape(Circle())
        }
    }
}

// MARK: - Question Row
// Clean: number · title · difficulty only. No time, no word count.

private struct QuestionRow: View {
    let number: Int
    let question: VSTEPQuestion
    let latestSubmission: UserSubmission?
    let submissionHistory: [UserSubmission]
    let isCompleted: Bool

    private var taskColor: Color { question.isTask1 ? .blue : .purple }

    var body: some View {
        NavigationLink {
            QuestionDetailView(
                question: question,
                questionNumber: number,
                latestSubmission: isCompleted ? latestSubmission : nil,
                submissionHistory: isCompleted ? submissionHistory : []
            )
        } label: {
            rowLabel
        }
        .buttonStyle(.plain)
    }

    private var rowLabel: some View {
        HStack(spacing: 16) {

            // Row number — plain text, no border/circle
            Text(String(format: "%02d", number))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isCompleted ? .green : Color(.tertiaryLabel))
                .frame(width: 24)

            // Title + difficulty
            VStack(alignment: .leading, spacing: 4) {
                Text(question.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(question.difficulty.capitalized)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 8)

            // Trailing: score, pending dot, or chevron
            trailingView
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var trailingView: some View {
        if let score = latestSubmission?.score {
            // Graded: show numeric score
            VStack(spacing: 1) {
                Text(String(format: "%.1f", score))
                    .font(.subheadline.bold())
                    .foregroundColor(scoreColor(score))
                Text("/ 10")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        } else if isCompleted {
            // Submitted but not graded
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
                Text("Pending")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        } else {
            // Not started
            Image(systemName: "chevron.right")
                .font(.caption.weight(.medium))
                .foregroundColor(Color(.tertiaryLabel))
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
