//
//  PianoScoreLogApp.swift
//  PianoScoreLog
//
//  Created by choo junho on 3/30/26.
//

import SwiftUI
import SwiftData
#if os(iOS)
import CoreText
#endif

@main
struct PianoScoreLogApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Piece.self,
            PracticeSession.self,
            PieceDailyStatus.self,
            Recording.self,
            MetronomePreset.self
        ])

        return Self.makeContainer(schema: schema)
    }()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                RootShellView()
            }
            .task {
                try? ScoreFileStore.prepareStorageIfNeeded()
                Self.registerStickerFontIfNeeded()
            }
        }
        .modelContainer(sharedModelContainer)
    }

    private static func makeContainer(schema: Schema) -> ModelContainer {
        do {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            #if DEBUG
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            if let container = try? ModelContainer(for: schema, configurations: [fallback]) {
                return container
            }
            #endif
            fatalError("ModelContainer 생성 실패: \(error)")
        }
    }

    private static func registerStickerFontIfNeeded() {
        #if os(iOS)
        guard let fontURL = Bundle.main.url(forResource: "Bravura", withExtension: "otf") else { return }
        CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
        #endif
    }
}
