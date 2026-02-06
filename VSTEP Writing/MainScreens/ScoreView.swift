import SwiftUI

struct ScoreView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Overall Score
                VStack(spacing: 12) {
                    Text("Overall Score")
                        .font(.headline)
                    
                    Text("7.5")
                        .font(.system(size: 60, weight: .bold))
                        .foregroundColor(.blue)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .padding(.horizontal)
                
                // Score Breakdown
                ForEach(0..<10) { index in
                    ScoreRow(testNumber: index + 1)
                }
                
                Spacer(minLength: 50)
            }
            .padding(.vertical)
        }
    }
}

struct ScoreRow: View {
    let testNumber: Int
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Test \(testNumber)")
                    .font(.headline)
                Text("Completed")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("\(Double.random(in: 6.0...9.0), specifier: "%.1f")")
                .font(.title3.bold())
                .foregroundColor(.green)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}
