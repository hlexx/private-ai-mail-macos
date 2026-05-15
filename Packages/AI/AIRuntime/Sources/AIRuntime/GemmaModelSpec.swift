import Foundation

public enum GemmaModelSpec {
    public static let modelID = "mlx-community/gemma-4-e4b-it-OptiQ-4bit"
    public static let revision = "cfac466f1bca589c605b9ca1dd57c2deb63c5c63"
    public static let directoryName = "gemma-4-it-optiq-4bit"

    public struct FileEntry: Sendable {
        public let name: String
        public let byteCount: Int64
        public let sha256: String?
    }

    public static let files: [FileEntry] = [
        FileEntry(
            name: "config.json",
            byteCount: 81_691,
            sha256: nil
        ),
        FileEntry(
            name: "chat_template.jinja",
            byteCount: 16_804,
            sha256: nil
        ),
        FileEntry(
            name: "generation_config.json",
            byteCount: 208,
            sha256: nil
        ),
        FileEntry(
            name: "model-00001-of-00002.safetensors",
            byteCount: 3_523_881_390,
            sha256: "0d239262a51b1795d1556ba0d0bdea955c126108d053249d2fd4c1e1584100fd"
        ),
        FileEntry(
            name: "model-00002-of-00002.safetensors",
            byteCount: 3_010_217_360,
            sha256: "da846c36ac065e0c8f558cd27286757490fc345b6613ac2789750c0d760f59a3"
        ),
        FileEntry(
            name: "model.safetensors.index.json",
            byteCount: 151_391,
            sha256: nil
        ),
        FileEntry(
            name: "optiq_metadata.json",
            byteCount: 40_081,
            sha256: nil
        ),
        FileEntry(
            name: "tokenizer.json",
            byteCount: 32_169_626,
            sha256: "cc8d3a0ce36466ccc1278bf987df5f71db1719b9ca6b4118264f45cb627bfe0f"
        ),
        FileEntry(
            name: "tokenizer_config.json",
            byteCount: 2_744,
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
