// VSTEPModels.swift
import Foundation
import FirebaseFirestore
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
    let questionId: String          // non-optional: luôn có trong Firestore doc
    let taskType: String
    let category: String
    let title: String
    let situation: String?
    let topic: String?
    let instruction: String?
    let requirements: [String]?
    let formalityLevel: String?
    let essayType: String?
    let difficulty: String
    var tags: [String]              // var: tránh crash nếu field vắng trong Firestore
    let suggestedStructure: [String]?

    // MARK: Computed
    var isTask1: Bool  { taskType == "task1" }
    var isTask2: Bool  { taskType == "task2" }
    var minWords: Int  { isTask1 ? 120 : 250 }
    var timeLimit: Int { isTask1 ? 20 : 40 }

    enum CodingKeys: String, CodingKey {
        case questionId, taskType, category, title, situation, topic
        case instruction, requirements, formalityLevel, essayType
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
    case draft      = "draft"
    case submitted  = "submitted"
    case grading    = "grading"
    case graded     = "graded"
    case failed     = "failed"

    var displayText: String {
        switch self {
        case .draft:     return "Draft"
        case .submitted: return "Submitted"
        case .grading:   return "Grading…"
        case .graded:    return "Graded"
        case .failed:    return "Failed"
        }
    }

    var icon: String {
        switch self {
        case .draft:     return "doc"
        case .submitted: return "paperplane.fill"
        case .grading:   return "clock.fill"
        case .graded:    return "checkmark.seal.fill"
        case .failed:    return "xmark.circle.fill"
        }
    }
}

// MARK: - User Submission
struct UserSubmission: Identifiable, Codable {
    @DocumentID var id: String?        // Firestore doc ID — ignored on encode [web:26]
    var questionId: String             // non-optional: luôn có khi submit
    let content: String                // nội dung essay
    let wordCount: Int
    var submittedAt: Date
    var score: Double?                 // 0–10 VSTEP, nil = chưa chấm
    var feedback: String?
    var status: SubmissionStatus
    var essayText: String? = nil       // = nil → memberwise init không bắt buộc truyền [web:35]

    enum CodingKeys: String, CodingKey {
        case questionId, content, wordCount, submittedAt
        case score, feedback, status, essayText
    }
}

// MARK: - User Progress
struct UserProgress: Codable {
    var completedQuestions: [String]
    var averageScore: Double           // var: FirebaseService cần ghi trực tiếp
    var totalSubmissions: Int
    var lastActivityDate: Date?        // optional: serverTimestamp nil khi mới tạo
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
        case .invalidData:      return "Định dạng dữ liệu không hợp lệ."
        case .encodingFailed:   return "Không thể mã hoá dữ liệu."
        case .uploadFailed:     return "Tải dữ liệu lên thất bại."
        case .networkError:     return "Lỗi kết nối mạng."
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
