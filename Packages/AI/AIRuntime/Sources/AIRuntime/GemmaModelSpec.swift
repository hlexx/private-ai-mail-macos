import Foundation

public enum GemmaModelSpec {
    public static let modelID = "mlx-community/gemma-3-4b-it-4bit"
    public static let revision = "main"
    public static let directoryName = "gemma-4-it-4bit"

    public struct FileEntry: Sendable {
        public let name: String
        public let byteCount: Int64
        public let sha256: String?
    }

    public static let files: [FileEntry] = [
        FileEntry(
            name: "model.safetensors",
            byteCount: 3_400_569_562,
            sha256: "94d3d701367d78584a9334ca00672b1c86e4aefa6a94167556c0485381e74af3"
        ),
        FileEntry(
            name: "model.safetensors.index.json",
            byteCount: 90_558,
            sha256: nil
        ),
        FileEntry(
            name: "config.json",
            byteCount: 1_072,
            sha256: nil
        ),
        FileEntry(
            name: "tokenizer.json",
            byteCount: 33_384_568,
            sha256: "4667f2089529e8e7657cfb6d1c19910ae71ff5f28aa7ab2ff2763330affad795"
        ),
        FileEntry(
            name: "tokenizer.model",
            byteCount: 4_689_074,
            sha256: "1299c11d7cf632ef3b4e11937501358ada021bbdf7c47638d13c0ee982f2e79c"
        ),
        FileEntry(
            name: "tokenizer_config.json",
            byteCount: 1_157_007,
            sha256: nil
        ),
        FileEntry(
            name: "generation_config.json",
            byteCount: 192,
            sha256: nil
        ),
        FileEntry(
            name: "special_tokens_map.json",
            byteCount: 662,
            sha256: nil
        ),
        FileEntry(
            name: "preprocessor_config.json",
            byteCount: 570,
            sha256: nil
        ),
        FileEntry(
            name: "processor_config.json",
            byteCount: 70,
            sha256: nil
        ),
        FileEntry(
            name: "added_tokens.json",
            byteCount: 35,
            sha256: nil
        ),
        FileEntry(
            name: "chat_template.json",
            byteCount: 1_615,
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
