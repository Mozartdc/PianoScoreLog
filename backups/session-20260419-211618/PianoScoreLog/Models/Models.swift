import Foundation
import SwiftData

@Model
final class Piece {
    @Attribute(.unique) var id: UUID
    var title: String
    var composer: String?
    var pdfRelativePath: String?
    var scoreRelativePath: String?
    var scoreFormat: String?
    var importedAt: Date
    var lastOpenedAt: Date?
    var lastViewedPage: Int
    var createdAt: Date
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        composer: String? = nil,
        pdfRelativePath: String? = nil,
        scoreRelativePath: String? = nil,
        scoreFormat: String? = "pdf",
        importedAt: Date = .now,
        lastOpenedAt: Date? = nil,
        lastViewedPage: Int = 0,
        createdAt: Date = .now,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.composer = composer
        self.pdfRelativePath = pdfRelativePath
        self.scoreRelativePath = scoreRelativePath ?? pdfRelativePath
        self.scoreFormat = scoreFormat
        self.importedAt = importedAt
        self.lastOpenedAt = lastOpenedAt
        self.lastViewedPage = lastViewedPage
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

@Model
final class PracticeSession {
    @Attribute(.unique) var id: UUID
    var pieceID: UUID?
    var dateKey: String
    var startAt: Date
    var endAt: Date
    var durationMinutes: Int
    var memo: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        pieceID: UUID? = nil,
        dateKey: String,
        startAt: Date,
        endAt: Date,
        durationMinutes: Int,
        memo: String = "",
        createdAt: Date = .now
    ) {
        self.id = id
        self.pieceID = pieceID
        self.dateKey = dateKey
        self.startAt = startAt
        self.endAt = endAt
        self.durationMinutes = durationMinutes
        self.memo = memo
        self.createdAt = createdAt
    }
}

@Model
final class PieceDailyStatus {
    @Attribute(.unique) var id: UUID
    var pieceID: UUID
    var dateKey: String
    var isChecked: Bool
    var repeatCount: Int
    var practiceMinutes: Int
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        pieceID: UUID,
        dateKey: String,
        isChecked: Bool = false,
        repeatCount: Int = 0,
        practiceMinutes: Int = 0,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.pieceID = pieceID
        self.dateKey = dateKey
        self.isChecked = isChecked
        self.repeatCount = repeatCount
        self.practiceMinutes = practiceMinutes
        self.updatedAt = updatedAt
    }
}

@Model
final class Recording {
    @Attribute(.unique) var id: UUID
    var pieceID: UUID
    var archiveName: String
    var createdAt: Date
    var durationMs: Int
    var note: String?
    var sourceType: String
    var mimeType: String
    var fileRef: String?

    init(
        id: UUID = UUID(),
        pieceID: UUID,
        archiveName: String,
        createdAt: Date = .now,
        durationMs: Int,
        note: String? = nil,
        sourceType: String,
        mimeType: String,
        fileRef: String? = nil
    ) {
        self.id = id
        self.pieceID = pieceID
        self.archiveName = archiveName
        self.createdAt = createdAt
        self.durationMs = durationMs
        self.note = note
        self.sourceType = sourceType
        self.mimeType = mimeType
        self.fileRef = fileRef
    }
}

@Model
final class MetronomePreset {
    @Attribute(.unique) var id: UUID
    var pieceID: UUID?
    var title: String
    var bpm: Int
    var numerator: Int
    var denominator: Int
    var beatPatternCSV: String
    var updatedAt: Date
    var lastViewedAt: Date

    init(
        id: UUID = UUID(),
        pieceID: UUID? = nil,
        title: String,
        bpm: Int = 60,
        numerator: Int = 4,
        denominator: Int = 4,
        beatPatternCSV: String = "A,2,2,2",
        updatedAt: Date = .now,
        lastViewedAt: Date = .now
    ) {
        self.id = id
        self.pieceID = pieceID
        self.title = title
        self.bpm = bpm
        self.numerator = numerator
        self.denominator = denominator
        self.beatPatternCSV = beatPatternCSV
        self.updatedAt = updatedAt
        self.lastViewedAt = lastViewedAt
    }
}
