// NotificationTestHelper.swift - CHI DUNG CHO DEBUG, xoa truoc khi release

#if DEBUG
    import UserNotifications

    struct NotificationTestHelper {
        static func simulateEssayGraded(essayId: String = "essay-456") {
            let content = UNMutableNotificationContent()
            content.title = "Bài essay đã được chấm"
            content.body = "Giáo viên vừa chấm xong bài Writing Task 2!"
            content.sound = .default
            content.badge = 1
            content.userInfo = [
                "event_type": "essay_graded",
                "essay_id": essayId,
            ]
            // Save to Firestore immediately so history is recorded before user taps
            saveAndSchedule(content: content, identifier: "test_essay_graded")
            print(
                "[NotificationTest] Essay graded notification scheduled in 3s"
            )
        }

        static func simulateNewAssignment(assignmentId: String = "hw-789") {
            let content = UNMutableNotificationContent()
            content.title = "Bài tập mới"
            content.body = "Giáo viên vừa giao bài Grammar Unit 5"
            content.sound = .default
            content.userInfo = [
                "event_type": "new_assignment",
                "assignment_id": assignmentId,
            ]
            saveAndSchedule(content: content, identifier: "test_new_assignment")
            print(
                "[NotificationTest] New assignment notification scheduled in 3s"
            )
        }

        static func simulateNewBlog(blogId: String = "blog-123") {
            let content = UNMutableNotificationContent()
            content.title = "Blog mới"
            content.body = "Có bài viết mới: Tips for VSTEP Writing Task 2"
            content.sound = .default
            content.userInfo = [
                "event_type": "new_blog",
                "blog_id": blogId,
            ]
            saveAndSchedule(content: content, identifier: "test_new_blog")
            print("[NotificationTest] New blog notification scheduled in 3s")
        }

        // Save to Firestore + schedule local notification
        private static func saveAndSchedule(
            content: UNMutableNotificationContent,
            identifier: String
        ) {
            Task {
                await NotificationService.shared.saveNotificationHistory(
                    title: content.title,
                    body: content.body,
                    userInfo: content.userInfo
                )
                // Notify TabBarView to refresh unread badge count
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .didSaveLocalNotification,
                        object: nil
                    )
                }
            }

            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(
                    withIdentifiers: [identifier]
                )
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: 3,
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print(
                        "[NotificationTest] Schedule error \(identifier): \(error.localizedDescription)"
                    )
                }
            }
        }
    }
#endif
