import Combine
import SwiftUI

// ─────────────────────────────────────────────
// MARK: - ChatViewModel
// ─────────────────────────────────────────────

// Manages all state for the VSTEP Writing chat session
@MainActor
final class ChatViewModel: ObservableObject {

    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isTyping: Bool = false
    @Published var errorMessage: String? = nil
    @Published var isLoadingHistory: Bool = false
    @Published var sessions: [ChatSession] = []

    private let service = FirebaseService.shared
    private var currentSessionId: String? = nil

    init() {
        Task { await loadOrCreateSession() }
    }

    private func loadOrCreateSession() async {
        isLoadingHistory = true

        do {
            if let result = try await service.loadLatestChatSession() {
                currentSessionId = result.sessionId
                messages = [makeWelcomeMessage()] + result.messages
            } else {
                currentSessionId = try await service.createChatSession()
                messages = [makeWelcomeMessage()]
            }
        } catch {
            messages = [makeWelcomeMessage()]
            print(
                "[ChatViewModel] Failed to load session: \(error.localizedDescription)"
            )
        }

        isLoadingHistory = false
    }

    private func makeWelcomeMessage() -> ChatMessage {
        ChatMessage(
            role: .model,
            content:
                "Hi! I'm your VSTEP Writing Assistant. Feel free to ask about **essay structure**, **paraphrasing techniques**, **vocabulary choices**, or **writing strategies**."
        )
    }

    func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let userMessage = ChatMessage(role: .user, content: trimmed)
        messages.append(userMessage)
        inputText = ""
        errorMessage = nil

        Task { await fetchAIReply(userMessage: userMessage) }
    }

    // Trong fetchAIReply() — sau khi AI reply thanh cong
    private func fetchAIReply(userMessage: ChatMessage) async {
        isTyping = true

        do {
            let reply = try await service.askAI(messages: messages)
            let aiMessage = ChatMessage(role: .model, content: reply)
            messages.append(aiMessage)
            await saveMessages([userMessage, aiMessage])

            await AIUsageManager.shared.recordChatbotQuestion()

        } catch AIChatError.unauthenticated {
            messages.removeLast()
            errorMessage = AIChatError.unauthenticated.errorDescription
        } catch {
            errorMessage =
                (error as? AIChatError)?.errorDescription
                ?? error.localizedDescription
        }

        isTyping = false
    }

    private func saveMessages(_ newMessages: [ChatMessage]) async {
        guard let sessionId = currentSessionId else { return }
        do {
            for message in newMessages {
                try await service.appendMessage(message, toSession: sessionId)
            }
        } catch {
            print(
                "[ChatViewModel] Failed to save messages: \(error.localizedDescription)"
            )
        }
    }

    func fetchSessions() async {
        do {
            sessions = try await service.fetchAllChatSessions()
        } catch {
            print(
                "[ChatViewModel] Failed to fetch sessions: \(error.localizedDescription)"
            )
        }
    }

    func loadSession(_ session: ChatSession) {
        guard let sessionId = session.id else { return }
        currentSessionId = sessionId
        messages =
            [makeWelcomeMessage()] + session.messages.map { $0.toChatMessage() }
    }

    func deleteSessions(at indexSet: IndexSet) async {
        for index in indexSet {
            let session = sessions[index]
            guard let sessionId = session.id else { continue }
            try? await service.deleteChatSession(sessionId: sessionId)
        }
        sessions.remove(atOffsets: indexSet)
    }

    func clearSession() {
        Task {
            if let sessionId = currentSessionId {
                try? await service.deleteChatSession(sessionId: sessionId)
            }
            currentSessionId = nil
            messages.removeAll()
            isTyping = false
            errorMessage = nil
            await loadOrCreateSession()
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    // Starts a brand new session without deleting existing history
    func startNewSession() {
        Task {
            currentSessionId = nil
            messages.removeAll()
            isTyping = false
            errorMessage = nil

            do {
                currentSessionId = try await service.createChatSession()
                messages = [makeWelcomeMessage()]
            } catch {
                messages = [makeWelcomeMessage()]
                print(
                    "[ChatViewModel] Failed to create new session: \(error.localizedDescription)"
                )
            }
        }
    }

    // Deletes all sessions from Firestore and dismisses the sheet
    func deleteAllSessions(dismiss: DismissAction) async {
        do {
            let allSessions = try await service.fetchAllChatSessions()
            for session in allSessions {
                guard let sessionId = session.id else { continue }
                try? await service.deleteChatSession(sessionId: sessionId)
            }
            sessions.removeAll()
            // Start fresh after deleting everything
            currentSessionId = nil
            messages = [makeWelcomeMessage()]
            currentSessionId = try? await service.createChatSession()
        } catch {
            print(
                "[ChatViewModel] Failed to delete all sessions: \(error.localizedDescription)"
            )
        }
        dismiss()
    }

}

// ─────────────────────────────────────────────
// MARK: - MessageBubbleView
// ─────────────────────────────────────────────

// Displays a single chat bubble with Markdown rendering for AI responses
// Displays a single chat bubble with Markdown rendering for AI responses
struct MessageBubbleView: View {

    let message: ChatMessage

    private var isUser: Bool { message.role == .user }
    private var bubbleColor: Color {
        isUser ? Color.accentColor : Color(.secondarySystemBackground)
    }
    private var textColor: Color { isUser ? .white : .primary }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 60) }
            if !isUser { assistantAvatar }  // Now defined in this struct

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                bubbleContent
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleColor)
                    .clipShape(ChatBubbleShape(isUser: isUser))

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }

            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var bubbleContent: some View {
        if isUser {
            Text(message.content)
                .font(.body)
                .foregroundColor(textColor)
        } else {
            MarkdownView(content: message.content, textColor: textColor)
        }
    }

    // Avatar displayed next to AI messages — also used in TypingIndicatorView
    private var assistantAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 32, height: 32)

            Image(systemName: "graduationcap.fill")
                .font(.system(size: 15))
                .foregroundColor(.accentColor)
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - ChatBubbleShape
// ─────────────────────────────────────────────

// Custom bubble: user has tail on bottom-right, assistant on bottom-left
struct ChatBubbleShape: Shape {

    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 18
        let tailRadius: CGFloat = 4
        var path = Path()

        let topLeft = CGPoint(x: rect.minX, y: rect.minY)
        let topRight = CGPoint(x: rect.maxX, y: rect.minY)
        let bottomLeft = CGPoint(x: rect.minX, y: rect.maxY)
        let bottomRight = CGPoint(x: rect.maxX, y: rect.maxY)

        path.move(to: CGPoint(x: topLeft.x + radius, y: topLeft.y))
        path.addLine(to: CGPoint(x: topRight.x - radius, y: topRight.y))
        path.addQuadCurve(
            to: CGPoint(x: topRight.x, y: topRight.y + radius),
            control: topRight
        )
        path.addLine(
            to: CGPoint(
                x: bottomRight.x,
                y: bottomRight.y - (isUser ? tailRadius : radius)
            )
        )

        if isUser {
            path.addQuadCurve(
                to: CGPoint(x: bottomRight.x - tailRadius, y: bottomRight.y),
                control: bottomRight
            )
        } else {
            path.addQuadCurve(
                to: CGPoint(x: bottomRight.x - radius, y: bottomRight.y),
                control: bottomRight
            )
        }

        path.addLine(
            to: CGPoint(
                x: bottomLeft.x + (isUser ? radius : tailRadius),
                y: bottomLeft.y
            )
        )

        if !isUser {
            path.addQuadCurve(
                to: CGPoint(x: bottomLeft.x, y: bottomLeft.y - tailRadius),
                control: bottomLeft
            )
        } else {
            path.addQuadCurve(
                to: CGPoint(x: bottomLeft.x, y: bottomLeft.y - radius),
                control: bottomLeft
            )
        }

        path.addLine(to: CGPoint(x: topLeft.x, y: topLeft.y + radius))
        path.addQuadCurve(
            to: CGPoint(x: topLeft.x + radius, y: topLeft.y),
            control: topLeft
        )
        path.closeSubpath()
        return path
    }
}

// ─────────────────────────────────────────────
// MARK: - TypingIndicatorView
// ─────────────────────────────────────────────

// Animated three-dot bounce indicator shown while the AI is composing a reply
struct TypingIndicatorView: View {

    @State private var isAnimating = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            assistantAvatar

            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary.opacity(0.6))
                        .frame(width: 8, height: 8)
                        .offset(y: isAnimating ? -6 : 0)
                        .animation(
                            .easeInOut(duration: 0.45)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.15),
                            value: isAnimating
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.secondarySystemBackground))
            .clipShape(Capsule())

            Spacer(minLength: 60)
        }
        .padding(.vertical, 2)
        .onAppear { isAnimating = true }
        .onDisappear { isAnimating = false }
    }

    private var assistantAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 32, height: 32)

            Image(systemName: "graduationcap.fill")
                .font(.system(size: 15))
                .foregroundColor(.accentColor)
        }
    }
}

// MARK: - ChatInputView
struct ChatInputView: View {

    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var isDisabled: Bool = false  // Added: controls locked state for free users
    var onSend: () -> Void

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isDisabled
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField(
                isDisabled
                    ? "Upgrade to use the AI chatbot..." : "Ask something...",
                text: $text,
                axis: .vertical
            )
            .lineLimit(1...5)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect()
            .focused(isFocused)
            .disabled(isDisabled)

            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        canSend
                            ? Color.accentColor : Color.secondary.opacity(0.4)
                    )
            }
            .disabled(!canSend)
            .animation(.easeInOut(duration: 0.2), value: canSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemGroupedBackground))
    }
}
// ChatInputView closes here

// ─────────────────────────────────────────────
// MARK: - ChatHistoryView
// ─────────────────────────────────────────────

// Sheet with two tabs: history list and new conversation action
struct ChatHistoryView: View {

    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteAllConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.sessions.isEmpty {
                    emptySessions
                } else {
                    sessionList
                }
            }
            .navigationTitle("Chat History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .background(Color(.systemGroupedBackground))
            .confirmationDialog(
                "Delete all conversations?",
                isPresented: $showDeleteAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete All", role: .destructive) {
                    Task { await viewModel.deleteAllSessions(dismiss: dismiss) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all chat history.")
            }
        }
        .presentationDragIndicator(.hidden)
        .task { await viewModel.fetchSessions() }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Close sheet on the left
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
        }

        // Delete all on the right — only visible when sessions exist
        ToolbarItem(placement: .navigationBarTrailing) {
            if !viewModel.sessions.isEmpty {
                Button {
                    showDeleteAllConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            }
        }
    }

    private var emptySessions: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 52))
                .foregroundColor(.secondary)

            Text("No History Yet")
                .font(.headline)

            Text("Your conversations will appear here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.sessions) { session in
                    Button {
                        viewModel.loadSession(session)
                        dismiss()
                    } label: {
                        sessionRow(session)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task {
                                if let index = viewModel.sessions.firstIndex(
                                    where: { $0.id == session.id })
                                {
                                    await viewModel.deleteSessions(
                                        at: IndexSet(integer: index)
                                    )
                                }
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollContentBackground(.hidden)
    }

    // Reusable new conversation button
    private var newConversationButton: some View {
        Button {
            viewModel.startNewSession()
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.bubble.fill")
                Text("New Conversation")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.accentColor)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: Color.accentColor.opacity(0.3), radius: 8, y: 4)
        }
    }

    // Session row: last message sender + preview + exact timestamp
    private func sessionRow(_ session: ChatSession) -> some View {
        let lastMessage = session.messages.last
        let senderLabel = lastMessage?.role == "user" ? "You" : "Assistant"
        let preview = lastMessage?.content ?? "New conversation"
        let lastDate = lastMessage?.timestamp ?? session.updatedAt

        return VStack(alignment: .leading, spacing: 8) {
            Text("\(senderLabel): \(preview)")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(lastDate, format: .dateTime.day().month().hour().minute())
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 16))
    }
}
