import DesignSystem
import Foundation
import SwiftUI

struct ToastState: Equatable {
    let id = UUID()
    let message: String
    let undoAction: UndoAction?
    let kind: Kind

    init(message: String, undoAction: UndoAction?, kind: Kind = .success) {
        self.message = message
        self.undoAction = undoAction
        self.kind = kind
    }

    enum Kind: Equatable {
        case success
        case error
        case progress
    }

    enum UndoAction: Equatable {
        case unarchive(threadId: String, accountId: String)
        case star(threadId: String, accountId: String)
        case unstar(threadId: String, accountId: String)
        case untrash(threadId: String, accountId: String)
    }
}

extension ToastState.Kind {
    var systemImage: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        case .progress:
            return "arrow.triangle.2.circlepath.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .success:
            return .rbSignalSuccess
        case .error:
            return .rbSignalDeadline
        case .progress:
            return .rbAccent
        }
    }
}
