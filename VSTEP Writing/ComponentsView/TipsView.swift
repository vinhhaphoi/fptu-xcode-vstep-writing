// TipsView.swift
// VSTEP Writing - Writing Tips with bilingual support (English / Vietnamese)

import SwiftUI

// MARK: - Tips View

struct TipsView: View {

    @StateObject private var service = ContentService.shared
    @Environment(LanguageManager.self) private var languageManager
    @State private var selectedTemplate: WritingTemplateFS? = nil
    @State private var expandedId: String? = nil

    private var currentLanguage: AppLanguage { languageManager.currentLanguage }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                tipsHeaderBanner
                    .padding(.horizontal)

                if service.isLoadingTemplates {
                    TipsSkeletonView()
                        .padding(.horizontal)
                } else {
                    templatesSection
                }

                quickTipsSection
                    .padding(.horizontal)

                Spacer(minLength: 40)
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(
            currentLanguage == .vietnamese ? "Mẹo viết" : "Writing Tips"
        )
        .toolbarTitleDisplayMode(.large)
        .sheet(item: $selectedTemplate) { template in
            TemplateDetailSheet(template: template, language: currentLanguage)
        }
        .task {
            if service.templates.isEmpty {
                await service.fetchTemplates()
            }
        }
        .refreshable {
            await service.fetchTemplates()
        }
    }

    // MARK: - Header Banner

    private var tipsHeaderBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                currentLanguage == .vietnamese
                    ? "VSTEP Task 2" : "VSTEP Task 2",
                systemImage: "doc.text.magnifyingglass"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(BrandColor.light)

            Text(
                currentLanguage == .vietnamese
                    ? "Khung bài luận mẫu"
                    : "Essay Writing Frameworks"
            )
            .font(.title3.bold())
            .foregroundStyle(.primary)

            Text(
                currentLanguage == .vietnamese
                    ? "Nắm vững cả 5 dạng bài với template đã được kiểm chứng bởi học sinh đạt điểm cao."
                    : "Master all 5 essay types with proven templates used by top scorers."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassEffect(
            .regular.tint(BrandColor.primary.opacity(0.08)),
            in: .rect(cornerRadius: 16)
        )
    }

    // MARK: - Templates Section

    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                currentLanguage == .vietnamese
                    ? "Các dạng bài" : "Writing Templates"
            )
            .font(.headline)
            .padding(.horizontal)

            VStack(spacing: 12) {
                ForEach(service.templates) { template in
                    TemplateCardView(
                        template: template,
                        language: currentLanguage,
                        isExpanded: expandedId == template.id,
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                expandedId =
                                    expandedId == template.id
                                    ? nil : template.id
                            }
                        },
                        onViewFull: {
                            selectedTemplate = template
                        }
                    )
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Quick Tips Section

    private var quickTipsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(currentLanguage == .vietnamese ? "Mẹo chung" : "General Tips")
                .font(.headline)

            VStack(spacing: 0) {
                let tips = WritingQuickTip.all(for: currentLanguage)
                ForEach(Array(tips.enumerated()), id: \.offset) { index, tip in
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(tip.color.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: tip.icon)
                                .font(.system(size: 15))
                                .foregroundStyle(tip.color)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(tip.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(tip.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    if index < tips.count - 1 {
                        Divider().padding(.leading, 66)
                    }
                }
            }
            .glassEffect(in: .rect(cornerRadius: 16))
        }
    }
}

// MARK: - Tips Skeleton Loading View

private struct TipsSkeletonView: View {

    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<4, id: \.self) { index in
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.secondarySystemBackground))
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 7) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.secondarySystemBackground))
                            .frame(width: 50, height: 11)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.secondarySystemBackground))
                            .frame(width: CGFloat(130 + index * 12), height: 14)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.secondarySystemBackground))
                            .frame(width: 110, height: 11)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .glassEffect(in: .rect(cornerRadius: 16))
                .opacity(isAnimating ? 0.45 : 1.0)
                .animation(
                    .easeInOut(duration: 0.9)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.12),
                    value: isAnimating
                )
            }
        }
        .onAppear { isAnimating = true }
        .onDisappear { isAnimating = false }
    }
}

// MARK: - Template Card View

private struct TemplateCardView: View {

    let template: WritingTemplateFS
    let language: AppLanguage
    let isExpanded: Bool
    let onTap: () -> Void
    let onViewFull: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(template.color.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: template.icon)
                            .font(.system(size: 20))
                            .foregroundStyle(template.color)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        // Type badge adapts to language
                        Text(
                            language == .vietnamese
                                ? "Dạng \(template.typeNumber)"
                                : "Type \(template.typeNumber)"
                        )
                        .font(.caption.weight(.bold))
                        .foregroundStyle(template.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(template.color.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                        Text(template.title(for: language))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)

                        Text(template.subtitle(for: language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Image(
                        systemName: isExpanded ? "chevron.up" : "chevron.down"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(template.sections(for: language).prefix(2)) {
                        section in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(section.heading)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(template.color)
                            Text(section.content)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Button(action: onViewFull) {
                        HStack(spacing: 6) {
                            Text(
                                language == .vietnamese
                                    ? "Xem đầy đủ"
                                    : "View Full Template"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(template.color)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(template.color)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(template.color.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    )
                )
            }
        }
        .glassEffect(in: .rect(cornerRadius: 16))
    }
}

// MARK: - Template Detail Sheet

struct TemplateDetailSheet: View {

    let template: WritingTemplateFS
    let language: AppLanguage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(template.color.opacity(0.15))
                                .frame(width: 50, height: 50)
                            Image(systemName: template.icon)
                                .font(.system(size: 23))
                                .foregroundStyle(template.color)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(
                                language == .vietnamese
                                    ? "Dạng \(template.typeNumber)"
                                    : "Type \(template.typeNumber)"
                            )
                            .font(.caption.weight(.bold))
                            .foregroundStyle(template.color)
                            Text(template.title(for: language))
                                .font(.title3.bold())
                                .foregroundStyle(.primary)
                        }

                        Spacer()
                    }

                    Text(template.subtitle(for: language))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Divider()

                    // All sections
                    ForEach(template.sections(for: language)) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(template.color)
                                    .frame(width: 3, height: 16)
                                Text(section.heading)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(template.color)
                            }

                            Text(section.content)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .glassEffect(in: .rect(cornerRadius: 14))
                    }

                    // Usage note
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .font(.caption)
                            .foregroundStyle(BrandColor.soft)
                        Text(
                            language == .vietnamese
                                ? "Thay thế các từ trong ngoặc đơn bằng nội dung thực tế khi viết bài."
                                : "Replace the placeholders in parentheses with your actual content when writing."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .glassEffect(
                        .regular.tint(BrandColor.muted),
                        in: .rect(cornerRadius: 12)
                    )

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(template.title(for: language))
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

// MARK: - Writing Quick Tip Model (bilingual)

struct WritingQuickTip {
    let icon: String
    let color: Color
    let title: String
    let description: String

    static func all(for language: AppLanguage) -> [WritingQuickTip] {
        language == .vietnamese ? vietnamese : english
    }

    private static let english: [WritingQuickTip] = [
        WritingQuickTip(
            icon: "clock.fill",
            color: .orange,
            title: "Time Management",
            description:
                "Task 1: 20 minutes (120+ words). Task 2: 40 minutes (250+ words). Spend 3 minutes planning before writing."
        ),
        WritingQuickTip(
            icon: "text.alignleft",
            color: BrandColor.primary,
            title: "Paragraph Structure",
            description:
                "Every body paragraph needs: Topic Sentence → Reason → Explanation → Example. Never skip the example."
        ),
        WritingQuickTip(
            icon: "link",
            color: .purple,
            title: "Cohesion & Linking",
            description:
                "Use a variety of connectors: First and foremost, On the other hand, In addition, To illustrate, In conclusion."
        ),
        WritingQuickTip(
            icon: "abc",
            color: .green,
            title: "Vocabulary Range",
            description:
                "Avoid repeating the same words. Use synonyms and academic vocabulary. Paraphrase the topic in your introduction."
        ),
        WritingQuickTip(
            icon: "checkmark.circle.fill",
            color: .blue,
            title: "Grammar Accuracy",
            description:
                "Mix simple and complex sentences. Check subject-verb agreement, tense consistency, and article usage."
        ),
        WritingQuickTip(
            icon: "arrow.triangle.2.circlepath",
            color: .red,
            title: "Review & Revise",
            description:
                "Save 3–5 minutes to re-read. Check word count, fix spelling errors, and make sure your conclusion matches your introduction."
        ),
    ]

    private static let vietnamese: [WritingQuickTip] = [
        WritingQuickTip(
            icon: "clock.fill",
            color: .orange,
            title: "Quản lý thời gian",
            description:
                "Task 1: 20 phút (120+ từ). Task 2: 40 phút (250+ từ). Dành 3 phút lập dàn ý trước khi viết."
        ),
        WritingQuickTip(
            icon: "text.alignleft",
            color: BrandColor.primary,
            title: "Cấu trúc đoạn văn",
            description:
                "Mỗi đoạn thân bài cần: Câu chủ đề → Lí do → Giải thích → Ví dụ. Không bao giờ bỏ qua ví dụ."
        ),
        WritingQuickTip(
            icon: "link",
            color: .purple,
            title: "Liên kết & Mạch lạc",
            description:
                "Dùng đa dạng từ nối: First and foremost, On the other hand, In addition, To illustrate, In conclusion."
        ),
        WritingQuickTip(
            icon: "abc",
            color: .green,
            title: "Phạm vi từ vựng",
            description:
                "Tránh lặp từ. Dùng từ đồng nghĩa và từ vựng học thuật. Paraphrase chủ đề trong phần mở bài."
        ),
        WritingQuickTip(
            icon: "checkmark.circle.fill",
            color: .blue,
            title: "Độ chính xác ngữ pháp",
            description:
                "Kết hợp câu đơn và câu phức. Kiểm tra sự hòa hợp chủ ngữ-động từ, nhất quán thì và cách dùng mạo từ."
        ),
        WritingQuickTip(
            icon: "arrow.triangle.2.circlepath",
            color: .red,
            title: "Đọc lại & Sửa bài",
            description:
                "Dành 3–5 phút đọc lại. Kiểm tra số từ, sửa lỗi chính tả và đảm bảo phần kết bài khớp với mở bài."
        ),
    ]
}
