import Foundation
import SwiftUI

// MARK: - String + Markdown

extension String {
    func markdownAttributed() -> AttributedString {
        do {
            return try AttributedString(
                markdown: self,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                )
            )
        } catch {
            return AttributedString(stringLiteral: self)
        }
    }
}
