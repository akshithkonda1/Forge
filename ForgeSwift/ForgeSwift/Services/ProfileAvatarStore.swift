import SwiftUI
import UIKit
import Combine

/// On-device storage for the user's profile photo.
///
/// The image lives as a JPEG in Application Support rather than in `UserDefaults`, because
/// the profile is encoded to defaults on every mutation and a base64 photo would be
/// re-serialised on each keystroke of the name field. `UserProfile` keeps only the filename.
@MainActor
final class ProfileAvatarStore: ObservableObject {
    static let shared = ProfileAvatarStore()

    /// Bumped whenever the stored image changes so SwiftUI re-reads it.
    @Published private(set) var revision = 0

    /// Longest edge of the stored image. Big enough for a Retina hero, small enough that
    /// writing it is instant.
    private static let maxDimension: CGFloat = 1024
    private static let compressionQuality: CGFloat = 0.85
    private static let directoryName = "ProfileAvatars"

    private var cache: [String: UIImage] = [:]

    private init() {}

    private var directory: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = base.appendingPathComponent(Self.directoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func url(for fileName: String) -> URL? {
        // Defend against a filename from persisted state escaping the directory.
        let safe = fileName.replacingOccurrences(of: "/", with: "")
        guard !safe.isEmpty, safe != ".", safe != ".." else { return nil }
        return directory?.appendingPathComponent(safe)
    }

    // MARK: Read

    func image(named fileName: String?) -> UIImage? {
        guard let fileName, !fileName.isEmpty else { return nil }
        if let cached = cache[fileName] { return cached }
        guard let url = url(for: fileName),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        cache[fileName] = image
        return image
    }

    // MARK: Write

    /// Saves `image` and returns the new filename, or `nil` if it could not be written.
    /// A fresh filename is used every time so no view can serve a stale cached file.
    @discardableResult
    func save(_ image: UIImage, replacing previous: String?) -> String? {
        let resized = Self.downscaled(image, maxDimension: Self.maxDimension)
        guard let data = resized.jpegData(compressionQuality: Self.compressionQuality) else { return nil }
        let fileName = "avatar-\(UUID().uuidString).jpg"
        guard let url = url(for: fileName) else { return nil }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        // Only remove the old file once the new one is safely on disk.
        if let previous, previous != fileName { delete(previous) }
        cache[fileName] = resized
        revision &+= 1
        return fileName
    }

    func delete(_ fileName: String?) {
        guard let fileName, !fileName.isEmpty else { return }
        cache.removeValue(forKey: fileName)
        if let url = url(for: fileName) {
            try? FileManager.default.removeItem(at: url)
        }
        revision &+= 1
    }

    // MARK: Helpers

    /// Scales down while preserving aspect ratio, and normalises orientation so a photo
    /// taken in portrait doesn't render sideways.
    static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longestEdge = max(image.size.width, image.size.height)
        let scale = longestEdge > maxDimension ? maxDimension / longestEdge : 1
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

// MARK: - Avatar view

/// The user's photo when they have one, initials when they don't. Used everywhere an
/// avatar appears so the two never disagree.
struct ProfileAvatarView: View {
    let fileName: String?
    let initials: String
    var size: CGFloat = 92
    var showsRing: Bool = true

    @ObservedObject private var avatars = ProfileAvatarStore.shared

    var body: some View {
        ZStack {
            if let image = avatars.image(named: fileName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(LinearGradient.emberGradient)
                    .frame(width: size, height: size)
                Text(initials.isEmpty ? "?" : initials)
                    .font(.system(size: size * 0.37, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            if showsRing {
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [.emberLight, .ember, .emberDark, .ember, .emberLight],
                            center: .center
                        ),
                        lineWidth: 2.5
                    )
                    .frame(width: size + 8, height: size + 8)
            }
        }
        // Without this the identity change from the revision counter is the only thing
        // that forces SwiftUI to re-read the file after a new photo is saved.
        .id("\(fileName ?? "none")-\(avatars.revision)")
        .accessibilityHidden(true)
    }
}
