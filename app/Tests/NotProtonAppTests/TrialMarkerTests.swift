import Foundation
import Testing

@testable import NotProtonApp

// The run script trusts this file at every launch, so what it holds has to match what
// compat_run.sh reads: whole epoch seconds, and anything else counted as ended.
@Suite("Trial marker")
struct TrialMarkerTests {

    private func runners() throws -> URL {
        let dir = URL.temporaryDirectory.appending(path: "np-trial-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("The end is written as whole seconds beside the clone and read back")
    func roundTrip() throws {
        let runners = try runners()
        defer { try? FileManager.default.removeItem(at: runners) }
        let expires = Date(timeIntervalSince1970: 1_900_000_000.75)

        try TrialMarker.record(expires, build: "27.0.0.41073", runners: runners)

        let file = SupportPaths.runnerRoot(forBuild: "27.0.0.41073", runners: runners)
            .appending(path: "notproton-trial")
        #expect(try String(contentsOf: file, encoding: .utf8) == "1900000000\n")
        #expect(TrialMarker.expiry(forBuild: "27.0.0.41073", runners: runners)
            == Date(timeIntervalSince1970: 1_900_000_000))
    }

    @Test("A paid license removes the marker, and a build without one has no trial")
    func paidRemovesTheMarker() throws {
        let runners = try runners()
        defer { try? FileManager.default.removeItem(at: runners) }

        try TrialMarker.record(Date(), build: "26.3.0.39832", runners: runners)
        try TrialMarker.record(nil, build: "26.3.0.39832", runners: runners)
        #expect(TrialMarker.expiry(forBuild: "26.3.0.39832", runners: runners) == nil)
        // Clearing with no marker present is not an error.
        try TrialMarker.record(nil, build: "26.3.0.39832", runners: runners)
    }

    @Test("A marker that is not a number reads as a trial that has ended")
    func unreadableMarkerHasEnded() throws {
        let runners = try runners()
        defer { try? FileManager.default.removeItem(at: runners) }
        let file = TrialMarker.url(forBuild: "27.0.0.41073", runners: runners)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        for text in ["", "tomorrow", "-5"] {
            try text.write(to: file, atomically: true, encoding: .utf8)
            #expect(TrialMarker.expiry(forBuild: "27.0.0.41073", runners: runners) == .distantPast)
        }
    }

    @Test("Only builds with a marker are listed")
    func listsMarkedBuilds() throws {
        let runners = try runners()
        defer { try? FileManager.default.removeItem(at: runners) }
        let expires = Date(timeIntervalSince1970: 1_900_000_000)
        try TrialMarker.record(expires, build: "27.0.0.41073", runners: runners)

        let found = TrialMarker.all(builds: ["27.0.0.41073", "26.3.0.39832"], runners: runners)
        #expect(found == ["27.0.0.41073": expires])
    }
}
