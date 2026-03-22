// ContentService.swift
// VSTEP Writing - Shared Firestore service for writing templates and grammar content
// Supports bilingual display: English and Vietnamese

import FirebaseFirestore
import Foundation
import SwiftUI
import Combine

// MARK: - Writing Template Models

struct WritingTemplateFS: Identifiable, Codable {
    @DocumentID var id: String?
    var typeNumber: Int
    var titleEn: String
    var titleVi: String
    var subtitleEn: String
    var subtitleVi: String
    var icon: String
    var colorHex: String
    var isPublished: Bool
    var order: Int
    var sectionsEn: [TemplateSectionFS]
    var sectionsVi: [TemplateSectionFS]
    var createdAt: Date?
    var updatedAt: Date?

    var color: Color { Color(hex: colorHex) }

    // Returns the localized title based on current app language
    func title(for language: AppLanguage) -> String {
        language == .vietnamese ? titleVi : titleEn
    }

    // Returns the localized subtitle based on current app language
    func subtitle(for language: AppLanguage) -> String {
        language == .vietnamese ? subtitleVi : subtitleEn
    }

    // Returns the localized sections based on current app language
    func sections(for language: AppLanguage) -> [TemplateSectionFS] {
        language == .vietnamese ? sectionsVi : sectionsEn
    }

    enum CodingKeys: String, CodingKey {
        case typeNumber
        case titleEn, titleVi
        case subtitleEn, subtitleVi
        case icon, colorHex, isPublished, order
        case sectionsEn, sectionsVi
        case createdAt, updatedAt
    }
}

struct TemplateSectionFS: Codable, Identifiable {
    let id: String
    var heading: String
    var content: String
}

// MARK: - Grammar Models

struct GrammarCategoryFS: Identifiable, Codable {
    @DocumentID var id: String?
    var titleEn: String
    var titleVi: String
    var icon: String
    var colorHex: String
    var isPublished: Bool
    var order: Int
    var lessons: [GrammarLessonFS]
    var createdAt: Date?
    var updatedAt: Date?

    var color: Color { Color(hex: colorHex) }

    func title(for language: AppLanguage) -> String {
        language == .vietnamese ? titleVi : titleEn
    }

    enum CodingKeys: String, CodingKey {
        case titleEn, titleVi, icon, colorHex, isPublished, order, lessons,
            createdAt, updatedAt
    }
}

struct GrammarLessonFS: Codable, Identifiable {
    let id: String
    var titleEn: String
    var titleVi: String
    var explanationEn: String
    var explanationVi: String
    var examples: [GrammarExampleFS]
    var commonMistakesEn: [String]
    var commonMistakesVi: [String]

    func title(for language: AppLanguage) -> String {
        language == .vietnamese ? titleVi : titleEn
    }

    func explanation(for language: AppLanguage) -> String {
        language == .vietnamese ? explanationVi : explanationEn
    }

    func commonMistakes(for language: AppLanguage) -> [String] {
        language == .vietnamese ? commonMistakesVi : commonMistakesEn
    }
}

struct GrammarExampleFS: Codable, Identifiable {
    let id: String
    var wrong: String
    var correct: String
    var noteEn: String
    var noteVi: String

    func note(for language: AppLanguage) -> String {
        language == .vietnamese ? noteVi : noteEn
    }
}

// MARK: - Content Service

@MainActor
final class ContentService: ObservableObject {

    static let shared = ContentService()

    @Published var templates: [WritingTemplateFS] = []
    @Published var grammarCategories: [GrammarCategoryFS] = []
    @Published var isLoadingTemplates: Bool = false
    @Published var isLoadingGrammar: Bool = false

    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Fetch Writing Templates
    // Collection: writingTemplates
    // Filter: isPublished == true, ordered by field 'order'

    func fetchTemplates() async {
        isLoadingTemplates = true
        defer { isLoadingTemplates = false }

        do {
            let snapshot =
                try await db
                .collection("writingTemplates")
                .whereField("isPublished", isEqualTo: true)
                .order(by: "order")
                .getDocuments()

            let fetched = snapshot.documents.compactMap {
                try? $0.data(as: WritingTemplateFS.self)
            }

            templates = fetched.isEmpty ? WritingTemplateFallback.all : fetched

        } catch {
            templates = WritingTemplateFallback.all
            print(
                "[ContentService] fetchTemplates error: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Fetch Grammar Categories
    // Collection: grammarCategories
    // Filter: isPublished == true, ordered by field 'order'

    func fetchGrammarCategories() async {
        isLoadingGrammar = true
        defer { isLoadingGrammar = false }

        do {
            let snapshot =
                try await db
                .collection("grammarCategories")
                .whereField("isPublished", isEqualTo: true)
                .order(by: "order")
                .getDocuments()

            let fetched = snapshot.documents.compactMap {
                try? $0.data(as: GrammarCategoryFS.self)
            }

            grammarCategories =
                fetched.isEmpty ? GrammarCategoryFallback.all : fetched

        } catch {
            grammarCategories = GrammarCategoryFallback.all
            print(
                "[ContentService] fetchGrammarCategories error: \(error.localizedDescription)"
            )
        }
    }
}

// MARK: - Writing Template Fallback Data
// All placeholder labels are written in proper Vietnamese with full diacritics

enum WritingTemplateFallback {
    static let all: [WritingTemplateFS] = [type1, type2, type3, type4, type5]

    // MARK: Type 1 - Discussion

    static let type1 = WritingTemplateFS(
        typeNumber: 1,
        titleEn: "Discussion",
        titleVi: "Thảo luận hai quan điểm",
        subtitleEn: "Discussion of Two Viewpoints",
        subtitleVi: "Trình bày và bình luận hai quan điểm trái chiều",
        icon: "text.bubble.fill",
        colorHex: "0066CC",
        isPublished: true,
        order: 1,
        sectionsEn: [
            TemplateSectionFS(
                id: "d_en_1",
                heading: "Introduction",
                content: """
                    In recent years, ... (topic) .... has become a broad issue to the general public. Some people believe that... (viewpoint 1) .... However, others think that ..... (viewpoint 2)..... In my opinion, I agree with the former / latter idea. Discussed below are several reasons supporting my perspective.
                    """
            ),
            TemplateSectionFS(
                id: "d_en_2",
                heading: "Body Paragraph 1 — Viewpoint 1",
                content: """
                    First and foremost, people should recognize that (viewpoint 1). A very important point to consider is that (reason 1). This means that (explanation 1). To illustrate this point, I would like to mention that (example 1). Another point I would like to make is that (reason 2). This is because of the fact that (explanation 2). For example, (example 2).
                    """
            ),
            TemplateSectionFS(
                id: "d_en_3",
                heading: "Body Paragraph 2 — Viewpoint 2",
                content: """
                    On the other hand, there are several arguments in support of the idea that (viewpoint 2). It is also convincing to realize that (reason). This means that (explanation). A specific example of this is that (example).
                    """
            ),
            TemplateSectionFS(
                id: "d_en_4",
                heading: "Conclusion",
                content: """
                    In conclusion, the above mentioned facts have created a dilemma when people evaluate the impact of this issue, and it is still a controversial issue. As far as I am concerned, I put more highlight on the idea that.... People should have further consideration on this issue.
                    """
            ),
        ],
        sectionsVi: [
            TemplateSectionFS(
                id: "d_vi_1",
                heading: "Mở bài",
                content: """
                    In recent years, ... (chủ đề) .... has become a broad issue to the general public. Some people believe that... (quan điểm 1) .... However, others think that ..... (quan điểm 2)..... In my opinion, I agree with the former / latter idea. Discussed below are several reasons supporting my perspective.
                    """
            ),
            TemplateSectionFS(
                id: "d_vi_2",
                heading: "Thân bài 1 — Quan điểm 1",
                content: """
                    First and foremost, people should recognize that (quan điểm 1). A very important point to consider is that (lí do 1). This means that (giải thích 1). To illustrate this point, I would like to mention that (ví dụ 1). Another point I would like to make is that (lí do 2). This is because of the fact that (giải thích 2). For example, (ví dụ 2).
                    """
            ),
            TemplateSectionFS(
                id: "d_vi_3",
                heading: "Thân bài 2 — Quan điểm 2",
                content: """
                    On the other hand, there are several arguments in support of the idea that (quan điểm 2). It is also convincing to realize that (lí do). This means that (giải thích). A specific example of this is that (ví dụ).
                    """
            ),
            TemplateSectionFS(
                id: "d_vi_4",
                heading: "Kết bài",
                content: """
                    In conclusion, the above mentioned facts have created a dilemma when people evaluate the impact of this issue, and it is still a controversial issue. As far as I am concerned, I put more highlight on the idea that.... People should have further consideration on this issue.
                    """
            ),
        ]
    )

    // MARK: Type 2 - Agree or Disagree

    static let type2 = WritingTemplateFS(
        typeNumber: 2,
        titleEn: "Agree – Disagree",
        titleVi: "Đồng ý – Không đồng ý",
        subtitleEn: "Argue for or against a statement",
        subtitleVi: "Trình bày quan điểm đồng ý hoặc không đồng ý",
        icon: "checkmark.square.fill",
        colorHex: "2E8B57",
        isPublished: true,
        order: 2,
        sectionsEn: [
            TemplateSectionFS(
                id: "a_en_1",
                heading: "Introduction",
                content: """
                    In recent years, ..... (topic).... has become a broad issue to the general public. Some people believe that.... (viewpoint).... In my opinion, I partly agree with this idea. Discussed below are several reasons in favor of my perspectives.
                    """
            ),
            TemplateSectionFS(
                id: "a_en_2",
                heading: "Body Paragraph 1 — Supporting Side",
                content: """
                    First and foremost, people should recognize that (viewpoint). A very important point to consider is that (reason 1). This means that (explanation 1). To illustrate this point, I would like to mention that (example 1). Another point I would like to make is that (reason 2). This is because of the fact that (explanation 2). For example, (example 2).
                    """
            ),
            TemplateSectionFS(
                id: "a_en_3",
                heading: "Body Paragraph 2 — Opposing Side",
                content: """
                    On the other hand, there are several arguments against the statement that (viewpoint). In fact, people have this opinion because (reason against 1). This means that (explanation for opposing viewpoint). This can be shown by the example that (example).
                    """
            ),
            TemplateSectionFS(
                id: "a_en_4",
                heading: "Conclusion",
                content: """
                    In conclusion, the above mentioned facts have created a dilemma when people evaluate the impact of this issue, and it is still a controversial issue. As far as I am concerned, it could have both positive and negative impacts. People should have further consideration on this issue.
                    """
            ),
        ],
        sectionsVi: [
            TemplateSectionFS(
                id: "a_vi_1",
                heading: "Mở bài",
                content: """
                    In recent years, ..... (chủ đề).... has become a broad issue to the general public. Some people believe that.... (quan điểm).... In my opinion, I partly agree with this idea. Discussed below are several reasons in favor of my perspectives.
                    """
            ),
            TemplateSectionFS(
                id: "a_vi_2",
                heading: "Thân bài 1 — Đồng ý",
                content: """
                    First and foremost, people should recognize that (quan điểm). A very important point to consider is that (lí do đồng ý 1). This means that (giải thích 1). To illustrate this point, I would like to mention that (ví dụ 1). Another point I would like to make is that (lí do đồng ý 2). This is because of the fact that (giải thích 2). For example, (ví dụ 2).
                    """
            ),
            TemplateSectionFS(
                id: "a_vi_3",
                heading: "Thân bài 2 — Không đồng ý",
                content: """
                    On the other hand, there are several arguments against the statement that (quan điểm). In fact, people have this opinion because (lí do không đồng ý 1). This means that (giải thích cho quan điểm không đồng ý). This can be shown by the example that (ví dụ).
                    """
            ),
            TemplateSectionFS(
                id: "a_vi_4",
                heading: "Kết bài",
                content: """
                    In conclusion, the above mentioned facts have created a dilemma when people evaluate the impact of this issue, and it is still a controversial issue. As far as I am concerned, it could have both positive and negative impacts. People should have further consideration on this issue.
                    """
            ),
        ]
    )

    // MARK: Type 3 - Advantages and Disadvantages

    static let type3 = WritingTemplateFS(
        typeNumber: 3,
        titleEn: "Advantages – Disadvantages",
        titleVi: "Lợi ích – Bất lợi",
        subtitleEn: "Discuss the benefits and drawbacks of an issue",
        subtitleVi: "Phân tích lợi ích và bất lợi của một vấn đề",
        icon: "arrow.up.arrow.down.circle.fill",
        colorHex: "7B2D8B",
        isPublished: true,
        order: 3,
        sectionsEn: [
            TemplateSectionFS(
                id: "adv_en_1",
                heading: "Introduction",
                content: """
                    In recent years, (topic) has become a broad issue to the general public. Some people believe the issue that (topic) has many advantages. However, others think that it could also have some negative effects. In my opinion, its cons could never overshadow its pros. Discussed below are several benefits as well as drawbacks of this issue.
                    """
            ),
            TemplateSectionFS(
                id: "adv_en_2",
                heading: "Body Paragraph 1 — Advantages",
                content: """
                    First and foremost, people should recognize that there are many advantages of (topic). A very important point to consider is that (advantage 1). This means that (explanation for advantage 1). To illustrate this point, I would like to mention that (example 1). Another point I would like to make is that (advantage 2). This is because of the fact that (explanation 2). For example, (example 2).
                    """
            ),
            TemplateSectionFS(
                id: "adv_en_3",
                heading: "Body Paragraph 2 — Disadvantages",
                content: """
                    On the other hand, in addition to the important advantages of this problem, it has some disadvantages. In fact, people have this opinion because (disadvantage 1). This means that (explanation). This can be shown by example that (example).
                    """
            ),
            TemplateSectionFS(
                id: "adv_en_4",
                heading: "Conclusion",
                content: """
                    In conclusion, the above mentioned facts have outlined the benefits as well as the drawbacks of this issue. Its disadvantages should be taken into account. People should take advantages of the pros and minimize the cons of this issue.
                    """
            ),
        ],
        sectionsVi: [
            TemplateSectionFS(
                id: "adv_vi_1",
                heading: "Mở bài",
                content: """
                    In recent years, (chủ đề) has become a broad issue to the general public. Some people believe the issue that (chủ đề) has many advantages. However, others think that it could also have some negative effects. In my opinion, its cons could never overshadow its pros. Discussed below are several benefits as well as drawbacks of this issue.
                    """
            ),
            TemplateSectionFS(
                id: "adv_vi_2",
                heading: "Thân bài 1 — Lợi ích",
                content: """
                    First and foremost, people should recognize that there are many advantages of (chủ đề). A very important point to consider is that (thuận lợi 1). This means that (giải thích cho thuận lợi 1). To illustrate this point, I would like to mention that (ví dụ 1). Another point I would like to make is that (thuận lợi 2). This is because of the fact that (giải thích 2). For example, (ví dụ 2).
                    """
            ),
            TemplateSectionFS(
                id: "adv_vi_3",
                heading: "Thân bài 2 — Bất lợi",
                content: """
                    On the other hand, in addition to the important advantages of this problem, it has some disadvantages. In fact, people have this opinion because (bất lợi 1). This means that (giải thích). This can be shown by example that (ví dụ).
                    """
            ),
            TemplateSectionFS(
                id: "adv_vi_4",
                heading: "Kết bài",
                content: """
                    In conclusion, the above mentioned facts have outlined the benefits as well as the drawbacks of this issue. Its disadvantages should be taken into account. People should take advantages of the pros and minimize the cons of this issue.
                    """
            ),
        ]
    )

    // MARK: Type 4 - Causes and Effects

    static let type4 = WritingTemplateFS(
        typeNumber: 4,
        titleEn: "Causes – Effects",
        titleVi: "Nguyên nhân – Hậu quả",
        subtitleEn: "Identify the causes and resulting effects of an issue",
        subtitleVi: "Phân tích nguyên nhân và hậu quả của một vấn đề",
        icon: "arrow.triangle.branch",
        colorHex: "CC6600",
        isPublished: true,
        order: 4,
        sectionsEn: [
            TemplateSectionFS(
                id: "ce_en_1",
                heading: "Introduction",
                content: """
                    In recent years, (topic) has become a broad issue to the general public. Although noticeable, the impact of this issue has not been realized by many residents. Discussed below are several causes as well as effects of this issue.
                    """
            ),
            TemplateSectionFS(
                id: "ce_en_2",
                heading: "Body Paragraph 1 — Causes",
                content: """
                    First and foremost, people should recognize that there are several reasons supporting the idea that (viewpoint). A very important point to consider is that (cause 1). This means that (explanation for cause 1). To illustrate this point, I would like to mention that (example 1). Another point I would like to make is that (cause 2). This is because of the fact that (explanation 2). For example, (example 2).
                    """
            ),
            TemplateSectionFS(
                id: "ce_en_3",
                heading: "Body Paragraph 2 — Effects",
                content: """
                    There are many serious effects of this issue. One primary effect would be that (effect 1). In addition, (effect 2).
                    """
            ),
            TemplateSectionFS(
                id: "ce_en_4",
                heading: "Conclusion",
                content: """
                    In conclusion, the above-mentioned facts have outlined the reasons as well as the measures of this issue. Its cause and effects should be taken into account. People should have further consideration on this issue.
                    """
            ),
        ],
        sectionsVi: [
            TemplateSectionFS(
                id: "ce_vi_1",
                heading: "Mở bài",
                content: """
                    In recent years, (chủ đề) has become a broad issue to the general public. Although noticeable, the impact of this issue has not been realized by many residents. Discussed below are several causes as well as effects of this issue.
                    """
            ),
            TemplateSectionFS(
                id: "ce_vi_2",
                heading: "Thân bài 1 — Nguyên nhân",
                content: """
                    First and foremost, people should recognize that there are several reasons supporting the idea that (quan điểm). A very important point to consider is that (nguyên nhân 1). This means that (giải thích cho nguyên nhân 1). To illustrate this point, I would like to mention that (ví dụ 1). Another point I would like to make is that (nguyên nhân 2). This is because of the fact that (giải thích 2). For example, (ví dụ 2).
                    """
            ),
            TemplateSectionFS(
                id: "ce_vi_3",
                heading: "Thân bài 2 — Hậu quả",
                content: """
                    There are many serious effects of this issue. One primary effect would be that (hậu quả 1). In addition, (hậu quả 2).
                    """
            ),
            TemplateSectionFS(
                id: "ce_vi_4",
                heading: "Kết bài",
                content: """
                    In conclusion, the above-mentioned facts have outlined the reasons as well as the measures of this issue. Its cause and effects should be taken into account. People should have further consideration on this issue.
                    """
            ),
        ]
    )

    // MARK: Type 5 - Causes and Solutions

    static let type5 = WritingTemplateFS(
        typeNumber: 5,
        titleEn: "Causes – Solutions",
        titleVi: "Nguyên nhân – Giải pháp",
        subtitleEn: "Identify causes and propose solutions to an issue",
        subtitleVi: "Phân tích nguyên nhân và đề xuất giải pháp",
        icon: "lightbulb.max.fill",
        colorHex: "CC1430",
        isPublished: true,
        order: 5,
        sectionsEn: [
            TemplateSectionFS(
                id: "cs_en_1",
                heading: "Introduction",
                content: """
                    In recent years, (topic) has become a broad issue to the general public. Although noticeable, the impact of this issue has not been realized by many residents. Discussed below are several causes as well as solutions of this issue.
                    """
            ),
            TemplateSectionFS(
                id: "cs_en_2",
                heading: "Body Paragraph 1 — Causes",
                content: """
                    First and foremost, people should recognize that there are several main reasons supporting the idea that (viewpoint). A very important point to consider is that (cause 1). This means that (explanation for cause 1). To illustrate this point, I would like to mention that (example 1). Another point I would like to make is that (cause 2). This is because of the fact that (explanation 2). For example, (example 2).
                    """
            ),
            TemplateSectionFS(
                id: "cs_en_3",
                heading: "Body Paragraph 2 — Solutions",
                content: """
                    In order to resolve such problems, people should take some concerted measures. One primary solution would be that (solution 1). In addition, (solution 2). However, education is the main way to tackle this issue. People need to be aware of the effects so that they can avoid this problem.
                    """
            ),
            TemplateSectionFS(
                id: "cs_en_4",
                heading: "Conclusion",
                content: """
                    In conclusion, the above-mentioned facts have outlined the reasons as well as the measures of this issue. The presented suggestions would be very good steps towards solving them. People should have further consideration on this issue.
                    """
            ),
        ],
        sectionsVi: [
            TemplateSectionFS(
                id: "cs_vi_1",
                heading: "Mở bài",
                content: """
                    In recent years, (chủ đề) has become a broad issue to the general public. Although noticeable, the impact of this issue has not been realized by many residents. Discussed below are several causes as well as solutions of this issue.
                    """
            ),
            TemplateSectionFS(
                id: "cs_vi_2",
                heading: "Thân bài 1 — Nguyên nhân",
                content: """
                    First and foremost, people should recognize that there are several main reasons supporting the idea that (quan điểm). A very important point to consider is that (nguyên nhân 1). This means that (giải thích cho nguyên nhân 1). To illustrate this point, I would like to mention that (ví dụ 1). Another point I would like to make is that (nguyên nhân 2). This is because of the fact that (giải thích 2). For example, (ví dụ 2).
                    """
            ),
            TemplateSectionFS(
                id: "cs_vi_3",
                heading: "Thân bài 2 — Giải pháp",
                content: """
                    In order to resolve such problems, people should take some concerted measures. One primary solution would be that (giải pháp 1). In addition, (giải pháp 2). However, education is the main way to tackle this issue. People need to be aware of the effects so that they can avoid this problem.
                    """
            ),
            TemplateSectionFS(
                id: "cs_vi_4",
                heading: "Kết bài",
                content: """
                    In conclusion, the above-mentioned facts have outlined the reasons as well as the measures of this issue. The presented suggestions would be very good steps towards solving them. People should have further consideration on this issue.
                    """
            ),
        ]
    )
}

// MARK: - Grammar Category Fallback Data
// Bilingual: English explanations + Vietnamese translations for all lesson content

enum GrammarCategoryFallback {
    static let all: [GrammarCategoryFS] = [
        tenseConsistency, complexSentences, articlesAndDeterminers,
        modalVerbs, passiveVoice, conditionals,
    ]

    // MARK: Tense Consistency

    static let tenseConsistency = GrammarCategoryFS(
        titleEn: "Tense Consistency",
        titleVi: "Sự nhất quán về thì",
        icon: "clock.arrow.2.circlepath",
        colorHex: "0066CC",
        isPublished: true,
        order: 1,
        lessons: [
            GrammarLessonFS(
                id: "t1",
                titleEn: "Present Simple for Facts",
                titleVi: "Hiện tại đơn diễn đạt sự thật",
                explanationEn:
                    "Use Present Simple when stating general truths, facts, or when presenting arguments in academic essays. Most VSTEP Task 2 essays are written in Present Simple.",
                explanationVi:
                    "Dùng Hiện tại đơn khi trình bày sự thật chung, dữ kiện, hoặc khi lập luận trong bài luận học thuật. Phần lớn bài Task 2 VSTEP được viết ở thì Hiện tại đơn.",
                examples: [
                    GrammarExampleFS(
                        id: "t1e1",
                        wrong:
                            "Technology has allowed people to connect easier.",
                        correct:
                            "Technology allows people to connect more easily.",
                        noteEn:
                            "Present Simple is preferred for stating general facts.",
                        noteVi:
                            "Hiện tại đơn được dùng để diễn đạt sự thật chung."
                    )
                ],
                commonMistakesEn: [
                    "Mixing Past Simple with Present Simple without reason.",
                    "Using Present Continuous for general habits (e.g. 'People are studying' instead of 'People study').",
                ],
                commonMistakesVi: [
                    "Trộn lẫn Quá khứ đơn với Hiện tại đơn không có lí do.",
                    "Dùng Hiện tại tiếp diễn cho thói quen chung (ví dụ: 'People are studying' thay vì 'People study').",
                ]
            ),
            GrammarLessonFS(
                id: "t2",
                titleEn: "Present Perfect vs Past Simple",
                titleVi: "Hiện tại hoàn thành vs Quá khứ đơn",
                explanationEn:
                    "Use Present Perfect when the time is not specified or the result is still relevant. Use Past Simple for completed actions at a specific time.",
                explanationVi:
                    "Dùng Hiện tại hoàn thành khi thời gian không xác định hoặc kết quả vẫn còn liên quan. Dùng Quá khứ đơn cho hành động hoàn thành tại một thời điểm cụ thể.",
                examples: [
                    GrammarExampleFS(
                        id: "t2e1",
                        wrong: "Technology improved a lot in recent years.",
                        correct:
                            "Technology has improved a lot in recent years.",
                        noteEn: "'In recent years' signals Present Perfect.",
                        noteVi:
                            "'In recent years' là tín hiệu của Hiện tại hoàn thành."
                    ),
                    GrammarExampleFS(
                        id: "t2e2",
                        wrong: "Scientists have discovered penicillin in 1928.",
                        correct: "Scientists discovered penicillin in 1928.",
                        noteEn:
                            "'In 1928' is a specific time, so Past Simple is correct.",
                        noteVi:
                            "'In 1928' là thời điểm cụ thể, nên dùng Quá khứ đơn."
                    ),
                ],
                commonMistakesEn: [
                    "Using Past Simple with 'recently', 'lately', 'in recent years'.",
                    "Using Present Perfect with specific time markers like 'yesterday', 'last year', 'in 2020'.",
                ],
                commonMistakesVi: [
                    "Dùng Quá khứ đơn với 'recently', 'lately', 'in recent years'.",
                    "Dùng Hiện tại hoàn thành với mốc thời gian cụ thể như 'yesterday', 'last year', 'in 2020'.",
                ]
            ),
        ]
    )

    // MARK: Complex Sentences

    static let complexSentences = GrammarCategoryFS(
        titleEn: "Complex Sentences",
        titleVi: "Câu phức",
        icon: "link",
        colorHex: "7B2D8B",
        isPublished: true,
        order: 2,
        lessons: [
            GrammarLessonFS(
                id: "c1",
                titleEn: "Subordinating Conjunctions",
                titleVi: "Liên từ phụ thuộc",
                explanationEn:
                    "Subordinating conjunctions (because, although, since, while, if, unless, whereas) connect a main clause with a dependent clause. They show relationships between ideas and are essential for a high grammar score.",
                explanationVi:
                    "Liên từ phụ thuộc (because, although, since, while, if, unless, whereas) nối mệnh đề chính với mệnh đề phụ. Chúng thể hiện mối quan hệ giữa các ý và rất quan trọng để đạt điểm ngữ pháp cao.",
                examples: [
                    GrammarExampleFS(
                        id: "c1e1",
                        wrong:
                            "Many people live in cities. They want better job opportunities.",
                        correct:
                            "Many people live in cities because they want better job opportunities.",
                        noteEn: "'Because' joins the reason to the main idea.",
                        noteVi: "'Because' nối lí do vào ý chính."
                    ),
                    GrammarExampleFS(
                        id: "c1e2",
                        wrong: "",
                        correct:
                            "Although technology has many advantages, it also creates serious problems.",
                        noteEn:
                            "'Although' introduces a contrast before the comma.",
                        noteVi:
                            "'Although' đưa ra sự tương phản trước dấu phẩy."
                    ),
                ],
                commonMistakesEn: [
                    "Writing two short sentences instead of one complex sentence.",
                    "Confusing 'although/even though' (conjunction) with 'however/nevertheless' (adverb).",
                    "Using 'although... but...' together — only one connector is needed.",
                ],
                commonMistakesVi: [
                    "Viết hai câu ngắn thay vì một câu phức.",
                    "Nhầm lẫn 'although/even though' (liên từ) với 'however/nevertheless' (trạng từ).",
                    "Dùng cả 'although... but...' — chỉ cần một trong hai.",
                ]
            ),
            GrammarLessonFS(
                id: "c2",
                titleEn: "Relative Clauses",
                titleVi: "Mệnh đề quan hệ",
                explanationEn:
                    "Use 'who' for people, 'which' for things in non-defining clauses, and 'that' for people or things in defining clauses.",
                explanationVi:
                    "Dùng 'who' cho người, 'which' cho vật trong mệnh đề không giới hạn, và 'that' cho người hoặc vật trong mệnh đề giới hạn.",
                examples: [
                    GrammarExampleFS(
                        id: "c2e1",
                        wrong: "",
                        correct:
                            "Students who study consistently tend to achieve higher scores.",
                        noteEn:
                            "'who' refers to 'Students' — a defining relative clause.",
                        noteVi:
                            "'who' chỉ 'Students' — mệnh đề quan hệ giới hạn."
                    ),
                    GrammarExampleFS(
                        id: "c2e2",
                        wrong: "",
                        correct:
                            "The internet, which was invented in the 20th century, has transformed communication.",
                        noteEn:
                            "Non-defining clause uses commas and 'which', not 'that'.",
                        noteVi:
                            "Mệnh đề không giới hạn dùng dấu phẩy và 'which', không dùng 'that'."
                    ),
                ],
                commonMistakesEn: [
                    "Using 'which' instead of 'who' for people.",
                    "Forgetting the commas in non-defining relative clauses.",
                    "Repeating the pronoun: 'The book which I bought it' — remove 'it'.",
                ],
                commonMistakesVi: [
                    "Dùng 'which' thay vì 'who' cho người.",
                    "Quên dấu phẩy trong mệnh đề quan hệ không giới hạn.",
                    "Lặp đại từ: 'The book which I bought it' — phải bỏ 'it'.",
                ]
            ),
        ]
    )

    // MARK: Articles and Determiners

    static let articlesAndDeterminers = GrammarCategoryFS(
        titleEn: "Articles & Determiners",
        titleVi: "Mạo từ",
        icon: "textformat",
        colorHex: "CC6600",
        isPublished: true,
        order: 3,
        lessons: [
            GrammarLessonFS(
                id: "ar1",
                titleEn: "Definite Article: THE",
                titleVi: "Mạo từ xác định: THE",
                explanationEn:
                    "Use 'the' when both the writer and reader know which specific thing is being referred to — when it has been mentioned before, or when it is unique (the sun, the government, the internet).",
                explanationVi:
                    "Dùng 'the' khi cả người viết và người đọc đều biết đang nói về cái gì cụ thể — khi đã đề cập trước đó, hoặc khi nó là duy nhất (the sun, the government, the internet).",
                examples: [
                    GrammarExampleFS(
                        id: "ar1e1",
                        wrong: "A government should invest more in education.",
                        correct:
                            "The government should invest more in education.",
                        noteEn: "We refer to a specific, known government.",
                        noteVi:
                            "Chúng ta đề cập đến một chính phủ cụ thể, đã biết."
                    ),
                    GrammarExampleFS(
                        id: "ar1e2",
                        wrong:
                            "Internet has changed the way people communicate.",
                        correct:
                            "The internet has changed the way people communicate.",
                        noteEn: "'The internet' is unique — there is only one.",
                        noteVi:
                            "'The internet' là duy nhất — chỉ có một mạng internet."
                    ),
                ],
                commonMistakesEn: [
                    "Omitting 'the' before unique nouns: the environment, the internet, the government.",
                    "Using 'the' before uncountable or plural nouns in general statements: 'The money is important' should be 'Money is important'.",
                ],
                commonMistakesVi: [
                    "Bỏ sót 'the' trước danh từ duy nhất: the environment, the internet, the government.",
                    "Dùng 'the' trước danh từ không đếm được hoặc danh từ số nhiều trong phát biểu chung: 'The money is important' phải là 'Money is important'.",
                ]
            ),
            GrammarLessonFS(
                id: "ar2",
                titleEn: "Indefinite Article: A / AN",
                titleVi: "Mạo từ không xác định: A / AN",
                explanationEn:
                    "Use 'a' before consonant sounds and 'an' before vowel sounds. Use 'a/an' when introducing a singular countable noun for the first time.",
                explanationVi:
                    "Dùng 'a' trước âm phụ âm và 'an' trước âm nguyên âm. Dùng 'a/an' khi giới thiệu danh từ đếm được số ít lần đầu tiên.",
                examples: [
                    GrammarExampleFS(
                        id: "ar2e1",
                        wrong: "An university was built in the city.",
                        correct: "A university was built in the city.",
                        noteEn:
                            "'University' starts with a /j/ sound, not a vowel sound.",
                        noteVi:
                            "'University' bắt đầu bằng âm /j/, không phải âm nguyên âm."
                    ),
                    GrammarExampleFS(
                        id: "ar2e2",
                        wrong: "",
                        correct: "An honest person always tells the truth.",
                        noteEn:
                            "'Honest' starts with a vowel sound /ɒ/, so use 'an'.",
                        noteVi:
                            "'Honest' bắt đầu bằng âm nguyên âm /ɒ/, nên dùng 'an'."
                    ),
                ],
                commonMistakesEn: [
                    "Choosing 'a/an' based on spelling instead of pronunciation.",
                    "Using articles with uncountable nouns: 'a water', 'an advice' are incorrect.",
                    "Using 'a/an' with plural nouns.",
                ],
                commonMistakesVi: [
                    "Chọn 'a/an' dựa vào chính tả thay vì cách phát âm.",
                    "Dùng mạo từ với danh từ không đếm được: 'a water', 'an advice' là sai.",
                    "Dùng 'a/an' với danh từ số nhiều.",
                ]
            ),
        ]
    )

    // MARK: Modal Verbs

    static let modalVerbs = GrammarCategoryFS(
        titleEn: "Modal Verbs",
        titleVi: "Động từ khuyết thiếu",
        icon: "slider.horizontal.3",
        colorHex: "2E8B57",
        isPublished: true,
        order: 4,
        lessons: [
            GrammarLessonFS(
                id: "m1",
                titleEn: "Should, Must, Have to",
                titleVi: "Should, Must, Have to — Nghĩa vụ và khuyến nghị",
                explanationEn:
                    "Use 'should' for recommendations. Use 'must' for strong obligation or logical deduction. Modal verbs are NEVER followed by 'to' (except 'have to', 'ought to').",
                explanationVi:
                    "Dùng 'should' để đưa ra khuyến nghị. Dùng 'must' cho nghĩa vụ mạnh hoặc suy luận logic. Động từ khuyết thiếu KHÔNG BAO GIỜ đi theo sau bởi 'to' (trừ 'have to', 'ought to').",
                examples: [
                    GrammarExampleFS(
                        id: "m1e1",
                        wrong:
                            "People must to consider the long-term consequences.",
                        correct:
                            "People must consider the long-term consequences.",
                        noteEn: "Never use 'to' directly after a modal verb.",
                        noteVi:
                            "Không bao giờ dùng 'to' ngay sau động từ khuyết thiếu."
                    ),
                    GrammarExampleFS(
                        id: "m1e2",
                        wrong: "",
                        correct:
                            "Governments should invest more in renewable energy.",
                        noteEn:
                            "'Should' gives a recommendation without sounding too forceful.",
                        noteVi:
                            "'Should' đưa ra khuyến nghị mà không nghe quá cứng nhắc."
                    ),
                ],
                commonMistakesEn: [
                    "Adding 'to' after modals: 'should to do', 'must to go' — WRONG.",
                    "Using 'Everyone should works' — the verb stays in base form after a modal.",
                    "Using 'must' for recommendations — it sounds too strong; use 'should' instead.",
                ],
                commonMistakesVi: [
                    "Thêm 'to' sau modal: 'should to do', 'must to go' — SAI.",
                    "Dùng 'Everyone should works' — động từ giữ nguyên dạng cơ bản sau modal.",
                    "Dùng 'must' cho khuyến nghị — nghe quá mạnh; hãy dùng 'should' thay thế.",
                ]
            ),
            GrammarLessonFS(
                id: "m2",
                titleEn: "Can, Could, May, Might",
                titleVi: "Can, Could, May, Might — Khả năng và sự cho phép",
                explanationEn:
                    "Use 'can/could' for ability or possibility. Use 'may/might' for uncertain possibility. In academic writing, 'may' and 'might' help express ideas with appropriate caution.",
                explanationVi:
                    "Dùng 'can/could' cho khả năng hoặc sự có thể. Dùng 'may/might' cho khả năng không chắc chắn. Trong văn học thuật, 'may' và 'might' giúp diễn đạt ý kiến với sự thận trọng phù hợp.",
                examples: [
                    GrammarExampleFS(
                        id: "m2e1",
                        wrong: "",
                        correct:
                            "This policy may lead to significant improvements in public health.",
                        noteEn:
                            "'May' expresses academic caution — a good writing strategy.",
                        noteVi:
                            "'May' diễn đạt sự thận trọng học thuật — một chiến lược viết tốt."
                    ),
                    GrammarExampleFS(
                        id: "m2e2",
                        wrong: "",
                        correct:
                            "Increased investment could solve the housing crisis.",
                        noteEn: "'Could' expresses a conditional possibility.",
                        noteVi: "'Could' diễn đạt khả năng có điều kiện."
                    ),
                ],
                commonMistakesEn: [
                    "Confusing 'can' (ability) with 'may' (permission/possibility) in formal writing.",
                    "Using 'might' when 'must' is needed for logical deduction.",
                ],
                commonMistakesVi: [
                    "Nhầm lẫn 'can' (khả năng) với 'may' (sự cho phép/khả năng) trong văn phong trang trọng.",
                    "Dùng 'might' khi cần 'must' cho suy luận logic.",
                ]
            ),
        ]
    )

    // MARK: Passive Voice

    static let passiveVoice = GrammarCategoryFS(
        titleEn: "Passive Voice",
        titleVi: "Câu bị động",
        icon: "arrow.left.arrow.right",
        colorHex: "CC1430",
        isPublished: true,
        order: 5,
        lessons: [
            GrammarLessonFS(
                id: "p1",
                titleEn: "Forming the Passive Voice",
                titleVi: "Cách tạo câu bị động",
                explanationEn:
                    "Passive voice = Subject + be (conjugated) + past participle. Use passive when the action is more important than the doer, or when the doer is unknown. Very common in academic and formal writing.",
                explanationVi:
                    "Câu bị động = Chủ ngữ + be (chia) + quá khứ phân từ. Dùng bị động khi hành động quan trọng hơn chủ thể, hoặc khi không biết chủ thể. Rất phổ biến trong văn học thuật và trang trọng.",
                examples: [
                    GrammarExampleFS(
                        id: "p1e1",
                        wrong: "",
                        correct:
                            "The new policy was introduced by the government last year.",
                        noteEn:
                            "Past Simple Passive: was/were + past participle.",
                        noteVi:
                            "Bị động Quá khứ đơn: was/were + quá khứ phân từ."
                    ),
                    GrammarExampleFS(
                        id: "p1e2",
                        wrong: "",
                        correct:
                            "A great deal of money is spent on healthcare every year.",
                        noteEn:
                            "Present Simple Passive: is/are + past participle.",
                        noteVi:
                            "Bị động Hiện tại đơn: is/are + quá khứ phân từ."
                    ),
                    GrammarExampleFS(
                        id: "p1e3",
                        wrong: "",
                        correct:
                            "The problem could be solved through better education.",
                        noteEn: "Modal Passive: modal + be + past participle.",
                        noteVi:
                            "Bị động với Modal: modal + be + quá khứ phân từ."
                    ),
                ],
                commonMistakesEn: [
                    "Forgetting to conjugate 'be': 'The letter write by her' should be 'was written'.",
                    "Confusing past tense with past participle: 'was wrote' instead of 'was written'.",
                    "Overusing passive voice when active voice is clearer.",
                ],
                commonMistakesVi: [
                    "Quên chia 'be': 'The letter write by her' phải là 'was written'.",
                    "Nhầm thì quá khứ với quá khứ phân từ: 'was wrote' thay vì 'was written'.",
                    "Lạm dụng câu bị động khi câu chủ động rõ hơn.",
                ]
            )
        ]
    )

    // MARK: Conditionals

    static let conditionals = GrammarCategoryFS(
        titleEn: "Conditionals",
        titleVi: "Câu điều kiện",
        icon: "arrow.triangle.branch",
        colorHex: "008B8B",
        isPublished: true,
        order: 6,
        lessons: [
            GrammarLessonFS(
                id: "con1",
                titleEn: "First Conditional — Real Future Possibility",
                titleVi:
                    "Câu điều kiện loại 1 — Khả năng có thật trong tương lai",
                explanationEn:
                    "Form: If + Present Simple, will + base verb. Use when the condition is realistic and likely to happen in the future.",
                explanationVi:
                    "Cấu trúc: If + Hiện tại đơn, will + động từ nguyên thể. Dùng khi điều kiện có thật và có khả năng xảy ra trong tương lai.",
                examples: [
                    GrammarExampleFS(
                        id: "con1e1",
                        wrong:
                            "If governments will invest more, education will improve.",
                        correct:
                            "If governments invest more, education will improve.",
                        noteEn:
                            "The 'if' clause uses Present Simple, not 'will'.",
                        noteVi:
                            "Mệnh đề 'if' dùng Hiện tại đơn, không dùng 'will'."
                    )
                ],
                commonMistakesEn: [
                    "Using 'will' in the if-clause: 'If it will rain...' is WRONG.",
                    "Confusing with Zero Conditional (used for universal facts).",
                ],
                commonMistakesVi: [
                    "Dùng 'will' trong mệnh đề if: 'If it will rain...' là SAI.",
                    "Nhầm với câu điều kiện loại 0 (dùng cho sự thật hiển nhiên).",
                ]
            ),
            GrammarLessonFS(
                id: "con2",
                titleEn: "Second Conditional — Hypothetical Situations",
                titleVi: "Câu điều kiện loại 2 — Tình huống giả định",
                explanationEn:
                    "Form: If + Past Simple, would + base verb. Use for hypothetical, unlikely, or imaginary situations in the present or future. Very useful in VSTEP essays for suggesting solutions.",
                explanationVi:
                    "Cấu trúc: If + Quá khứ đơn, would + động từ nguyên thể. Dùng cho tình huống giả định, ít có khả năng xảy ra, hoặc tưởng tượng. Rất hữu ích trong bài luận VSTEP khi đề xuất giải pháp.",
                examples: [
                    GrammarExampleFS(
                        id: "con2e1",
                        wrong:
                            "If the government would reduce taxes, businesses would grow.",
                        correct:
                            "If the government reduced taxes, businesses would grow faster.",
                        noteEn:
                            "Use Past Simple in the if-clause, not 'would'.",
                        noteVi:
                            "Dùng Quá khứ đơn trong mệnh đề if, không dùng 'would'."
                    ),
                    GrammarExampleFS(
                        id: "con2e2",
                        wrong: "",
                        correct:
                            "If everyone had access to quality education, poverty rates would decrease significantly.",
                        noteEn:
                            "A strong hypothetical argument structure for Task 2.",
                        noteVi: "Cấu trúc lập luận giả định mạnh mẽ cho Task 2."
                    ),
                ],
                commonMistakesEn: [
                    "Using 'would' in the if-clause: 'If I would have...' — WRONG.",
                    "Confusing Second and Third Conditional for present vs past hypotheticals.",
                ],
                commonMistakesVi: [
                    "Dùng 'would' trong mệnh đề if: 'If I would have...' — SAI.",
                    "Nhầm câu điều kiện loại 2 và loại 3 cho giả định hiện tại và quá khứ.",
                ]
            ),
        ]
    )
}
