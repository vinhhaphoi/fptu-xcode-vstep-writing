import SwiftUI

struct SearchView: View {
    @State private var searchText = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Search results
                ForEach(0..<30) { index in
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading) {
                            Text("Result \(index)")
                                .font(.headline)
                            Text("Search result description")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .searchable(text: $searchText, prompt: "Search...")
    }
}
