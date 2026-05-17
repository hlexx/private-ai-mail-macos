import Foundation

public enum GmailDTO {
    public struct MessageList: Codable, Sendable {
        public let messages: [MessageRef]?
        public let nextPageToken: String?
        public let resultSizeEstimate: Int?

        public init(messages: [MessageRef]? = nil, nextPageToken: String? = nil, resultSizeEstimate: Int? = nil) {
            self.messages = messages
            self.nextPageToken = nextPageToken
            self.resultSizeEstimate = resultSizeEstimate
        }
    }

    public struct MessageRef: Codable, Sendable {
        public let id: String
        public let threadId: String

        public init(id: String, threadId: String) {
            self.id = id
            self.threadId = threadId
        }
    }

    public struct Message: Codable, Sendable {
        public let id: String
        public let threadId: String
        public let labelIds: [String]?
        public let snippet: String?
        public let historyId: String?
        public let internalDate: String?
        public let payload: MessagePart?
        public let sizeEstimate: Int?

        public init(
            id: String,
            threadId: String,
            labelIds: [String]? = nil,
            snippet: String? = nil,
            historyId: String? = nil,
            internalDate: String? = nil,
            payload: MessagePart? = nil,
            sizeEstimate: Int? = nil
        ) {
            self.id = id
            self.threadId = threadId
            self.labelIds = labelIds
            self.snippet = snippet
            self.historyId = historyId
            self.internalDate = internalDate
            self.payload = payload
            self.sizeEstimate = sizeEstimate
        }
    }

    public struct Thread: Codable, Sendable {
        public let id: String
        public let historyId: String?
        public let messages: [Message]?

        public init(id: String, historyId: String? = nil, messages: [Message]? = nil) {
            self.id = id
            self.historyId = historyId
            self.messages = messages
        }
    }

    public struct MessagePart: Codable, Sendable {
        public let partId: String?
        public let mimeType: String?
        public let filename: String?
        public let headers: [MessagePartHeader]?
        public let body: MessagePartBody?
        public let parts: [MessagePart]?

        public init(
            partId: String? = nil,
            mimeType: String? = nil,
            filename: String? = nil,
            headers: [MessagePartHeader]? = nil,
            body: MessagePartBody? = nil,
            parts: [MessagePart]? = nil
        ) {
            self.partId = partId
            self.mimeType = mimeType
            self.filename = filename
            self.headers = headers
            self.body = body
            self.parts = parts
        }
    }

    public struct MessagePartHeader: Codable, Sendable {
        public let name: String
        public let value: String

        public init(name: String, value: String) {
            self.name = name
            self.value = value
        }
    }

    public struct MessagePartBody: Codable, Sendable {
        public let attachmentId: String?
        public let size: Int?
        public let data: String?

        public init(attachmentId: String? = nil, size: Int? = nil, data: String? = nil) {
            self.attachmentId = attachmentId
            self.size = size
            self.data = data
        }
    }

    public struct Label: Decodable, Sendable {
        public let id: String
        public let name: String
        public let type: String
        public let color: ColorInfo?
        public let messagesUnread: Int?
        public let messagesTotal: Int?

        public struct ColorInfo: Decodable, Sendable {
            public let backgroundColor: String?
            public let textColor: String?
        }

        public init(
            id: String,
            name: String,
            type: String = "system",
            color: ColorInfo? = nil,
            messagesUnread: Int? = nil,
            messagesTotal: Int? = nil
        ) {
            self.id = id
            self.name = name
            self.type = type
            self.color = color
            self.messagesUnread = messagesUnread
            self.messagesTotal = messagesTotal
        }
    }

    public struct LabelList: Decodable, Sendable {
        public let labels: [Label]?

        public init(labels: [Label]? = nil) {
            self.labels = labels
        }
    }

    public struct SentMessage: Codable, Sendable {
        public let id: String
        public let threadId: String
        public let labelIds: [String]?

        public init(id: String, threadId: String, labelIds: [String]? = nil) {
            self.id = id
            self.threadId = threadId
            self.labelIds = labelIds
        }
    }

    public struct HistoryResponse: Codable, Sendable {
        public let history: [HistoryRecord]?
        public let nextPageToken: String?
        public let historyId: String?

        public init(history: [HistoryRecord]? = nil, nextPageToken: String? = nil, historyId: String? = nil) {
            self.history = history
            self.nextPageToken = nextPageToken
            self.historyId = historyId
        }
    }

    public struct HistoryRecord: Codable, Sendable {
        public let id: String
        public let messages: [Message]?
        public let messagesAdded: [HistoryMessageAdded]?
        public let messagesDeleted: [HistoryMessageDeleted]?
        public let labelsAdded: [HistoryLabelAdded]?
        public let labelsRemoved: [HistoryLabelRemoved]?

        public init(
            id: String,
            messages: [Message]? = nil,
            messagesAdded: [HistoryMessageAdded]? = nil,
            messagesDeleted: [HistoryMessageDeleted]? = nil,
            labelsAdded: [HistoryLabelAdded]? = nil,
            labelsRemoved: [HistoryLabelRemoved]? = nil
        ) {
            self.id = id
            self.messages = messages
            self.messagesAdded = messagesAdded
            self.messagesDeleted = messagesDeleted
            self.labelsAdded = labelsAdded
            self.labelsRemoved = labelsRemoved
        }
    }

    public struct HistoryMessageAdded: Codable, Sendable {
        public let message: Message

        public init(message: Message) {
            self.message = message
        }
    }

    public struct HistoryMessageDeleted: Codable, Sendable {
        public let message: Message

        public init(message: Message) {
            self.message = message
        }
    }

    public struct HistoryLabelAdded: Codable, Sendable {
        public let message: Message
        public let labelIds: [String]

        public init(message: Message, labelIds: [String]) {
            self.message = message
            self.labelIds = labelIds
        }
    }

    public struct HistoryLabelRemoved: Codable, Sendable {
        public let message: Message
        public let labelIds: [String]

        public init(message: Message, labelIds: [String]) {
            self.message = message
            self.labelIds = labelIds
        }
    }
}
