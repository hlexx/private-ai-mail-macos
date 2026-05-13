import Foundation

public struct Address: Sendable, Equatable, Codable {
    public let name: String?
    public let email: String

    public init(name: String? = nil, email: String) {
        self.name = name
        self.email = email
    }

    public init?(rfc822 raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if let open = trimmed.lastIndex(of: "<"),
           let close = trimmed.lastIndex(of: ">"),
           open < close {
            let emailPart = String(trimmed[trimmed.index(after: open)..<close])
            let namePart = String(trimmed[trimmed.startIndex..<open])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            self.email = emailPart
            self.name = namePart.isEmpty ? nil : namePart
        } else if trimmed.contains("@") {
            self.email = trimmed
            self.name = nil
        } else {
            return nil
        }
    }
}
