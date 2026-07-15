import Foundation

enum FixtureResource {
    static func url(_ relativePath: String) throws -> URL {
        guard let root = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return relativePath.split(separator: "/").reduce(root) { url, component in
            url.appendingPathComponent(String(component))
        }
    }

    static func data(_ relativePath: String) throws -> Data {
        try Data(contentsOf: url(relativePath))
    }

    static func provider(
        directory relativePath: String,
        mappedTo destinationRoot: URL,
        modificationDate: Date? = nil
    ) throws -> InMemoryDirectoryAccessProvider {
        let sourceRoot = try url(relativePath)
        guard let enumerator = FileManager.default.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }

        var files: [(path: String, data: Data)] = []
        while let fileURL = enumerator.nextObject() as? URL {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let path = fileURL.pathComponents
                .dropFirst(sourceRoot.pathComponents.count)
                .joined(separator: "/")
            files.append((path, try Data(contentsOf: fileURL)))
        }

        return InMemoryDirectoryAccessProvider.make { builder in
            for file in files.sorted(by: { $0.path < $1.path }) {
                builder.addFile(
                    at: destinationRoot.appendingPathComponent(file.path),
                    data: file.data,
                    modificationDate: modificationDate
                )
            }
        }
    }
}
