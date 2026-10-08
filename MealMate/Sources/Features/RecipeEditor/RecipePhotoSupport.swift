import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Prepares photos for upload: downsampled JPEG, small enough for a quick upload
/// but big enough for Mealie's `original` variant.
enum RecipePhotoEncoder {
    /// Longest edge of uploaded photos, in pixels.
    static let maxPixelSize = 2048

    /// Decodes any image format ImageIO knows (HEIC, PNG, JPEG, ...), applies the
    /// EXIF orientation, downsamples and re-encodes as JPEG. Off the main actor.
    nonisolated static func jpegData(from data: Data, maxPixelSize: Int = maxPixelSize, quality: CGFloat = 0.82) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    nonisolated static func jpegData(from image: UIImage, quality: CGFloat = 0.82) -> Data? {
        guard let data = image.jpegData(compressionQuality: 1) else { return nil }
        return jpegData(from: data, quality: quality)
    }
}

/// Camera capture (`UIImagePickerController`), for "Take Photo" in the editor.
/// Only offered when the device has a camera.
struct CameraPicker: UIViewControllerRepresentable {
    var onPick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onPick(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
