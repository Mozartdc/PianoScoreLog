#if os(iOS)
enum DrawingTool: String, CaseIterable, Identifiable {
    case pen
    case pencil
    case highlighter
    case eraser
    case sticker
    case postit
    case text
    case ruler

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .pen: return "pencil.tip"
        case .pencil: return "pencil"
        case .highlighter: return "highlighter"
        case .eraser: return "eraser"
        case .sticker: return "music.note.list"
        case .postit: return "note.text"
        case .text: return "textformat"
        case .ruler: return "ruler"
        }
    }
}

enum PianologFeature: String, CaseIterable, Identifiable {
    case home
    case appleScore
    case metronome
    case recording
    case photoImport
    case today
    case stats
    case settings

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .appleScore: return "5.arrow.trianglehead.counterclockwise"
        case .metronome: return "metronome"
        case .recording: return "record.circle"
        case .photoImport: return "photo.on.rectangle.angled"
        case .today: return "calendar"
        case .stats: return "chart.line.uptrend.xyaxis"
        case .settings: return "gearshape"
        }
    }
}

enum DrawingToolMode {
    case pen
    case pencil
    case marker
    case eraser
    case sticker
    case text
}

enum EraserMode: String, CaseIterable, Identifiable {
    case bitmap = "영역"
    case vector = "획"
    var id: String { rawValue }
}
#endif
