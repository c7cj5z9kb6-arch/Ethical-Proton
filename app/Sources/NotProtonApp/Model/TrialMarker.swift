// Records, beside a cloned runner, when the trial it was set up under ends. The clone
// never asks CrossOver again, so the run script reads this at every launch instead.

import Foundation

enum TrialMarker {

    // compat_run.sh reads the same name beside $CX_ROOT.
    static let fileName = "notproton-trial"

    static func url(forBuild build: String, runners: URL = SupportPaths.runners) -> URL {
        SupportPaths.runnerRoot(forBuild: build, runners: runners).appending(path: fileName)
    }

    // A nil expiry is a paid license, which leaves no marker behind.
    static func record(_ expires: Date?, build: String, runners: URL = SupportPaths.runners) throws {
        let file = url(forBuild: build, runners: runners)
        guard let expires else {
            if FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: file)
            }
            return
        }
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        // Whole seconds, rounded down, so the run script never outlasts the trial.
        let seconds = Int(expires.timeIntervalSince1970.rounded(.down))
        try "\(seconds)\n".write(to: file, atomically: true, encoding: .utf8)
    }

    // A marker that cannot be read is treated as a trial that has ended, as the run script does.
    static func expiry(forBuild build: String, runners: URL = SupportPaths.runners) -> Date? {
        let file = url(forBuild: build, runners: runners)
        guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { return nil }
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        guard let seconds = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)), seconds >= 0 else {
            return .distantPast
        }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    static func all(builds: [String], runners: URL = SupportPaths.runners) -> [String: Date] {
        var found: [String: Date] = [:]
        for build in builds {
            if let date = expiry(forBuild: build, runners: runners) { found[build] = date }
        }
        return found
    }
}
