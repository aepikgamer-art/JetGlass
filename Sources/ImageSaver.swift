import Foundation
import Photos
import UIKit

/// Downloads a jet photo and saves it to the user's photo library.
final class ImageSaver: NSObject {
    enum SaveError: LocalizedError {
        case badURL
        case downloadFailed
        case permissionDenied

        var errorDescription: String? {
            switch self {
            case .badURL: return "Couldn't build a valid image URL."
            case .downloadFailed: return "Download failed — check your connection and try again."
            case .permissionDenied: return "Photo library access was denied. Enable it in Settings."
            }
        }
    }

    static func save(from urlString: String?) async throws {
        guard let urlString, let url = URL(string: urlString) else { throw SaveError.badURL }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.permissionDenied }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw SaveError.downloadFailed
        }
        guard let image = UIImage(data: data) else { throw SaveError.downloadFailed }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }
}
