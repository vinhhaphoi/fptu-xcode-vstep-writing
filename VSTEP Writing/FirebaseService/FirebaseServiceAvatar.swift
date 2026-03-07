import FirebaseFirestore
import FirebaseStorage
import Foundation
import UIKit

extension FirebaseService {

    // MARK: - Upload Avatar
    // Storage path: avatars/{uid}/avatar.jpg
    func uploadAvatar(
        image: UIImage,
        maxSizeInPixels: CGFloat = 512,
        compressionQuality: CGFloat = 0.7
    ) async throws -> String {
        guard let uid = currentUserId else {
            throw AvatarUploadError.noCurrentUser
        }

        let resized = resizeImage(image, maxDimension: maxSizeInPixels)

        guard
            let imageData = resized.jpegData(
                compressionQuality: compressionQuality
            )
        else {
            throw AvatarUploadError.imageCompressionFailed
        }

        let sizeKB = Double(imageData.count) / 1024
        print(
            "[FirebaseService] Avatar size: \(String(format: "%.1f", sizeKB)) KB"
        )

        let storageRef = storage.reference().child("avatars/\(uid)/avatar.jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        do {
            _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
        } catch {
            throw AvatarUploadError.uploadFailed(error)
        }

        let downloadURL: URL
        do {
            downloadURL = try await storageRef.downloadURL()
        } catch {
            throw AvatarUploadError.downloadURLFailed(error)
        }

        let urlString = downloadURL.absoluteString

        do {
            try await db.collection("users").document(uid)
                .updateData(["photoURL": urlString])
        } catch {
            throw AvatarUploadError.firestoreUpdateFailed(error)
        }

        uploadedAvatarURL = urlString
        return urlString
    }

    // MARK: - Delete Avatar
    func deleteAvatar() async throws {
        guard let uid = currentUserId else {
            throw AvatarUploadError.noCurrentUser
        }

        let storageRef = storage.reference().child("avatars/\(uid)/avatar.jpg")
        try await storageRef.delete()
        uploadedAvatarURL = nil
        print("[FirebaseService] Avatar deleted for uid: \(uid)")
    }

    // MARK: - Fetch Avatar URL
    func fetchAvatarURL() async {
        guard let uid = currentUserId else { return }
        let doc = try? await db.collection("users").document(uid).getDocument()
        if let urlString = doc?.data()?["photoURL"] as? String {
            uploadedAvatarURL = urlString
        }
    }

    // MARK: - Private Helper
    // Keeps aspect ratio, only downscales never upscales
    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage
    {
        let originalSize = image.size
        let maxSide = max(originalSize.width, originalSize.height)
        guard maxSide > maxDimension else { return image }

        let scale = maxDimension / maxSide
        let newSize = CGSize(
            width: (originalSize.width * scale).rounded(),
            height: (originalSize.height * scale).rounded()
        )

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
