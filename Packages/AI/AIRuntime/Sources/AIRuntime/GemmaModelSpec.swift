import Foundation

public enum GemmaModelSpec {
    public static let modelID = "mlx-community/gemma-4-e2b-it-4bit"
    public static let revision = "99d9a53ff828d365a8ecae538e45f80a08d612cd"
    public static let directoryName = "gemma-4-e2b-it-4bit"

    public struct FileEntry: Sendable {
        public let name: String
        public let byteCount: Int64
        public let sha256: String?
    }

    public static let files: [FileEntry] = [
        FileEntry(
            name: "config.json",
            byteCount: 5_996,
            sha256: nil
        ),
        FileEntry(
            name: "chat_template.jinja",
            byteCount: 16_317,
            sha256: nil
        ),
        FileEntry(
            name: "generation_config.json",
            byteCount: 208,
            sha256: nil
        ),
        FileEntry(
            name: "model.safetensors",
            byteCount: 3_581_101_896,
            sha256: "e9bea0584546fafb5ff83a1132a6c4662a8498cc6a5bcda52fc6ca562b7bafab"
        ),
        FileEntry(
            name: "model.safetensors.index.json",
            byteCount: 230_329,
            sha256: nil
        ),
        FileEntry(
            name: "processor_config.json",
            byteCount: 902,
            sha256: nil
        ),
        FileEntry(
            name: "tokenizer.json",
            byteCount: 32_169_626,
            sha256: "cc8d3a0ce36466ccc1278bf987df5f71db1719b9ca6b4118264f45cb627bfe0f"
        ),
        FileEntry(
            name: "tokenizer_config.json",
            byteCount: 2_095,
            sha256: nil
        ),
    ]

    public static var totalBytes: Int64 {
        files.reduce(0) { $0 + $1.byteCount }
    }

    static func downloadURL(for fileName: String) -> URL {
        guard let encoded = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://huggingface.co/\(modelID)/resolve/\(revision)/\(encoded)")
        else {
            preconditionFailure("GemmaModelSpec: invalid download URL for file '\(fileName)'")
        }
        return url
    }
}
