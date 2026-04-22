import Foundation

private struct AnnotationLayersMetadata: Codable {
    let layers: [AnnotationLayer]
    let activeLayerID: UUID?
}

private struct StickerPlacementsPayload: Codable {
    let placements: [StickerPlacement]
}

enum ScoreFileStoreError: LocalizedError {
    case unsupportedScoreFile
    case copyFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedScoreFile:
            return "PDF 또는 MusicXML 파일을 선택해 주세요."
        case .copyFailed:
            return "악보 파일을 앱 저장소로 복사하지 못했습니다."
        }
    }
}

enum ScoreFileStore {
    private static let migrationFlagKey = "ScoreFileStore.didMigratePiecesToDocuments.v1"
    private static let folderName = "pieces"

    enum ImportedScoreType: String {
        case pdf
        case musicXML = "musicxml"

        var fileExtension: String {
            switch self {
            case .pdf:
                return "pdf"
            case .musicXML:
                return "musicxml"
            }
        }
    }

    static func libraryDirectoryURL() throws -> URL {
        try prepareStorageIfNeeded()
        return try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent(folderName, isDirectory: true)
    }

    static func prepareStorageIfNeeded() throws {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let target = documents.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        }

        try migrateLegacyIfNeeded(to: target)
    }

    static func importScore(from sourceURL: URL, pieceID: UUID) throws -> (relativePath: String, type: ImportedScoreType) {
        let scoreType = try resolveImportedScoreType(for: sourceURL)

        let hasSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let destinationDir = try pieceDirectoryURL(pieceID: pieceID)
        let fileName = "score.\(scoreType.fileExtension)"
        let destination = destinationDir.appendingPathComponent(fileName, isDirectory: false)

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return ("\(pieceID.uuidString)/\(fileName)", scoreType)
        } catch {
            throw ScoreFileStoreError.copyFailed
        }
    }

    static func importPDF(from sourceURL: URL, pieceID: UUID) throws -> String {
        let result = try importScore(from: sourceURL, pieceID: pieceID)
        guard result.type == .pdf else {
            throw ScoreFileStoreError.unsupportedScoreFile
        }
        return result.relativePath
    }

    static func fileURL(for relativePath: String?) throws -> URL? {
        guard let relativePath, !relativePath.isEmpty else { return nil }
        let base = try libraryDirectoryURL()
        return base.appendingPathComponent(relativePath, isDirectory: false)
    }

    static func remove(relativePath: String?) {
        guard let relativePath, !relativePath.isEmpty else { return }
        do {
            let base = try libraryDirectoryURL()
            let url = base.appendingPathComponent(relativePath, isDirectory: false)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            // no-op
        }
    }

    static func removePieceDirectory(pieceID: UUID) {
        do {
            let base = try libraryDirectoryURL()
            let dir = base.appendingPathComponent(pieceID.uuidString, isDirectory: true)
            if FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.removeItem(at: dir)
            }
        } catch {
            // no-op
        }
    }

    static func pieceDirectoryURL(pieceID: UUID) throws -> URL {
        let base = try libraryDirectoryURL()
        let pieceDir = base.appendingPathComponent(pieceID.uuidString, isDirectory: true)
        if !FileManager.default.fileExists(atPath: pieceDir.path) {
            try FileManager.default.createDirectory(at: pieceDir, withIntermediateDirectories: true)
        }
        return pieceDir
    }

    static func annotationsDirectoryRelativePath(pieceID: UUID) -> String {
        "\(pieceID.uuidString)/annotations"
    }

    static func annotationPageRelativePath(pieceID: UUID, pageIndex: Int) -> String {
        "\(annotationsDirectoryRelativePath(pieceID: pieceID))/page_\(max(0, pageIndex)).data"
    }

    static func recordingsDirectoryRelativePath(pieceID: UUID) -> String {
        "\(pieceID.uuidString)/recordings"
    }

    static func annotationsDirectoryURL(pieceID: UUID) throws -> URL {
        let base = try libraryDirectoryURL()
        let dir = base.appendingPathComponent(annotationsDirectoryRelativePath(pieceID: pieceID), isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func annotationPageURL(pieceID: UUID, pageIndex: Int) throws -> URL {
        let dir = try annotationsDirectoryURL(pieceID: pieceID)
        return dir.appendingPathComponent("page_\(max(0, pageIndex)).data", isDirectory: false)
    }

    static func annotationLayerDirectoryURL(pieceID: UUID, layerID: UUID) throws -> URL {
        let base = try annotationsDirectoryURL(pieceID: pieceID)
        let dir = base.appendingPathComponent("layer_\(layerID.uuidString)", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func annotationLayerPageURL(pieceID: UUID, layerID: UUID, pageIndex: Int) throws -> URL {
        let dir = try annotationLayerDirectoryURL(pieceID: pieceID, layerID: layerID)
        return dir.appendingPathComponent("page_\(max(0, pageIndex)).data", isDirectory: false)
    }

    static func annotationLayersMetadataURL(pieceID: UUID) throws -> URL {
        let dir = try annotationsDirectoryURL(pieceID: pieceID)
        return dir.appendingPathComponent("layers.json", isDirectory: false)
    }

    static func stickersMetadataURL(pieceID: UUID) throws -> URL {
        let dir = try annotationsDirectoryURL(pieceID: pieceID)
        return dir.appendingPathComponent("stickers.json", isDirectory: false)
    }

    static func loadAnnotationData(pieceID: UUID, pageIndex: Int) -> Data? {
        do {
            let url = try annotationPageURL(pieceID: pieceID, pageIndex: pageIndex)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try Data(contentsOf: url)
        } catch {
            return nil
        }
    }

    static func loadAnnotationData(pieceID: UUID, layerID: UUID, pageIndex: Int) -> Data? {
        do {
            let url = try annotationLayerPageURL(pieceID: pieceID, layerID: layerID, pageIndex: pageIndex)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try Data(contentsOf: url)
        } catch {
            return nil
        }
    }

    static func saveAnnotationData(_ data: Data, pieceID: UUID, pageIndex: Int) {
        do {
            let url = try annotationPageURL(pieceID: pieceID, pageIndex: pageIndex)
            try data.write(to: url, options: .atomic)
        } catch {
            // no-op
        }
    }

    static func saveAnnotationData(_ data: Data, pieceID: UUID, layerID: UUID, pageIndex: Int) {
        do {
            let url = try annotationLayerPageURL(pieceID: pieceID, layerID: layerID, pageIndex: pageIndex)
            try data.write(to: url, options: .atomic)
        } catch {
            // no-op
        }
    }

    static func removeAnnotationData(pieceID: UUID, pageIndex: Int) {
        do {
            let url = try annotationPageURL(pieceID: pieceID, pageIndex: pageIndex)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            // no-op
        }
    }

    static func removeAnnotationData(pieceID: UUID, layerID: UUID, pageIndex: Int) {
        do {
            let url = try annotationLayerPageURL(pieceID: pieceID, layerID: layerID, pageIndex: pageIndex)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            // no-op
        }
    }

    static func saveAnnotationLayersMetadata(layers: [AnnotationLayer], activeLayerID: UUID?, pieceID: UUID) {
        do {
            let url = try annotationLayersMetadataURL(pieceID: pieceID)
            let payload = AnnotationLayersMetadata(layers: layers, activeLayerID: activeLayerID)
            let data = try JSONEncoder().encode(payload)
            try data.write(to: url, options: .atomic)
        } catch {
            // no-op
        }
    }

    static func loadAnnotationLayersMetadata(pieceID: UUID) -> (layers: [AnnotationLayer], activeLayerID: UUID?)? {
        do {
            let url = try annotationLayersMetadataURL(pieceID: pieceID)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let data = try Data(contentsOf: url)
            let payload = try JSONDecoder().decode(AnnotationLayersMetadata.self, from: data)
            return (payload.layers, payload.activeLayerID)
        } catch {
            return nil
        }
    }

    static func saveStickerPlacements(_ placements: [StickerPlacement], pieceID: UUID) {
        do {
            let url = try stickersMetadataURL(pieceID: pieceID)
            let payload = StickerPlacementsPayload(placements: placements)
            let data = try JSONEncoder().encode(payload)
            try data.write(to: url, options: .atomic)
        } catch {
            // no-op
        }
    }

    static func loadStickerPlacements(pieceID: UUID) -> [StickerPlacement] {
        do {
            let url = try stickersMetadataURL(pieceID: pieceID)
            guard FileManager.default.fileExists(atPath: url.path) else { return [] }
            let data = try Data(contentsOf: url)
            let payload = try JSONDecoder().decode(StickerPlacementsPayload.self, from: data)
            return payload.placements
        } catch {
            return []
        }
    }

    static func ubiquityContainerURL() -> URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)
    }

    static func isUploadedToICloud(fileURL: URL) -> Bool? {
        let values = try? fileURL.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemIsUploadedKey])
        guard values?.isUbiquitousItem == true else { return nil }
        return values?.ubiquitousItemIsUploaded
    }

    private static func migrateLegacyIfNeeded(to documentsPiecesDir: URL) throws {
        if UserDefaults.standard.bool(forKey: migrationFlagKey) {
            return
        }

        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let legacyDir = appSupport.appendingPathComponent(folderName, isDirectory: true)

        guard FileManager.default.fileExists(atPath: legacyDir.path) else {
            UserDefaults.standard.set(true, forKey: migrationFlagKey)
            return
        }

        let enumerator = FileManager.default.enumerator(
            at: legacyDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        while let source = enumerator?.nextObject() as? URL {
            let relativePath = source.path.replacingOccurrences(of: legacyDir.path + "/", with: "")
            let destination = documentsPiecesDir.appendingPathComponent(relativePath, isDirectory: false)

            let values = try source.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                if !FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                }
            } else {
                let parent = destination.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: parent.path) {
                    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                }
                if !FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.copyItem(at: source, to: destination)
                }
            }
        }

        UserDefaults.standard.set(true, forKey: migrationFlagKey)
    }

    private static func resolveImportedScoreType(for sourceURL: URL) throws -> ImportedScoreType {
        let ext = sourceURL.pathExtension.lowercased()
        switch ext {
        case "pdf":
            return .pdf
        case "xml", "musicxml", "mxl":
            return .musicXML
        default:
            throw ScoreFileStoreError.unsupportedScoreFile
        }
    }
}
