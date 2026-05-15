import Foundation

public enum AIError: Error, Sendable {
    case modelNotInstalled
    case modelLoadFailed(any Error)
    case inferenceFailed(any Error)
    case invalidStructuredOutput(String)
    case cancelled
}
