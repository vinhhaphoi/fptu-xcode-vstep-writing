import SwiftUI

struct LearnView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ForEach(0..<20) { index in
                    LessonCard(lessonNumber: index + 1)
                }
                Spacer(minLength: 50)
            }
            .padding(.vertical)
        }
    }
}

struct LessonCard: View {
    let lessonNumber: Int
    
    var body: some View {
        NavigationLink {
            Text("Lesson \(lessonNumber) Content")
                .navigationTitle("Lesson \(lessonNumber)")
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Lesson \(lessonNumber)")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("Duration: 30 minutes")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }
}
