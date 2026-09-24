import AppKit
import Foundation

/// Installs an update in place. Because the builds are not notarized, Forelight
/// replaces its own bundle and relaunches instead of using a framework updater.
enum UpdateInstaller {
    /// Downloads and unpacks a release zip, returning the new .app in a temp dir.
    static func download(_ url: URL) async throws -> URL {
        let (temporaryURL, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.badResponse
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForelightUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let zipURL = directory.appendingPathComponent("update.zip")
        try FileManager.default.moveItem(at: temporaryURL, to: zipURL)

        try await run("/usr/bin/ditto", ["-x", "-k", zipURL.path, directory.path])

        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        guard let app = contents.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.extractionFailed
        }
        return app
    }

    /// Whether Forelight can replace its own bundle (the folder must be writable).
    static func canInstall(into target: URL) -> Bool {
        let parent = target.deletingLastPathComponent()
        return FileManager.default.isWritableFile(atPath: parent.path)
    }

    /// Waits for this process to exit, swaps the bundle, clears quarantine, and
    /// relaunches. The caller should terminate right after.
    static func installAndRelaunch(newApp: URL, target: URL) throws {
        let script = """
        #!/bin/sh
        set -e
        APP="$1"
        NEW="$2"
        PID="$3"
        PARENT="$(dirname "$APP")"
        STAGE="$PARENT/.Forelight-update.app"
        TRASH="$HOME/.Trash/Forelight-$(date +%s).app"

        for _ in $(seq 1 100); do
            kill -0 "$PID" 2>/dev/null || break
            sleep 0.1
        done

        rm -rf "$STAGE"
        ditto "$NEW" "$STAGE"
        xattr -dr com.apple.quarantine "$STAGE" 2>/dev/null || true

        if [ -d "$APP" ]; then
            mkdir -p "$HOME/.Trash"
            mv "$APP" "$TRASH" 2>/dev/null || rm -rf "$APP"
        fi
        mv "$STAGE" "$APP"
        open "$APP"
        """

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("forelight-update-\(UUID().uuidString).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            scriptURL.path,
            target.path,
            newApp.path,
            String(ProcessInfo.processInfo.processIdentifier)
        ]
        try process.run()
    }

    private static func run(_ launchPath: String, _ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = arguments
            process.terminationHandler = { finished in
                if finished.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: UpdateError.extractionFailed)
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
