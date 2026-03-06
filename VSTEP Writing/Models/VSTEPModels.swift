import FirebaseFirestore
import Foundation
import SwiftUI

// MARK: - Task Model
struct VSTEPTask: Identifiable, Codable {
    @DocumentID var id: String?
    let taskId: String
    let name: String
    let description: String
    let minWords: Int
    let timeLimit: Int
    let taskType: String

    // @DocumentID tự xử lý — không đưa vào CodingKeys [web:9]
    enum CodingKeys: String, CodingKey {
        case taskId, name, description, minWords, timeLimit, taskType
    }
}

// MARK: - Question Model
struct VSTEPQuestion: Identifiable, Codable {
    @DocumentID var id: String?
    let questionId: String  // non-optional: luôn có trong Firestore doc
    let taskType: String
    let category: String
    let title: String
    let situation: String?
    let task: String?
    let topic: String?
    let instruction: String?
    let requirements: [String]?
    let formalityLevel: String?
    let essayType: String?
    let difficulty: String
    var tags: [String]  // var: tránh crash nếu field vắng trong Firestore
    let suggestedStructure: [String]?

    // MARK: Computed
    var isTask1: Bool { taskType == "task1" }
    var isTask2: Bool { taskType == "task2" }
    var minWords: Int { isTask1 ? 120 : 250 }
    var timeLimit: Int { isTask1 ? 20 : 40 }

    enum CodingKeys: String, CodingKey {
        case questionId, taskType, category, title, situation
        case task
        case topic, instruction, requirements, formalityLevel, essayType
        case difficulty, tags, suggestedStructure
    }
}

// MARK: - Rubric Model
struct VSTEPRubric: Identifiable, Codable {
    @DocumentID var id: String?
    let name: String
    let totalCriteria: Int
    let criteria: [String: RubricCriterion]

    enum CodingKeys: String, CodingKey {
        case name, totalCriteria, criteria
    }
}

struct RubricCriterion: Codable {
    let name: String
    let weight: Double
    let levels: [String: RubricLevel]
}

struct RubricLevel: Codable {
    let score: Int
    let descriptor: String
}

// MARK: - Submission Status (top-level — FirebaseService cần dùng trực tiếp)
enum SubmissionStatus: String, Codable {
    case draft = "draft"
    case submitted = "submitted"
    case grading = "grading"
    case graded = "graded"
    case failed = "failed"

    var displayText: String {
        switch self {
        case .draft: return "Draft"
        case .submitted: return "Submitted"
        case .grading: return "Grading…"
        case .graded: return "Graded"
        case .failed: return "Failed"
        }
    }

    var icon: String {
        switch self {
        case .draft: return "doc"
        case .submitted: return "paperplane.fill"
        case .grading: return "clock.fill"
        case .graded: return "checkmark.seal.fill"
        case .failed: return "xmark.circle.fill"
        }
    }
}

// MARK: - User Submission
struct UserSubmission: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var questionId: String
    let content: String
    let wordCount: Int
    var submittedAt: Date
    var score: Double?
    var feedback: String?
    var overallComment: String?
    var suggestions: [String]?
    var criteria: [SubmissionCriterion]?
    var status: SubmissionStatus
    var essayText: String? = nil

    enum CodingKeys: String, CodingKey {
           case questionId
           case content
           case wordCount
           case submittedAt
           case score
           case feedback
           case overallComment 
           case suggestions
           case criteria
           case status
           case essayText
       }
}
struct SubmissionCriterion: Codable, Hashable {
    let name: String
    let score: Double?
    let band: String?
    let feedback: String?
}

// MARK: - User Progress
struct UserProgress: Codable {
    var completedQuestions: [String]
    var averageScore: Double  // var: FirebaseService cần ghi trực tiếp
    var totalSubmissions: Int
    var lastActivityDate: Date?  // optional: serverTimestamp nil khi mới tạo
    var task1Completed: Int
    var task2Completed: Int
}

// MARK: - Firebase Service Error (hợp nhất từ cả 2 phiên bản)
enum FirebaseServiceError: LocalizedError {
    case notAuthenticated
    case documentNotFound
    case invalidData
    case encodingFailed
    case uploadFailed
    case networkError

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Vui lòng đăng nhập để tiếp tục."
        case .documentNotFound: return "Không tìm thấy dữ liệu yêu cầu."
        case .invalidData: return "Định dạng dữ liệu không hợp lệ."
        case .encodingFailed: return "Không thể mã hoá dữ liệu."
        case .uploadFailed: return "Tải dữ liệu lên thất bại."
        case .networkError: return "Lỗi kết nối mạng."
        }
    }
}

// MARK: - Plan (IAP)
struct PlanBenefits: Codable {
    let unlimitedTests: Bool
    let detailedAnalytics: Bool
    let offlineMode: Bool
    let prioritySupport: Bool
    let adsRemoved: Bool
}

struct Plan: Codable, Identifiable {
    @DocumentID var id: String?
    let displayName: String
    let price: Int
    let benefits: PlanBenefits

    enum CodingKeys: String, CodingKey {
        case displayName, price, benefits
    }
}

// MARK: - Avatar Upload Error
enum AvatarUploadError: LocalizedError {
    case noCurrentUser
    case imageCompressionFailed
    case uploadFailed(Error)
    case downloadURLFailed(Error)
    case firestoreUpdateFailed(Error)

    var errorDescription: String? {
        switch self {
        case .noCurrentUser:
            return "No authenticated user found."
        case .imageCompressionFailed:
            return "Failed to compress image data."
        case .uploadFailed(let error):
            return "Upload failed: \(error.localizedDescription)"
        case .downloadURLFailed(let error):
            return "Failed to get download URL: \(error.localizedDescription)"
        case .firestoreUpdateFailed(let error):
            return "Failed to update profile: \(error.localizedDescription)"
        }
    }
}


// MARK: - Supporting Models
struct PolicyInfo: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let title: String
    let type: PolicyType
}

enum PolicyType: String, Identifiable {
    case termsOfUse = "Terms of Use"
    case privacyPolicy = "Privacy Policy"
    var id: String { rawValue }
}

struct AlertMessage: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

// MARK: - Biometric Auth Error
enum BiometricError: LocalizedError {
    case notAvailable
    case notEnrolled
    case failed(Error)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notAvailable: return "Biometric authentication is not available on this device."
        case .notEnrolled: return "No biometric data enrolled. Please set up Face ID in Settings."
        case .failed(let error): return error.localizedDescription
        case .cancelled: return "Authentication was cancelled."
        }
    }
}

// MARK: - Biometric Type
enum BiometricType {
    case faceID
    case touchID
    case none
}
