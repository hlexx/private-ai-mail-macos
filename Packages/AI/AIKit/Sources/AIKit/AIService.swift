import Foundation

public protocol AIService: Sendable {
    func threadBrief(_ input: AIThreadInput) async throws -> AIThreadBrief
}
