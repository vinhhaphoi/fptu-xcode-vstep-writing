import SwiftUI

// Main VSTEP Writing chat screen — embedded inside TabBarView's NavigationStack
struct ChatView: View {

    @StateObject private var viewModel: ChatViewModel
    @FocusState private var isInputFocused: Bool

    // Controls the delete history confirmation alert
    @State private var showClearConfirmation = false

    @State private var showHistory = false

    init() {
        _viewModel = StateObject(wrappedValue: ChatViewModel())
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ChatInputView(
                        text: $viewModel.inputText,
                        isFocused: $isInputFocused,
                        onSend: { viewModel.sendMessage() }
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
        // Confirmation alert before clearing chat history
        .confirmationDialog(
            "Start a new conversation?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete History", role: .destructive) {
                viewModel.clearSession()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the current conversation.")
        }
    }

    // Scrollable message list with auto-scroll and interactive keyboard dismiss
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        MessageBubbleView(message: message)
                            .id(message.id)
                            .transition(
                                .asymmetric(
                                    insertion: .move(
                                        edge: message.role == .user
                                            ? .trailing : .leading
                                    )
                                    .combined(with: .opacity),
                                    removal: .opacity
                                )
                            )
                    }

                    if viewModel.isTyping {
                        TypingIndicatorView()
                            .id("typing_indicator")
                            .transition(
                                .opacity.combined(with: .move(edge: .leading))
                            )
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
            // Drag scroll down to dismiss keyboard interactively
            .scrollDismissesKeyboard(.interactively)
            // Tap empty space to dismiss keyboard
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

    // Error banner shown at top when Firebase call fails
    private func errorBanner(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)

            Text(message)
                .font(.footnote)
                .foregroundColor(.primary)

            Spacer()

            Button {
                viewModel.dismissError()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // Toolbar: compose button triggers confirmation dialog before clearing
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                showHistory = true
            } label: {
                Image(
                    systemName:
                        "clock.arrow.trianglehead.counterclockwise.rotate.90"
                )
                .fontWeight(.medium)
            }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                if viewModel.messages.count > 1 {
                    showClearConfirmation = true
                } else {
                    viewModel.clearSession()
                }
            } label: {
                Image(systemName: "square.and.pencil")
                    .fontWeight(.medium)
            }
        }
    }

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
