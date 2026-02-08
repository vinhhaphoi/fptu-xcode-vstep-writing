// ScoreView.swift - SIMPLE VERSION WITH FIREBASE
import SwiftUI

struct ScoreView: View {
    @StateObject private var firebaseService = FirebaseService.shared
    @State private var submissions: [UserSubmission] = []
    @State private var isLoading = false
    
    var averageScore: Double {
        let gradedSubmissions = submissions.filter { $0.score != nil }
        guard !gradedSubmissions.isEmpty else { return 7.5 } // Default placeholder
        let total = gradedSubmissions.reduce(0.0) { $0 + ($1.score ?? 0) }
        return total / Double(gradedSubmissions.count)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Overall Score (Giống gốc 100%)
                VStack(spacing: 12) {
                    Text("Overall Score")
                        .font(.headline)
                    
                    // ✅ Hiển thị average score từ Firebase
                    Text(String(format: "%.1f", averageScore))
                        .font(.system(size: 60, weight: .bold))
                        .foregroundColor(.blue)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .padding(.horizontal)
                
                // Score Breakdown (Giống gốc 100%)
                if isLoading {
                    ProgressView()
                        .padding()
                } else if !submissions.isEmpty {
                    // ✅ Hiển thị submissions thật từ Firebase
                    ForEach(Array(submissions.enumerated()), id: \.offset) { index, submission in
                        ScoreRow(
                            testNumber: index + 1,
                            questionId: submission.questionId,
                            score: submission.score
                        )
                    }
                } else {
                    // ✅ Placeholder khi chưa có data (giống gốc)
                    ForEach(0..<10) { index in
                        ScoreRow(testNumber: index + 1)
                    }
                }
                
                Spacer(minLength: 50)
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Score")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await loadSubmissions()
        }
        .task {
            await loadSubmissions()
        }
    }
    
    private func loadSubmissions() async {
        guard firebaseService.currentUserId != nil else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            submissions = try await firebaseService.fetchUserSubmissions()
        } catch {
            print("Error loading submissions: \(error)")
        }
    }
}

// MARK: - Score Row (Giống gốc 100%)
struct ScoreRow: View {
    let testNumber: Int
    var questionId: String?
    var score: Double?
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                // ✅ Hiển thị questionId nếu có, không thì "Test X"
                if let questionId = questionId {
                    Text(questionId.uppercased())
                        .font(.headline)
                } else {
                    Text("Test \(testNumber)")
                        .font(.headline)
                }
                
                Text("Completed")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // ✅ Hiển thị score thật nếu có, không thì random (giống gốc)
            if let score = score {
                Text(String(format: "%.1f", score))
                    .font(.title3.bold())
                    .foregroundColor(.green)
            } else {
                Text(String(format: "%.1f", Double.random(in: 6.0...9.0)))
                    .font(.title3.bold())
                    .foregroundColor(.green)
            }
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
