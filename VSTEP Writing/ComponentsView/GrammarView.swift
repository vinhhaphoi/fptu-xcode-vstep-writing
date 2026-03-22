// GrammarView.swift
// VSTEP Writing - Grammar Guide with bilingual support (English / Vietnamese)

import SwiftUI

// MARK: - Grammar View

struct GrammarView: View {

    @StateObject private var service = ContentService.shared
    @Environment(LanguageManager.self) private var languageManager
    @State private var selectedCategory: GrammarCategoryFS? = nil
    @State private var searchText: String = ""

    private var currentLanguage: AppLanguage { languageManager.currentLanguage }

    private var displayedCategories: [GrammarCategoryFS] {
        guard !searchText.isEmpty else { return service.grammarCategories }
        return service.grammarCategories.filter { category in
            category.title(for: currentLanguage)
                .localizedCaseInsensitiveContains(searchText)
                || category.lessons.contains {
                    $0.title(for: currentLanguage)
                        .localizedCaseInsensitiveContains(searchText)
                }
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                grammarHeaderBanner
                    .padding(.horizontal)

                if service.isLoadingGrammar {
                    GrammarSkeletonView()
                        .padding(.horizontal)
                } else if !searchText.isEmpty && displayedCategories.isEmpty {
                    grammarEmptySearch
                        .padding(.horizontal)
                } else {
                    categoryGrid
                        .padding(.horizontal)

                    if searchText.isEmpty {
                        commonMistakesSection
                            .padding(.horizontal)
                    }
                }

                Spacer(minLength: 40)
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(
            currentLanguage == .vietnamese ? "Ngữ pháp" : "Grammar Guide"
        )
        .toolbarTitleDisplayMode(.large)
        .searchable(
            text: $searchText,
            prompt: currentLanguage == .vietnamese
                ? "Tìm chủ điểm ngữ pháp..."
                : "Search grammar topics..."
        )
        .sheet(item: $selectedCategory) { category in
            GrammarCategorySheet(category: category, language: currentLanguage)
        }
        .task {
            if service.grammarCategories.isEmpty {
                await service.fetchGrammarCategories()
            }
        }
        .refreshable {
            await service.fetchGrammarCategories()
        }
    }

    // MARK: - Header Banner

    private var grammarHeaderBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                currentLanguage == .vietnamese
                    ? "Điểm ngữ pháp quan trọng"
                    : "Key Grammar Points",
                systemImage: "text.badge.checkmark"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(BrandColor.light)

            Text(
                currentLanguage == .vietnamese
                    ? "Ngữ pháp thiết yếu cho VSTEP"
                    : "Essential Grammar for VSTEP"
            )
            .font(.title3.bold())
            .foregroundStyle(.primary)

            Text(
                currentLanguage == .vietnamese
                    ? "Nắm vững các điểm ngữ pháp này để nâng cao điểm Task Achievement và Language score."
                    : "Master these grammar areas to boost your Task Achievement and Language score."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassEffect(
            .regular.tint(BrandColor.light.opacity(0.08)),
            in: .rect(cornerRadius: 16)
        )
    }

    // MARK: - Category Grid

    private var categoryGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                searchText.isEmpty
                    ? (currentLanguage == .vietnamese
                        ? "Danh mục ngữ pháp" : "Grammar Categories")
                    : (currentLanguage == .vietnamese
                        ? "Kết quả tìm kiếm" : "Search Results")
            )
            .font(.headline)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                ForEach(displayedCategories) { category in
                    GrammarCategoryCard(
                        category: category,
                        language: currentLanguage,
                        onTap: { selectedCategory = category }
                    )
                }
            }
        }
    }

    // MARK: - Empty Search State

    private var grammarEmptySearch: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(
                currentLanguage == .vietnamese
                    ? "Không tìm thấy kết quả cho \"\(searchText)\""
                    : "No results for \"\(searchText)\""
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .glassEffect(in: .rect(cornerRadius: 16))
    }

    // MARK: - Common Mistakes Section

    private var commonMistakesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                currentLanguage == .vietnamese
                    ? "5 lỗi phổ biến nhất"
                    : "Top 5 Common Mistakes"
            )
            .font(.headline)

            VStack(spacing: 0) {
                let mistakes = GrammarCommonMistake.all(for: currentLanguage)
                ForEach(Array(mistakes.enumerated()), id: \.offset) {
                    index,
                    mistake in
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.12))
                                .frame(width: 28, height: 28)
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(.red)
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            Text(mistake.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                                    .padding(.top, 1)
                                Text(mistake.wrong)
                                    .font(.caption)
                                    .foregroundStyle(.red.opacity(0.8))
                                    .italic()
                                    .fixedSize(
                                        horizontal: false,
                                        vertical: true
                                    )
                            }

                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                                    .padding(.top, 1)
                                Text(mistake.correct)
                                    .font(.caption)
                                    .foregroundStyle(.green.opacity(0.9))
                                    .fixedSize(
                                        horizontal: false,
                                        vertical: true
                                    )
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    if index < mistakes.count - 1 {
                        Divider().padding(.leading, 58)
                    }
                }
            }
            .glassEffect(in: .rect(cornerRadius: 16))
        }
    }
}

// MARK: - Grammar Skeleton Loading View

private struct GrammarSkeletonView: View {

    @State private var isAnimating = false

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 12
        ) {
            ForEach(0..<6, id: \.self) { index in
                VStack(alignment: .leading, spacing: 10) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.secondarySystemBackground))
                        .frame(width: 44, height: 44)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.secondarySystemBackground))
                        .frame(height: 14)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.secondarySystemBackground))
                        .frame(width: 60, height: 20)
                        .clipShape(Capsule())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .glassEffect(in: .rect(cornerRadius: 14))
                .opacity(isAnimating ? 0.45 : 1.0)
                .animation(
                    .easeInOut(duration: 0.9)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.1),
                    value: isAnimating
                )
            }
        }
        .onAppear { isAnimating = true }
        .onDisappear { isAnimating = false }
    }
}

// MARK: - Grammar Category Card

private struct GrammarCategoryCard: View {

    let category: GrammarCategoryFS
    let language: AppLanguage
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(category.color.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: category.icon)
                        .font(.system(size: 20))
                        .foregroundStyle(category.color)
                }

                Text(category.title(for: language))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                let lessonCount = category.lessons.count
                Text(
                    language == .vietnamese
                        ? "\(lessonCount) bài học"
                        : "\(lessonCount) lesson\(lessonCount == 1 ? "" : "s")"
                )
                .font(.caption2)
                .foregroundStyle(category.color)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(category.color.opacity(0.1))
                .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .glassEffect(in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Grammar Category Sheet

struct GrammarCategorySheet: View {

    let category: GrammarCategoryFS
    let language: AppLanguage
    @Environment(\.dismiss) private var dismiss
    @State private var expandedLessonId: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    // Category header
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(category.color.opacity(0.15))
                                .frame(width: 52, height: 52)
                            Image(systemName: category.icon)
                                .font(.system(size: 24))
                                .foregroundStyle(category.color)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(category.title(for: language))
                                .font(.title3.bold())
                                .foregroundStyle(.primary)
                            let count = category.lessons.count
                            Text(
                                language == .vietnamese
                                    ? "\(count) bài học"
                                    : "\(count) lesson\(count == 1 ? "" : "s")"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(14)
                    .glassEffect(
                        .regular.tint(category.color.opacity(0.06)),
                        in: .rect(cornerRadius: 16)
                    )

                    // Lessons
                    VStack(spacing: 10) {
                        ForEach(category.lessons) { lesson in
                            GrammarLessonCard(
                                lesson: lesson,
                                language: language,
                                accentColor: category.color,
                                isExpanded: expandedLessonId == lesson.id,
                                onTap: {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        expandedLessonId =
                                            expandedLessonId == lesson.id
                                            ? nil : lesson.id
                                    }
                                }
                            )
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(category.title(for: language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.title3)
                    }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Grammar Lesson Card

private struct GrammarLessonCard: View {

    let lesson: GrammarLessonFS
    let language: AppLanguage
    let accentColor: Color
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Collapsed header
            Button(action: onTap) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(lesson.title(for: language))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)

                        let explanation = lesson.explanation(for: language)
                        let preview = explanation.prefix(65)
                        Text(preview + (explanation.count > 65 ? "…" : ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(
                        systemName: isExpanded ? "chevron.up" : "chevron.down"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                .padding(14)
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                Divider().padding(.horizontal, 14)

                VStack(alignment: .leading, spacing: 14) {
                    // Full explanation
                    Text(lesson.explanation(for: language))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Examples
                    let validExamples = lesson.examples.filter {
                        !$0.correct.isEmpty
                    }
                    if !validExamples.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(language == .vietnamese ? "Ví dụ" : "Examples")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(accentColor)

                            ForEach(validExamples) { example in
                                VStack(alignment: .leading, spacing: 5) {
                                    if !example.wrong.isEmpty {
                                        HStack(alignment: .top, spacing: 6) {
                                            Image(
                                                systemName: "xmark.circle.fill"
                                            )
                                            .font(.caption)
                                            .foregroundStyle(.red)
                                            .padding(.top, 1)
                                            Text(example.wrong)
                                                .font(.caption)
                                                .foregroundStyle(
                                                    .red.opacity(0.85)
                                                )
                                                .italic()
                                                .fixedSize(
                                                    horizontal: false,
                                                    vertical: true
                                                )
                                        }
                                    }

                                    HStack(alignment: .top, spacing: 6) {
                                        Image(
                                            systemName: "checkmark.circle.fill"
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                        .padding(.top, 1)
                                        Text(example.correct)
                                            .font(.caption)
                                            .foregroundStyle(
                                                .green.opacity(0.9)
                                            )
                                            .fixedSize(
                                                horizontal: false,
                                                vertical: true
                                            )
                                    }

                                    let note = example.note(for: language)
                                    if !note.isEmpty {
                                        Text(note)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .padding(.leading, 18)
                                    }
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    Color(.secondarySystemBackground).opacity(
                                        0.6
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }

                    // Common mistakes
                    let mistakes = lesson.commonMistakes(for: language)
                    if !mistakes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(
                                language == .vietnamese ? "Lưu ý" : "Remember",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.orange)

                            ForEach(mistakes, id: \.self) { mistake in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "circlebadge.fill")
                                        .font(.system(size: 6))
                                        .foregroundStyle(.orange)
                                        .padding(.top, 4)
                                    Text(mistake)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(
                                            horizontal: false,
                                            vertical: true
                                        )
                                }
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    )
                )
            }
        }
        .glassEffect(in: .rect(cornerRadius: 14))
    }
}

// MARK: - Grammar Common Mistake Model (bilingual)

struct GrammarCommonMistake {
    let title: String
    let wrong: String
    let correct: String

    static func all(for language: AppLanguage) -> [GrammarCommonMistake] {
        language == .vietnamese ? vietnamese : english
    }

    private static let english: [GrammarCommonMistake] = [
        GrammarCommonMistake(
            title: "Wrong Article Usage",
            wrong: "A government should protect the environment.",
            correct: "The government should protect the environment."
        ),
        GrammarCommonMistake(
            title: "Modal Verb + 'to'",
            wrong: "People should to consider both sides of the issue.",
            correct: "People should consider both sides of the issue."
        ),
        GrammarCommonMistake(
            title: "Subject-Verb Agreement",
            wrong: "The number of students who studies abroad have increased.",
            correct: "The number of students who study abroad has increased."
        ),
        GrammarCommonMistake(
            title: "Tense with Time Markers",
            wrong: "Technology improved significantly in recent years.",
            correct: "Technology has improved significantly in recent years."
        ),
        GrammarCommonMistake(
            title: "Although + But (Double Connectors)",
            wrong: "Although it is expensive, but it is worth it.",
            correct: "Although it is expensive, it is worth it."
        ),
    ]

    private static let vietnamese: [GrammarCommonMistake] = [
        GrammarCommonMistake(
            title: "Sai mạo từ",
            wrong: "A government should protect the environment.",
            correct: "The government should protect the environment."
        ),
        GrammarCommonMistake(
            title: "Động từ khuyết thiếu + 'to'",
            wrong: "People should to consider both sides of the issue.",
            correct: "People should consider both sides of the issue."
        ),
        GrammarCommonMistake(
            title: "Hòa hợp chủ ngữ - động từ",
            wrong: "The number of students who studies abroad have increased.",
            correct: "The number of students who study abroad has increased."
        ),
        GrammarCommonMistake(
            title: "Sai thì với trạng từ thời gian",
            wrong: "Technology improved significantly in recent years.",
            correct: "Technology has improved significantly in recent years."
        ),
        GrammarCommonMistake(
            title: "Dùng cả Although lẫn But",
            wrong: "Although it is expensive, but it is worth it.",
            correct: "Although it is expensive, it is worth it."
        ),
    ]
}
