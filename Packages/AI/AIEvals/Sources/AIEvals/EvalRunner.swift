import AIKit
import Foundation

/// Report produced by an eval run.
public struct EvalReport: Sendable {
    public struct ThreadResult: Sendable {
        public let threadID: String
        public let brief: AIThreadBrief?
        public let error: String?
        public let latencySeconds: Double
        public let schemaValid: Bool
        public let faithfulness: Double?
        public let hallucinationRate: Double?
    }

    public let results: [ThreadResult]
    public let totalThreads: Int
    public let successCount: Int
    public let schemaValidityRate: Double
    public let meanFaithfulness: Double
    public let meanHallucinationRate: Double
    public let p50Latency: Double
    public let p95Latency: Double

    /// Render a markdown summary of the eval run.
    public func markdownReport() -> String {
        var lines: [String] = []
        lines.append("# AIEvals — Thread Brief Baseline Report")
        lines.append("")
        lines.append("| Metric | Value |")
        lines.append("|---|---|")
        lines.append("| Threads evaluated | \(totalThreads) |")
        lines.append("| Successful | \(successCount) |")
        lines.append("| Schema validity | \(pct(schemaValidityRate)) |")
        lines.append("| Mean faithfulness | \(String(format: "%.3f", meanFaithfulness)) |")
        lines.append("| Mean hallucination rate | \(pct(meanHallucinationRate)) |")
        lines.append("| p50 latency | \(String(format: "%.2f", p50Latency))s |")
        lines.append("| p95 latency | \(String(format: "%.2f", p95Latency))s |")
        lines.append("")
        lines.append("## Per-thread results")
        lines.append("")
        lines.append("| Thread | Latency | Schema | Faithfulness | Hallucination | Error |")
        lines.append("|---|---|---|---|---|---|")
        for r in results {
            let lat = String(format: "%.2fs", r.latencySeconds)
            let sch = r.schemaValid ? "ok" : "FAIL"
            let faith = r.faithfulness.map { String(format: "%.3f", $0) } ?? "—"
            let hall = r.hallucinationRate.map { pct($0) } ?? "—"
            let err = r.error ?? ""
            lines.append("| \(r.threadID) | \(lat) | \(sch) | \(faith) | \(hall) | \(err) |")
        }
        return lines.joined(separator: "\n")
    }

    private func pct(_ v: Double) -> String {
        String(format: "%.1f%%", v * 100)
    }
}

/// Runs the AI service against a corpus of threads and produces an eval report.
public struct EvalRunner: Sendable {

    public init() {}

    public func run(
        corpus: [(id: String, input: AIThreadInput)],
        service: any AIService
    ) async throws -> EvalReport {
        var threadResults: [EvalReport.ThreadResult] = []

        for (id, input) in corpus {
            let start = ContinuousClock.now
            var brief: AIThreadBrief?
            var errorMsg: String?

            do {
                brief = try await service.threadBrief(input)
            } catch {
                let errStr = String(describing: error)
                errorMsg = errStr.count > 200 ? String(errStr.prefix(200)) + "…" : errStr
            }

            let elapsed = start.duration(to: .now)
            let latency = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18

            let schemaValid = brief != nil
            let faithfulness: Double? = brief.map { Metrics.faithfulness(brief: $0, input: input) }
            let hallucinationRate: Double? = brief.map { Metrics.hallucinationRate(brief: $0, input: input) }

            threadResults.append(.init(
                threadID: id,
                brief: brief,
                error: errorMsg,
                latencySeconds: latency,
                schemaValid: schemaValid,
                faithfulness: faithfulness,
                hallucinationRate: hallucinationRate
            ))
        }

        let latencies = threadResults.map(\.latencySeconds).sorted()
        let successCount = threadResults.filter(\.schemaValid).count
        let schemaRate = latencies.isEmpty ? 0 : Double(successCount) / Double(threadResults.count)
        let faithValues = threadResults.compactMap(\.faithfulness)
        let hallValues = threadResults.compactMap(\.hallucinationRate)

        return EvalReport(
            results: threadResults,
            totalThreads: threadResults.count,
            successCount: successCount,
            schemaValidityRate: schemaRate,
            meanFaithfulness: faithValues.isEmpty ? 0 : faithValues.reduce(0, +) / Double(faithValues.count),
            meanHallucinationRate: hallValues.isEmpty ? 0 : hallValues.reduce(0, +) / Double(hallValues.count),
            p50Latency: percentile(latencies, 0.50),
            p95Latency: percentile(latencies, 0.95)
        )
    }
}

private func percentile(_ sorted: [Double], _ p: Double) -> Double {
    guard !sorted.isEmpty else { return 0 }
    let index = p * Double(sorted.count - 1)
    let lower = Int(index)
    let upper = min(lower + 1, sorted.count - 1)
    let fraction = index - Double(lower)
    return sorted[lower] + fraction * (sorted[upper] - sorted[lower])
}
