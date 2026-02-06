import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) var dismiss
    
    let policyContent = """
Last Updated: 6 Feb, 2026
1. Introduction
Welcome to the VSTEP Writing Learning Website ("we," "our," or "us"). This project is developed by Vinhhaphoi from NTHT x Vinhhaphoi. We are committed to protecting your personal information and your right to privacy. This policy explains how we collect, use, and safeguard your data when you use our platform for VSTEP writing practice.
2. Information We Collect
We collect minimal data necessary to provide the "Immediate Feedback" and "Progress Tracking" solutions defined in our project scope:
• Personal Information: When you register, we collect your email address, full name, and profile picture to manage your account and identify you as a "Learner" or "Admin".
• User-Generated Content (Essays): We collect the text of the essays (Task 1 letters and Task 2 essays) you submit for grading.
• Usage Data: We track your exam history, scores, and time spent on tests to generate your progress dashboard.
3. How We Use Your Information
• To Provide Services: We use your essay submissions to generate scores and feedback.
• AI Processing: Your essay text is sent to the OpenAI API (a third-party service) solely for the purpose of analyzing grammar, vocabulary, organization, and task fulfillment. We do not use your data to train public AI models.
• To Track Progress: We store your past results in cloud to visualize your improvement over time (B1, B2, C1 progression).
4. Third-Party Service Providers
We utilize the following third-party services to operate the system. By using our application, you acknowledge that your data may be processed by:
• Google Firebase: Used for secure authentication, real-time database (for auto-save functionality), and hosting.
• Cloudflare: Used for DNS management, CDN, and DDoS protection to ensure site security and speed.
• OpenAI: Used as the core engine for Automated Essay Scoring (AES).
5. Data Retention
• Essays: We retain your submitted essays and feedback history as long as your account is active to support your learning journey.
• Guest Data: Data generated during "Guest" (Demo) sessions is not permanently stored 
6. Security
We implement standard security measures provided by Google Firebase and Cloudflare (SSL encryption) to protect your data. However, please remember that no transmission over the internet is 100% secure.
7. Contact Us
If you have questions about this policy, please contact the development team at: vinhhaphoi.work@gmail.com
"""
    
    var body: some View {
        NavigationStack {
            ScrollView {
                Text(policyContent)
                    .padding()
                    .font(.body)
                    .textSelection(.enabled)
            }
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}
