import SwiftUI
import AVFoundation

// MARK: - Secret Camera Capture
/// Camera wrapper that captures photos and videos directly into the vault.
struct SecretCameraCapture: UIViewControllerRepresentable {
    let onCapturedPhoto: (UIImage) -> Void
    let onCapturedVideo: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.image", "public.movie"]
        picker.videoMaximumDuration = 300 // 5 minutes max
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: SecretCameraCapture

        init(parent: SecretCameraCapture) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.dismiss()

            if let image = info[.originalImage] as? UIImage {
                DispatchQueue.main.async {
                    self.parent.onCapturedPhoto(image)
                }
            } else if let videoURL = info[.mediaURL] as? URL {
                // Copy to temp so the original isn't cleaned up before we save
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + ".mov")
                try? FileManager.default.copyItem(at: videoURL, to: tempURL)
                DispatchQueue.main.async {
                    self.parent.onCapturedVideo(tempURL)
                }
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
