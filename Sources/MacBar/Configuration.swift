import Foundation

struct AppEntry: Codable, Identifiable, Equatable {
    var name: String
    var bundleIdentifier: String
    var path: String?
    var id: String { bundleIdentifier }
}

struct Configuration: Codable, Equatable {
    var apps: [AppEntry]
    var background: BackgroundSettings?

    func validated() throws -> Configuration {
        if let path = background?.imagePath, !path.hasPrefix("/") {
            throw ConfigurationError.relativePath
        }
        var seen = Set<String>()
        for app in apps {
            guard !app.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !app.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ConfigurationError.invalidEntry
            }
            guard seen.insert(app.bundleIdentifier).inserted else {
                throw ConfigurationError.duplicate(app.bundleIdentifier)
            }
            if let path = app.path, !path.hasPrefix("/") {
                throw ConfigurationError.relativePath
            }
        }
        return self
    }

    static func read(from url: URL) throws -> Configuration {
        try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: url)).validated()
    }

    func save(to url: URL) throws {
        _ = try validated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

enum ConfigurationError: LocalizedError {
    case invalidEntry, relativePath, duplicate(String)
    var errorDescription: String? {
        switch self {
        case .invalidEntry: return "Every app needs a name and bundleIdentifier."
        case .relativePath: return "App and background image paths must be absolute paths starting with /."
        case .duplicate(let identifier): return "The app \(identifier) appears more than once."
        }
    }
}

enum BackgroundMode: String, Codable, CaseIterable {
    case fit, fill, stretch
    var title: String { rawValue.capitalized }
}

struct BackgroundSettings: Codable, Equatable {
    var imagePath: String? = nil
    var mode: BackgroundMode = .fill
    var isEnabled: Bool = true
}
