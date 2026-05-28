import SwiftUI
import PhotosUI

// MARK: - Secret Media Picker
/// A PHPicker wrapper that lets users pick multiple photos and videos
/// from their photo library to import into the secret vault.
struct SecretMediaPicker: UIViewControllerRepresentable {
    let onPickedPhotos: ([UIImage]) -> Void
    let onPickedVideos: ([URL]) -> Void
    let onAssetIdentifiers: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 50 // Allow batch import
        config.filter = .any(of: [.images, .videos])
        config.preferredAssetRepresentationMode = .current
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: SecretMediaPicker
        
        init(parent: SecretMediaPicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            
            guard !results.isEmpty else { return }

            var images: [UIImage] = []
            var videoURLs: [URL] = []
            let assetIdentifiers = results.compactMap { $0.assetIdentifier }
            let group = DispatchGroup()

            for result in results {
                let provider = result.itemProvider
                
                if provider.hasItemConformingToTypeIdentifier("public.movie") {
                    group.enter()
                    provider.loadFileRepresentation(forTypeIdentifier: "public.movie") { url, error in
                        defer { group.leave() }
                        guard let url = url else { return }
                        
                        // Copy to a temp location since the provided URL is temporary
                        let tempDir = FileManager.default.temporaryDirectory
                        let tempURL = tempDir.appendingPathComponent(UUID().uuidString + "." + url.pathExtension)
                        try? FileManager.default.copyItem(at: url, to: tempURL)
                        videoURLs.append(tempURL)
                    }
                } else if provider.canLoadObject(ofClass: UIImage.self) {
                    group.enter()
                    provider.loadObject(ofClass: UIImage.self) { object, error in
                        defer { group.leave() }
                        if let image = object as? UIImage {
                            images.append(image)
                        }
                    }
                }
            }
            
            group.notify(queue: .main) { [weak self] in
                if !images.isEmpty {
                    self?.parent.onPickedPhotos(images)
                }
                if !videoURLs.isEmpty {
                    self?.parent.onPickedVideos(videoURLs)
                }
                if !assetIdentifiers.isEmpty {
                    self?.parent.onAssetIdentifiers(assetIdentifiers)
                }
            }
        }
    }
}
