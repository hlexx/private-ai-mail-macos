import Foundation

actor RateLimiter {
    private let maxUnitsPerSecond: Int
    private var timestamps: [ContinuousClock.Instant] = []

    init(maxUnitsPerSecond: Int = 250) {
        self.maxUnitsPerSecond = maxUnitsPerSecond
    }

    func acquire(units: Int = 1) async {
        let now = ContinuousClock.now
        let windowStart = now - .seconds(1)
        timestamps.removeAll { $0 < windowStart }

        while timestamps.count + units > maxUnitsPerSecond {
            try? await Task.sleep(for: .milliseconds(50))
            let refreshed = ContinuousClock.now
            let refreshedStart = refreshed - .seconds(1)
            timestamps.removeAll { $0 < refreshedStart }
        }

        let acquired = ContinuousClock.now
        for _ in 0..<units {
            timestamps.append(acquired)
        }
    }
}
