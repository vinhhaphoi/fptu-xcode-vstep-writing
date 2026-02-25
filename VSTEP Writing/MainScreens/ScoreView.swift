// ScoreView.swift
import SwiftUI

// MARK: - Question Attempt Group Model
struct QuestionAttemptGroup: Identifiable {
    var id: String { questionId }
    let questionId: String
    let question: VSTEPQuestion?
    let attempts: [UserSubmission]          // sorted desc — newest first

    var latestAttempt: UserSubmission       { attempts[0] }
    var previousAttempts: [UserSubmission]  { Array(attempts.dropFirst()) }
    var attemptCount: Int                   { attempts.count }
    var bestScore: Double?                  { attempts.compactMap(\.score).max() }
}

// MARK: - ScoreView
struct ScoreView: View {
    @StateObject private var firebaseService = FirebaseService.shared
    @State private var submissions: [UserSubmission] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    // ── Grouped & sorted ───────────────────────────────────────
    private var groupedByQuestion: [QuestionAttemptGroup] {
        Dictionary(grouping: submissions) { $0.questionId }
            .map { questionId, attempts in
                QuestionAttemptGroup(
                    questionId: questionId,
                    question: firebaseService.questionMap[questionId],
                    attempts: attempts.sorted {
                        $0.submittedAt > $1.submittedAt   // newest first
                    }
                )
            }
            // Group có submission mới nhất lên đầu
            .sorted { $0.latestAttempt.submittedAt > $1.latestAttempt.submittedAt }
    }

    // ── Stats ──────────────────────────────────────────────────
    private var gradedSubmissions: [UserSubmission] {
        submissions.filter { $0.score != nil }
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

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

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
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("All Submissions")
                                .font(.title2.bold())
                            Spacer()
                            Text("\(groupedByQuestion.count) questions")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)

                        ForEach(groupedByQuestion) { group in
                            QuestionAttemptCard(group: group)
                        }
                    }
                }

                Spacer(minLength: 50)
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Score")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await loadSubmissions() }
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
            print("[ScoreView] error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Question Attempt Card
struct QuestionAttemptCard: View {
    let group: QuestionAttemptGroup
    @State private var isExpanded = false

    private var taskColor: Color {
        group.question?.taskType == "task1" ? .blue : .purple
    }

    private var taskBadgeText: String {
        switch group.question?.taskType {
        case "task1": return "Task 1"
        case "task2": return "Task 2"
        default:      return "Essay"
        }
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Latest Attempt Row (luôn hiển thị) ─────────────
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(taskColor)
                    .frame(width: 4, height: 68)

                VStack(alignment: .leading, spacing: 6) {
                    Text(group.question?.title
                         ?? group.questionId.uppercased())
                        .font(.headline)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        // Task badge
                        BadgeLabel(text: taskBadgeText, color: taskColor)

                        // Attempt count — chỉ hiện nếu > 1
                        if group.attemptCount > 1 {
                            BadgeLabel(
                                text: "\(group.attemptCount) attempts",
                                color: .secondary
                            )
                        }

                        // Date của lần mới nhất
                        Text(group.latestAttempt.submittedAt, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                AttemptScoreView(submission: group.latestAttempt)

                // Chevron expand — chỉ khi có lần thử trước
                if !group.previousAttempts.isEmpty {
                    Image(systemName: isExpanded
                          ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !group.previousAttempts.isEmpty else { return }
                withAnimation(.easeInOut(duration: 0.22)) {
                    isExpanded.toggle()
                }
            }

            // ── Previous Attempts (expandable stack) ───────────
            if isExpanded {
                Divider().padding(.horizontal, 16)

                ForEach(
                    Array(group.previousAttempts.enumerated()),
                    id: \.element.id
                ) { index, attempt in
                    PreviousAttemptRow(
                        attemptNumber: group.attemptCount - 1 - index,
                        submission: attempt
                    )

                    if index < group.previousAttempts.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
        .padding(.horizontal)
    }
}

// MARK: - Previous Attempt Row (compact)
struct PreviousAttemptRow: View {
    let attemptNumber: Int
    let submission: UserSubmission

    var body: some View {
        HStack(spacing: 12) {
            Text("#\(attemptNumber)")
                .font(.caption.weight(.bold))
                .foregroundColor(.secondary)
                .frame(width: 32, alignment: .center)

            Text(submission.submittedAt, style: .date)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            AttemptScoreView(submission: submission, compact: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Attempt Score View
struct AttemptScoreView: View {
    let submission: UserSubmission
    var compact: Bool = false

    private var scoreColor: Color {
        guard let score = submission.score else { return .secondary }
        switch score {
        case 8...:  return .green
        case 6..<8: return .orange
        default:    return .red
        }
    }

    private var statusColor: Color {
        switch submission.status {
        case .submitted: return .blue
        case .grading:   return .orange
        case .graded:    return .green
        case .failed:    return .red
        case .draft:     return .secondary
        }
    }

    var body: some View {
        if let score = submission.score {
            VStack(spacing: 1) {
                Text(String(format: "%.1f", score))
                    .font(compact
                          ? .subheadline.bold().monospacedDigit()
                          : .title3.bold().monospacedDigit())
                    .foregroundColor(scoreColor)
                Text("/ 10")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        } else {
            VStack(spacing: 3) {
                Image(systemName: submission.status.icon)
                    .font(compact ? .caption : .subheadline)
                    .foregroundColor(statusColor)
                Text(submission.status.displayText)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(statusColor)
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
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .cornerRadius(5)
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
        case 8...:  return .green
        case 6..<8: return .orange
        default:    return .red
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Overall Score")
                .font(.headline)
                .foregroundColor(.secondary)

            if let score = averageScore {
                Text(String(format: "%.1f", score))
                    .font(.system(size: 60, weight: .bold))
                    .foregroundColor(scoreColor)
                    .contentTransition(.numericText())
            } else {
                Text("—")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundColor(.secondary)
            }

            if totalSubmissions > 0 {
                HStack(spacing: 28) {
                    StatChip(icon: "doc.text.fill",
                             value: "\(totalSubmissions)", label: "Total")
                    StatChip(icon: "1.circle.fill",
                             value: "\(task1Count)", label: "Task 1",
                             color: .blue)
                    StatChip(icon: "2.circle.fill",
                             value: "\(task2Count)", label: "Task 2",
                             color: .purple)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
        .padding(.horizontal)
    }
}

// MARK: - Stat Chip
struct StatChip: View {
    let icon: String
    let value: String
    let label: String
    var color: Color = .primary

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.subheadline)
            Text(value)
                .font(.title3.bold())
                .foregroundColor(.primary)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Empty State
struct ScoreEmptyView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No submissions yet")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Complete your first essay\nto see your score here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}
