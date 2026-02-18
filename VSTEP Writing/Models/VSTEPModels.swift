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
    
    enum CodingKeys: String, CodingKey {
        case taskId, name, description, minWords, timeLimit, taskType
    }
}

// MARK: - Question Model
struct VSTEPQuestion: Identifiable, Codable {
    @DocumentID var id: String?
    let questionId: String
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
    let tags: [String]
    let suggestedStructure: [String]?
    
    var isTask1: Bool { taskType == "task1" }
    var isTask2: Bool { taskType == "task2" }
    
    var minWords: Int {
        isTask1 ? 120 : 250
    }
    
    var timeLimit: Int {
        isTask1 ? 20 : 40
    }
    
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

// MARK: - User Submission
struct UserSubmission: Identifiable, Codable {
    @DocumentID var id: String?
    let questionId: String
    let content: String
    let wordCount: Int
    let submittedAt: Date
    let score: Double?
    let feedback: String?
    let status: SubmissionStatus
    
    enum SubmissionStatus: String, Codable {
        case draft, submitted, graded
    }
}

// MARK: - User Progress
struct UserProgress: Codable {
    let completedQuestions: [String]
    let averageScore: Double
    let totalSubmissions: Int
    let lastActivityDate: Date
    let task1Completed: Int
    let task2Completed: Int
}

// MARK: - Firebase Service Error
enum FirebaseServiceError: LocalizedError {
    case notAuthenticated
    case invalidData
    case uploadFailed
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be logged in to perform this action"
        case .invalidData:
            return "Invalid data format"
        case .uploadFailed:
            return "Failed to upload data"
        case .networkError:
            return "Network connection error"
        }
    }
}

struct PlanBenefits: Codable {
    let unlimitedTests: Bool
    let detailedAnalytics: Bool
    let offlineMode: Bool
    let prioritySupport: Bool
    let adsRemoved: Bool
}

struct Plan: Codable, Identifiable {
    @DocumentID var id: String?           // productID
    let displayName: String
    let price: Int
    let benefits: PlanBenefits
}
