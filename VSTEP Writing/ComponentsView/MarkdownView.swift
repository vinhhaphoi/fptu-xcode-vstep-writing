import SwiftUI

// MARK: - MarkdownParser
// Parsing logic lives here since it is only used by MarkdownView
private struct MarkdownParser {
    static func parse(_ content: String) -> [MarkdownBlock] {
        let lines = content.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var numberedCounter = 0
        var lastWasContent = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                if lastWasContent {
                    blocks.append(.spacer)
                    lastWasContent = false
                }
                continue
            }

            if let match = trimmed.firstMatch(of: /^(\d+)\.\s+(.+)$/) {
                numberedCounter = Int(match.1) ?? (numberedCounter + 1)
                blocks.append(.numberedItem(numberedCounter, String(match.2)))
                lastWasContent = true
                continue
            }

            let leadingSpaces = line.prefix(while: { $0 == " " }).count
            let level = leadingSpaces / 4

            if trimmed.hasPrefix("* ") || trimmed.hasPrefix("- ") {
                let text = String(trimmed.dropFirst(2))
                blocks.append(.bulletItem(text, level))
                lastWasContent = true
                numberedCounter = 0
                continue
            }

            numberedCounter = 0
            blocks.append(.paragraph(trimmed))
            lastWasContent = true
        }

        return blocks
    }
}

// MARK: - MarkdownView
struct MarkdownView: View {

    let content: String
    let textColor: Color

    private var blocks: [MarkdownBlock] { MarkdownParser.parse(content) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            Text(inlineMarkdown(text))
                .font(.body)
                .foregroundColor(textColor)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 2)

        case .numberedItem(let index, let text):
            HStack(alignment: .top, spacing: 6) {
                Text("\(index).")
                    .font(.body.monospacedDigit())
                    .foregroundColor(textColor)
                    .frame(minWidth: 24, alignment: .trailing)
                Text(inlineMarkdown(text))
                    .font(.body)
                    .foregroundColor(textColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 4)

        case .bulletItem(let text, let level):
            HStack(alignment: .top, spacing: 8) {
                Text(level == 0 ? "•" : "◦")
                    .font(.body)
                    .foregroundColor(textColor.opacity(0.7))
                    .frame(width: 12, alignment: .center)
                Text(inlineMarkdown(text))
                    .font(.body)
                    .foregroundColor(textColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(level) * 16 + 4)

        case .spacer:
            Spacer().frame(height: 4)
        }
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full
        )
        return (try? AttributedString(markdown: text, options: options))
            ?? AttributedString(text)
    }
}
