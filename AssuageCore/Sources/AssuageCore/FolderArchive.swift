import Foundation

/// Archives a folder into a single `.zip` so it can be encrypted as one file.
///
/// Uses `NSFileCoordinator`'s upload coordination — the same mechanism AirDrop
/// and Mail use to send a folder — so there's no third-party dependency and the
/// result is an ordinary zip that Finder expands on double-click, even for a
/// recipient who decrypts with the plain `age` tool and has no copy of this app.
///
/// age encrypts a single byte stream, not a directory tree, so a folder has to
/// become one file first. Zipping happens on the input side only: on decrypt we
/// hand back the `.zip` untouched (we don't unpack it), so nothing app-specific
/// is embedded in the ciphertext.
public enum FolderArchive {
    /// Zip `folder` into a temporary `.zip` and return its URL. The returned file
    /// lives in a fresh temporary directory the caller owns and should delete when
    /// done (see `cleanUp(_:)`).
    ///
    /// Blocking I/O — call off the main actor.
    ///
    /// - Throws: the coordination error, or `AssuageError.ioFailure` if the
    ///   archive can't be copied out of the coordinator's scratch location.
    public static func zip(_ folder: URL) throws -> URL {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<URL, any Error> = .failure(AssuageError.ioFailure)

        // `.forUploading` yields a zip of the directory in a temporary location
        // that is valid only for the duration of the accessor block, so copy it
        // out to a location we control before returning.
        coordinator.coordinate(
            readingItemAt: folder, options: [.forUploading], error: &coordinationError
        ) { zippedURL in
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent(folder.lastPathComponent, isDirectory: false)
                .appendingPathExtension("zip")
            do {
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try FileManager.default.copyItem(at: zippedURL, to: destination)
                result = .success(destination)
            } catch {
                result = .failure(error)
            }
        }

        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    /// Remove a temporary archive (and its enclosing scratch directory) produced
    /// by `zip(_:)`. Best-effort; failures are ignored.
    public static func cleanUp(_ archive: URL) {
        try? FileManager.default.removeItem(at: archive.deletingLastPathComponent())
    }
}
