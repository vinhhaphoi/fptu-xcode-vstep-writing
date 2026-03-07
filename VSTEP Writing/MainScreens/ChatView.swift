import StoreKit
import SwiftUI

// Main VSTEP Writing chat screen — embedded inside TabBarView's NavigationStack
struct ChatView: View {

    @StateObject private var viewModel: ChatViewModel
    @Environment(StoreKitManager.self) private var store
    @FocusState private var isInputFocused: Bool
    @State private var showHistory = false

    init() {
        _viewModel = StateObject(wrappedValue: ChatViewModel())
    }

    // MARK: - Derived State

    private var usageManager: AIUsageManager { AIUsageManager.shared }

    private var isFreeUser: Bool {
        !store.isPurchased("com.vstep.advanced")
            && !store.isPurchased("com.vstep.premier")
    }

    private var canChat: Bool {
        usageManager.canUseChatbot(store: store).isAllowed
    }

    private var remainingQuestions: Int {
        usageManager.remainingChatbot(store: store)
    }

    private var chatbotLimit: Int {
        usageManager.limits(for: store).chatbotQuestionsPerDay
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            usageBanner

            messageList
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ChatInputView(
                        text: $viewModel.inputText,
                        isFocused: $isInputFocused,
                        isDisabled: !canChat,
                        onSend: { handleSend() }
                    )
                }
        }
        .navigationTitle("VSTEP Writing Assistant")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showHistory) {
            ChatHistoryView(viewModel: viewModel)
        }
        .overlay(alignment: .top) {
            if let error = viewModel.errorMessage {
                errorBanner(message: error)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.errorMessage)
        .task {
            await usageManager.loadInitialData()
        }
    }

    // MARK: - Usage Banner

    @ViewBuilder
    private var usageBanner: some View {
        if !isFreeUser && remainingQuestions <= 3 && chatbotLimit > 0 {
            remainingBanner
        }
    }

    private var remainingBanner: some View {
        HStack(spacing: 10) {
            Image(
                systemName: remainingQuestions == 0
                    ? "xmark.circle.fill"
                    : "exclamationmark.triangle.fill"
            )
            .font(.system(size: 14))
            .foregroundStyle(
                remainingQuestions == 0 ? Color.red : BrandColor.soft
            )

            Text(
                remainingQuestions == 0
                    ? "No questions left today. Resets at midnight."
                    : "\(remainingQuestions) of \(chatbotLimit) questions remaining today."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(in: .rect(cornerRadius: 16))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if isFreeUser {
                        upgradePromptCard
                            .padding(.top, 40)
                    } else {
                        ForEach(viewModel.messages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                                .transition(
                                    .asymmetric(
                                        insertion: .move(
                                            edge: message.role == .user
                                                ? .trailing : .leading
                                        ).combined(with: .opacity),
                                        removal: .opacity
                                    )
                                )
                        }

                        if viewModel.isTyping {
                            TypingIndicatorView()
                                .id("typing_indicator")
                                .transition(
                                    .opacity.combined(
                                        with: .move(edge: .leading)
                                    )
                                )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .animation(
                    .easeInOut(duration: 0.3),
                    value: viewModel.messages.count
                )
                .animation(
                    .easeInOut(duration: 0.25),
                    value: viewModel.isTyping
                )
            }
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle())
            .onTapGesture { isInputFocused = false }
            .onChange(of: viewModel.messages.count) {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.isTyping) { _, newValue in
                if newValue { scrollToTypingIndicator(proxy: proxy) }
            }
        }
    }

    // MARK: - Upgrade Prompt Card

    private var upgradePromptCard: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(BrandColor.muted)
                    .frame(width: 80, height: 80)

                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(BrandColor.primary)
            }

            VStack(spacing: 8) {
                Text("AI Chatbot — Subscribers Only")
                    .font(.headline)
                    .foregroundStyle(BrandColor.primary)
                    .multilineTextAlignment(.center)

                Text(
                    "Upgrade to Advanced or Premier to ask unlimited writing questions, get grammar tips, and practice strategies."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }

            NavigationLink {
                SubscriptionsView()
            } label: {
                Text("View Plans")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(BrandColor.primary))
            }
        }
        .padding(24)
        .glassEffect(in: .rect(cornerRadius: 16.0))
        .padding(.horizontal, 24)
    }

    // MARK: - Error Banner

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BrandColor.soft)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.primary)

            Spacer()

            Button {
                viewModel.dismissError()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // History button - hidden for free users
        ToolbarItem(placement: .navigationBarLeading) {
            if !isFreeUser {
                Button {
                    showHistory = true
                } label: {
                    Image(
                        systemName:
                            "clock.arrow.trianglehead.counterclockwise.rotate.90"
                    )
                    .fontWeight(.medium)
                    .foregroundStyle(BrandColor.primary)
                }
            }
        }

        // Remaining count + new session - hidden for free users
        ToolbarItem(placement: .navigationBarTrailing) {
            if !isFreeUser {
                HStack(spacing: 12) {
                    // Remaining count - only show when above warning threshold
                    if remainingQuestions > 3 {
                        HStack(spacing: 4) {
                            Image(systemName: "bubble.left.fill")
                                .font(.caption)
                            Text("\(remainingQuestions)")
                                .font(.caption.monospacedDigit())
                        }
                        .foregroundStyle(BrandColor.medium)
                    }

                    // New session button
                    Button {
                        viewModel.startNewSession()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .fontWeight(.medium)
                            .foregroundStyle(BrandColor.primary)
                    }
                }
            }
        }
    }

    // MARK: - Send Handler

    private func handleSend() {
        // Banner already shows the reason - just block silently here
        guard canChat else { return }

        viewModel.sendMessage()

        Task {
            await usageManager.recordChatbotQuestion()
        }
    }

    // MARK: - Scroll Helpers

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let lastId = viewModel.messages.last?.id else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo(lastId, anchor: .bottom)
        }
    }

    private func scrollToTypingIndicator(proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo("typing_indicator", anchor: .bottom)
        }
    }
}
