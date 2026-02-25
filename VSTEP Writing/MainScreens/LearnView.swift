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
                    // Section label — same horizontal padding as HomeView sections
                    SectionLabel(title: "Task 1", detail: "Letter · 120+ words", color: .blue)
                        .padding(.horizontal)
                        .padding(.top, 16)
                        .padding(.bottom, 8)

                    ForEach(task1Questions, id: \.questionId) { question in
                        QuestionRow(
                            number: extractNumber(from: question.questionId),
                            question: question,
                            latestSubmission: latestSubmissions[question.questionId],
                            submissionHistory: allSubmissions[question.questionId] ?? [],
                            isCompleted: submittedIds.contains(question.questionId)
                        )
                        // Each row manages its own horizontal padding — matches HomeView pattern
                        .padding(.horizontal)
                        .padding(.bottom, 10)
                    }
                }

                if !task2Questions.isEmpty {
                    SectionLabel(title: "Task 2", detail: "Essay · 250+ words", color: .purple)
                        .padding(.horizontal)
                        .padding(.top, 28)
                        .padding(.bottom, 8)

                    ForEach(task2Questions, id: \.questionId) { question in
                        QuestionRow(
                            number: extractNumber(from: question.questionId),
                            question: question,
                            latestSubmission: latestSubmissions[question.questionId],
                            submissionHistory: allSubmissions[question.questionId] ?? [],
                            isCompleted: submittedIds.contains(question.questionId)
                        )
                        .padding(.horizontal)
                        .padding(.bottom, 10)
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

// MARK: - Section Label

private struct SectionLabel: View {
    let title: String
    let detail: String
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.title3.bold())
                .foregroundColor(color)
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}

// MARK: - Question Row

private struct QuestionRow: View {
    let number: Int
    let question: VSTEPQuestion
    let latestSubmission: UserSubmission?
    let submissionHistory: [UserSubmission]
    let isCompleted: Bool

    private var taskColor: Color { question.isTask1 ? .blue : .purple }
    private var metaLine: String {
        "\(question.difficulty.capitalized)  ·  \(question.timeLimit) min  ·  \(question.minWords)+ words"
    }

    var body: some View {
        NavigationLink {
            QuestionDetailView(
                question: question,
                questionNumber: number,
                latestSubmission: isCompleted ? latestSubmission : nil,
                submissionHistory: isCompleted ? submissionHistory : []
            )
        } label: {
            HStack(spacing: 14) {

                // Number badge — standard font, no monospaced design
                ZStack {
                    Text(String(format: "%02d", number))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(isCompleted ? .green : taskColor)
                }
                .frame(width: 40, height: 40)
                .glassEffect(in: .circle)

                // Title + meta
                VStack(alignment: .leading, spacing: 4) {
                    Text(question.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    Text(metaLine)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 8)

                // Trailing accessory
                if let score = latestSubmission?.score {
                    VStack(spacing: 1) {
                        Text(String(format: "%.1f", score))
                            .font(.subheadline.bold())
                            .foregroundColor(scoreColor(score))
                        Text("/ 10")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else if isCompleted {
                    Text("Pending")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.orange)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color(.tertiaryLabel))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .glassEffect(in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 8...:  return .green
        case 6..<8: return .orange
        default:    return .red
        }
    }
}
