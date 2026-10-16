// Checks whether the user's CrossOver install is licensed.
// CodeWeavers, I hope this doesn't bother you. You don't validate
// license when the Wine binary itself is invoked, so I wanted to
// do something to prevent skids from doing really trivial piracy.
//
// An active CrossOver trial is accepted too. The clone made under it carries a
// TrialMarker, and the run script refuses to launch from it once the trial ends.

import Foundation

enum CrossOverLicense {

    struct Status: Sendable {
        // Whether a runner may be set up: a paid license verified, or a trial is active.
        let licensed: Bool
        let detail: String
        // The real reason, for the log.
        let diagnostic: String
        // Set only when licensed comes from an active trial, never for a paid license.
        var trialExpires: Date? = nil

        var isTrial: Bool { trialExpires != nil }
    }

    // What CrossOver reports about its own evaluation period.
    enum TrialReading: Sendable, Equatable {
        case notFound
        case active(expires: Date)
        case ended(expired: Date?)
    }

    typealias TrialSource = @Sendable (_ crossOverRoot: URL) -> TrialReading

    // How CrossOver records its trial has not been read off a real install yet. Until a
    // reader for it lands here, no trial is found and only a paid license is accepted.
    static let defaultTrialSource: TrialSource = { _ in .notFound }

    static let defaultSearchDirs: [URL] = {
        let home = URL(filePath: NSHomeDirectory())
        return [
            home.appending(path: "Library/Preferences"),
            URL(filePath: "/Library/Preferences"),
        ]
    }()

    private static let licenseBase = "com.codeweavers.CrossOver"

    static let notActivatedTitle = String(localized: "CrossOver does not appear to be activated.")
    static let notActivatedAdvice = String(localized: "Please run CrossOver and try again.")
    static var notActivated: String { "\(notActivatedTitle) \(notActivatedAdvice)" }

    static let trialEndedTitle = String(localized: "The CrossOver trial has ended.")
    static let trialEndedAdvice = String(localized: "Purchase CrossOver to keep using it with NotProton.")
    static var trialEnded: String { "\(trialEndedTitle) \(trialEndedAdvice)" }

    static func trialActive(until date: Date) -> String {
        let day = date.formatted(date: .abbreviated, time: .omitted)
        return String(localized: "CrossOver trial is active until \(day).")
    }

    static let defaultOpenssl = "/usr/bin/openssl"

    static func check(
        crossOverRoot: URL,
        searchDirs: [URL] = defaultSearchDirs,
        openssl: String = defaultOpenssl,
        trialSource: TrialSource = defaultTrialSource,
        now: Date = Date()
    ) -> Status {
        let paid = evaluate(
            crossOverRoot: crossOverRoot, searchDirs: searchDirs, openssl: openssl
        )
        // A paid license wins, so a trial left behind after purchase changes nothing.
        let status = paid.licensed
            ? paid
            : withTrial(paid, reading: trialSource(crossOverRoot), now: now)
        AppLog.note("license: \(status.diagnostic)")
        return status
    }

    private static func withTrial(_ paid: Status, reading: TrialReading, now: Date) -> Status {
        switch reading {
        case .notFound:
            return paid
        case .active(let expires) where expires > now:
            return Status(
                licensed: true,
                detail: trialActive(until: expires),
                diagnostic: "\(paid.diagnostic); trial active until \(expires.ISO8601Format())",
                trialExpires: expires
            )
        case .active(let expires), .ended(let expires?):
            return Status(
                licensed: false,
                detail: trialEnded,
                diagnostic: "\(paid.diagnostic); trial ended \(expires.ISO8601Format())"
            )
        case .ended(nil):
            return Status(
                licensed: false, detail: trialEnded, diagnostic: "\(paid.diagnostic); trial ended"
            )
        }
    }

    private static func evaluate(
        crossOverRoot: URL,
        searchDirs: [URL],
        openssl: String
    ) -> Status {
        let keyFile = crossOverRoot.appending(
            path: "share/crossover/data/tie.pub"
        ).path(percentEncoded: false)

        guard FileManager.default.fileExists(atPath: keyFile) else {
            return Status(
                licensed: false,
                detail: notActivated,
                diagnostic: "no verification key in the CrossOver bundle"
            )
        }

        var rejection: String?

        for dir in searchDirs {
            let label = dir.path(percentEncoded: false)
            let license = dir.appending(path: "\(licenseBase).license")
                .path(percentEncoded: false)

            guard FileManager.default.fileExists(atPath: license) else { continue }

            let signatures = sidecars(in: dir)
            guard !signatures.isEmpty else {
                rejection = "the license in \(label) has no signature beside it"
                continue
            }

            var unchecked: String?

            for signature in signatures {
                let result: CommandResult
                do {
                    result = try Shell.run(openssl, [
                        "dgst", signature.digest, "-verify", keyFile,
                        "-signature", signature.path, license,
                    ])
                } catch {
                    return Status(
                        licensed: false,
                        detail: notActivated,
                        diagnostic: "could not run \(openssl) to verify the license"
                    )
                }

                if result.succeeded {
                    return Status(
                        licensed: true,
                        detail: String(localized: "CrossOver is activated."),
                        diagnostic: "valid license in \(label)"
                    )
                }

                let trouble = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trouble.isEmpty {
                    if trouble.localizedCaseInsensitiveContains("unable to load key") {
                        return Status(
                            licensed: false,
                            detail: notActivated,
                            diagnostic: "the verification key in the CrossOver bundle could not be read"
                        )
                    }
                    unchecked = "the license in \(label) could not be checked"
                }
            }

            rejection = unchecked
                ?? "no signature beside the license in \(label) verified against this bundle"
        }

        return Status(
            licensed: false,
            detail: notActivated,
            diagnostic: rejection ?? "no CrossOver license file found"
        )
    }

    static func requireValid(for install: CrossOverInstall) throws {
        let status = check(crossOverRoot: install.crossOverRoot)
        guard status.licensed else {
            throw StepFailure(
                step: String(localized: "Verify CrossOver license"),
                detail: status.detail
            )
        }
    }

    private static func sidecars(in dir: URL) -> [(path: String, digest: String)] {
        let candidates: [(path: String, digest: String)] = [
            (dir.appending(path: "\(licenseBase).sha256").path(percentEncoded: false), "-sha256"),
            (dir.appending(path: "\(licenseBase).sig").path(percentEncoded: false), "-sha1"),
        ]
        return candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
