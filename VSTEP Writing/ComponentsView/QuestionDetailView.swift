// QuestionDetailView.swift - SIMPLE VERSION
import SwiftUI

struct QuestionDetailView: View {
    let question: VSTEPQuestion
    @StateObject private var firebaseService = FirebaseService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var userAnswer = ""
    @State private var isSubmitting = false
    @State private var showSuccess = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var wordCount: Int {
        userAnswer.split(separator: " ").count
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Question Title
                Text(question.title)
                    .font(.title2.bold())
                
                // Question Content
                if let situation = question.situation {
                    Text(situation)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                
                if let topic = question.topic {
                    Text(topic)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                
                // Requirements
                if let requirements = question.requirements {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Requirements:")
                            .font(.headline)
                        
                        ForEach(requirements, id: \.self) { req in
                            Text("• \(req)")
                                .font(.body)
                        }
                    }
                }
                
                // Word Count
                HStack {
                    Text("Your Answer")
                        .font(.headline)
                    Spacer()
                    Text("\(wordCount) / \(question.minWords)+ words")
                        .font(.caption)
                        .foregroundStyle(wordCount >= question.minWords ? .green : .orange)
                }
                .padding(.top)
                
                // Answer Input
                TextEditor(text: $userAnswer)
                    .frame(minHeight: 300)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                
                // Submit Button
                Button {
                    Task { await submitAnswer() }
                } label: {
                    HStack {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Submit Answer")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(userAnswer.isEmpty ? Color.gray : Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                }
                .disabled(userAnswer.isEmpty || isSubmitting)
            }
            .padding()
        }
        .navigationTitle(question.questionId.uppercased())
        .navigationBarTitleDisplayMode(.inline)
        .alert("Success!", isPresented: $showSuccess) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Your answer has been submitted successfully!")
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private func submitAnswer() async {
        guard firebaseService.currentUserId != nil else {
            errorMessage = "Please log in to submit your answer"
            showError = true
            return
        }
        
        isSubmitting = true
        defer { isSubmitting = false }
        
        do {
            try await firebaseService.submitAnswer(
                questionId: question.questionId,
                content: userAnswer,
                wordCount: wordCount
            )
            
            showSuccess = true
            
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
