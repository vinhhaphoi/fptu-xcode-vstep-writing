// LearnView.swift - UPDATED WITH ICON
import SwiftUI

struct LearnView: View {
    @StateObject private var firebaseService = FirebaseService.shared
    @State private var showError = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if firebaseService.isLoading {
                    ProgressView("Loading...")
                        .padding()
                } else if firebaseService.questions.isEmpty {
                    VStack(spacing: 12) {
                        Text("No questions available")
                            .foregroundStyle(.secondary)
                        
                        Button("Tap to reload") {
                            Task { await loadQuestions() }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                } else {
                    ForEach(Array(firebaseService.questions.enumerated()), id: \.offset) { index, question in
                        LessonCard(lessonNumber: index + 1, question: question)
                    }
                }
                
                Spacer(minLength: 50)
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Learn")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await loadQuestions()
        }
        .task {
            await loadQuestions()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(firebaseService.errorMessage ?? "Unknown error")
        }
    }
    
    private func loadQuestions() async {
        do {
            try await firebaseService.fetchQuestions()
        } catch {
            firebaseService.errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Lesson Card WITH ICON ✅
struct LessonCard: View {
    let lessonNumber: Int
    let question: VSTEPQuestion
    
    var body: some View {
        NavigationLink {
            QuestionDetailView(question: question)
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "text.document")
                    .font(.title3)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(question.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("Duration: \(question.timeLimit) minutes")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
            .padding(.horizontal)
        }
    }
}
