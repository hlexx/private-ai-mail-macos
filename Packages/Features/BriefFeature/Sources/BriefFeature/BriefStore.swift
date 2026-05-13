import Foundation
import Observation

// TODO(§15-step-4): replace stub with AIKit.threadBrief()

@Observable
@MainActor
public final class BriefStore {
    public private(set) var brief: ThreadBriefViewData?
    public private(set) var activeThreadID: String?

    public init() {}

    /// Load a brief for the given thread ID.
    /// Stub implementation returns hardcoded briefs for fixture threads t1/t2.
    // TODO(§15-step-4): replace stub with AIKit.threadBrief()
    public func loadBrief(forThreadID threadID: String?) {
        activeThreadID = threadID
        guard let threadID else {
            brief = nil
            return
        }

        if threadID.hasSuffix("t1") {
            brief = ThreadBriefViewData(
                summary: "Client approved pricing and asks for the contract draft by Friday.",
                request: "Send contract draft",
                deadline: "Fri \u{00B7} May 15",
                risk: "Tight turnaround",
                nextStep: "Draft reply with contract attached",
                confidence: 0.88,
                evidence: ["msg_1", "msg_3", "contract.pdf p.2"]
            )
        } else if threadID.hasSuffix("t2") {
            brief = ThreadBriefViewData(
                summary: "Jonas wants seat count for Q3 renewal confirmed by Wednesday.",
                request: "Confirm seat count",
                deadline: "Wed \u{00B7} May 14",
                risk: "Legal team CC\u{2019}d",
                nextStep: "Reply with current seat count",
                confidence: 0.92,
                evidence: ["msg_2"]
            )
        } else {
            brief = nil
        }
    }
}
