import Combine
import Sparkle
import SwiftUI

/// Thin wrapper around Sparkle's `SPUStandardUpdaterController` that
/// exposes an observable `canCheckForUpdates` flag for SwiftUI menu
/// item enablement.
@MainActor @Observable
final class SparkleUpdater {

    var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var cancellable: AnyCancellable?

    init() {
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
