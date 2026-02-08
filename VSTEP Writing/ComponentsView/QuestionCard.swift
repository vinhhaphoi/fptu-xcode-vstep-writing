// QuestionCard.swift
import SwiftUI

struct QuestionCard: View {
    let question: VSTEPQuestion
    var isCompleted: Bool = false
    
    var body: some View {
        NavigationLink(destination: QuestionDetailView(question: question)) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            (question.isTask1 ? Color.blue : Color.purple).opacity(0.1)
                        )
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: question.isTask1 ? "envelope.fill" : "doc.text.fill")
                        .font(.title2)
                        .foregroundStyle(question.isTask1 ? .blue : .purple)
                    
                    if isCompleted {
                        Circle()
                            .fill(.green)
                            .frame(width: 20, height: 20)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                            )
                            .offset(x: 20, y: -20)
                    }
                }
                
                // Content
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(question.questionId.uppercased())
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        
                        DifficultyBadge(level: question.difficulty)
                        
                        Spacer()
                    }
                    
                    Text(question.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    HStack(spacing: 12) {
                        Label(
                            question.category.replacingOccurrences(of: "_", with: " ").capitalized,
                            systemImage: "tag"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        
                        Label("\(question.minWords)+ words", systemImage: "text.word.spacing")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Difficulty Badge
struct DifficultyBadge: View {
    let level: String
    
    var color: Color {
        switch level.lowercased() {
        case "beginner", "easy":
            return .green
        case "intermediate", "medium":
            return .orange
        case "advanced", "hard":
            return .red
        default:
            return .gray
        }
    }
    
    var body: some View {
        Text(level.capitalized)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
