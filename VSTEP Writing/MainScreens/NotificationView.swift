// NotificationView.swift

import FirebaseMessaging
import SwiftUI
import UserNotifications

// MARK: - NotificationView
struct NotificationView: View {
    @StateObject private var firebaseService = FirebaseService.shared
    @State private var searchText = ""
    @State private var notifications: [AppNotification] = []
    @State private var isLoading = false
    @State private var showDeleteConfirm = false
    @Environment(StoreKitManager.self) private var store

    #if DEBUG
        @State private var showTestToast = false
        @State private var toastMessage = ""
    #endif

    private var searchResults: [VSTEPQuestion] {
        guard !searchText.isEmpty else { return [] }
        return firebaseService.questions.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.difficulty.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var unreadCount: Int {
        notifications.filter { !$0.isRead }.count
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if searchText.isEmpty {
                        notificationContent

                        #if DEBUG
                            debugSection
                                .padding(.top, 32)
                        #endif
                    } else {
                        searchContent
                    }

                    Spacer(minLength: 50)
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .refreshable {
                await loadNotifications()
            }

            #if DEBUG
                if showTestToast {
                    toastView
                        .transition(
                            .move(edge: .bottom).combined(with: .opacity)
                        )
                        .padding(.bottom, 20)
                }
            #endif
        }
        .animation(.easeInOut(duration: 0.3), value: showTestToast)
        .navigationTitle("Notifications")
        .toolbarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search questions...")
        .toolbar {
            // Mark all as read - only show when there are unread notifications
            if unreadCount > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await markAllAsRead() }
                    } label: {
                        Image(systemName: "checkmark.circle")
                    }
                }
            }

            // Delete all notifications - only show when list is not empty
            if !notifications.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete all notifications?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                Task { await deleteAllNotifications() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .task {
            if firebaseService.questions.isEmpty {
                try? await firebaseService.fetchQuestions()
            }
            await loadNotifications()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .didReceivePushNotification
            )
        ) { _ in
            Task { await loadNotifications() }
        }
    }

    // MARK: - Notification Content
    private var notificationContent: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else if notifications.isEmpty {
                emptyNotificationBlock
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(notifications) { item in
                        NotificationRow(item: item) {
                            Task { await markAsRead(item) }
                        }
                        .glassEffect()
                        .padding(.horizontal)
                        .padding(.bottom, 10)
                    }
                }
            }
        }
    }

    // MARK: - Search Content
    private var searchContent: some View {
        Group {
            if searchResults.isEmpty {
                emptySearchBlock
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(
                        Array(searchResults.enumerated()),
                        id: \.element.questionId
                    ) { index, question in
                        SearchResultRow(question: question)
                        if index < searchResults.count - 1 {
                            Divider().padding(.leading, 70)
                        }
                    }
                }
                .glassEffect(in: .rect(cornerRadius: 16))
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Empty Blocks
    private var emptyNotificationBlock: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.slash")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No notifications yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Pull down to refresh")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .glassEffect(in: .rect(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var emptySearchBlock: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No results for \"\(searchText)\"")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .glassEffect(in: .rect(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - Debug Section
    #if DEBUG
        private var debugSection: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "ladybug.fill")
                        .foregroundStyle(.orange)
                    Text("Debug Tools")
                        .font(.headline)
                }
                .padding(.horizontal)

                LazyVStack(spacing: 10) {
                    debugNotificationButton(
                        icon: "checkmark.seal.fill",
                        color: .green,
                        title: "Essay Graded",
                        subtitle: "Simulate essay result notification"
                    ) {
                        NotificationTestHelper.simulateEssayGraded()
                        showToast("Notification saved & scheduled in 3s")
                        Task { await loadNotifications() }
                    }

                    debugNotificationButton(
                        icon: "doc.text.fill",
                        color: .blue,
                        title: "New Assignment",
                        subtitle: "Simulate new homework notification"
                    ) {
                        NotificationTestHelper.simulateNewAssignment()
                        showToast("Notification saved & scheduled in 3s")
                        Task { await loadNotifications() }
                    }

                    debugNotificationButton(
                        icon: "newspaper.fill",
                        color: .purple,
                        title: "New Blog",
                        subtitle: "Simulate new blog post notification"
                    ) {
                        NotificationTestHelper.simulateNewBlog()
                        showToast("Notification saved & scheduled in 3s")
                        Task { await loadNotifications() }
                    }
                }
                .padding(.horizontal)
            }
        }

        private func debugNotificationButton(
            icon: String,
            color: Color,
            title: String,
            subtitle: String,
            action: @escaping () -> Void
        ) -> some View {
            Button(action: action) {
                HStack(spacing: 14) {
                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundStyle(color)
                        .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .glassEffect(in: .rect(cornerRadius: 16))
        }

        private var toastView: some View {
            Text(toastMessage)
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(radius: 4)
        }

        private func showToast(_ message: String) {
            toastMessage = message
            withAnimation { showTestToast = true }
            Task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation { showTestToast = false }
            }
        }
    #endif

    // MARK: - Actions
    private func loadNotifications() async {
        isLoading = true
        defer { isLoading = false }
        notifications =
            (try? await NotificationService.shared.fetchNotifications()) ?? []
        await updateAppBadge()
    }

    private func markAsRead(_ item: AppNotification) async {
        guard let id = item.id else { return }
        await NotificationService.shared.markAsRead(id)
        if let index = notifications.firstIndex(where: { $0.id == id }) {
            notifications[index].isRead = true
        }
        await updateAppBadge()
    }

    private func markAllAsRead() async {
        let unread = notifications.filter { !$0.isRead }
        await withTaskGroup(of: Void.self) { group in
            for item in unread {
                guard let id = item.id else { continue }
                group.addTask {
                    await NotificationService.shared.markAsRead(id)
                }
            }
        }
        for index in notifications.indices {
            notifications[index].isRead = true
        }
        await updateAppBadge()
    }

    private func deleteAllNotifications() async {
        await NotificationService.shared.deleteAllNotifications()
        notifications = []
        await updateAppBadge()
    }

    // Update the app icon badge to match the current unread count
    private func updateAppBadge() async {
        let count = notifications.filter { !$0.isRead }.count
        try? await UNUserNotificationCenter.current().setBadgeCount(count)
    }
}

// MARK: - NotificationRow
struct NotificationRow: View {
    let item: AppNotification
    let onTap: () -> Void

    private var iconName: String {
        switch item.notificationType {
        case .graded: return "checkmark.seal.fill"
        case .newQuestion: return "doc.text.fill"
        case .reminder: return "flame.fill"
        }
    }

    private var iconColor: Color {
        switch item.notificationType {
        case .graded: return item.isRead ? .secondary : .green
        case .newQuestion: return item.isRead ? .secondary : .blue
        case .reminder: return item.isRead ? .secondary : .orange
        }
    }

    // Show "HH:mm" for today, "Yesterday HH:mm" for yesterday, "dd/MM HH:mm" for older
    private var formattedTime: String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        if calendar.isDateInToday(item.createdAt) {
            formatter.dateFormat = "HH:mm"
        } else if calendar.isDateInYesterday(item.createdAt) {
            formatter.dateFormat = "'Yesterday' HH:mm"
        } else {
            formatter.dateFormat = "dd/MM HH:mm"
        }
        return formatter.string(from: item.createdAt)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: iconName)
                    .font(.system(size: 26))
                    .foregroundStyle(iconColor)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .font(
                                .system(
                                    size: 15,
                                    weight: item.isRead ? .regular : .semibold
                                )
                            )
                            .foregroundStyle(.primary)

                        if !item.isRead {
                            Circle()
                                .fill(.blue)
                                .frame(width: 7, height: 7)
                        }
                    }

                    Text(item.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(formattedTime)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .opacity(item.isRead ? 0.7 : 1.0)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SearchResultRow
struct SearchResultRow: View {

    let question: VSTEPQuestion
    @Environment(StoreKitManager.self) private var store  // Them dong nay

    private var taskColor: Color {
        question.taskType == "task1" ? BrandColor.light : BrandColor.medium
    }

    private var taskIcon: String {
        question.taskType == "task1" ? "chart.bar.fill" : "text.bubble.fill"
    }

    private var difficultyColor: Color {
        switch question.difficulty.lowercased() {
        case "easy": return .green
        case "medium": return .orange
        case "hard": return .red
        default: return .secondary
        }
    }

    var body: some View {
        NavigationLink(
            destination: QuestionDetailView(
                question: question,
                questionNumber: 0,
                latestSubmission: nil,
                submissionHistory: [],
                store: store  // Them dong nay
            )
        ) {
            HStack(spacing: 14) {
                Image(systemName: taskIcon)
                    .font(.system(size: 26))
                    .foregroundStyle(taskColor)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(question.title)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        BadgeLabel(
                            text: question.taskType == "task1"
                                ? "Task 1" : "Task 2",
                            color: taskColor
                        )
                        BadgeLabel(
                            text: question.difficulty.capitalized,
                            color: difficultyColor
                        )
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}
