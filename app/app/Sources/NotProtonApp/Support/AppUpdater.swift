import Sparkle

@MainActor
final class AppUpdater {

    private let controller: SPUStandardUpdaterController

    init() {
        // Ferry is a private fork with no update feed (Info.plist SUFeedURL is empty): never
        // start Sparkle, so it can neither nag about a missing feed nor update to upstream.
        let scheduling = false
        controller = SPUStandardUpdaterController(
            startingUpdater: scheduling,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func check() {
        // no update feed in the Ferry fork
    }
}
