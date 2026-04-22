import SwiftUI

struct HomePanelView: View {
    let onSelectPiece: (Piece) -> Void
    @Binding var isPanelOpen: Bool

    var body: some View {
        GeometryReader { proxy in
            let topHeight = max(320, proxy.size.height * 0.6)

            VStack(spacing: 0) {
                ScoreLibrarySection(onSelectPiece: onSelectPiece, isPanelOpen: $isPanelOpen)
                    .frame(height: topHeight)

                Divider()

                PianologSection()
                    .frame(maxHeight: .infinity)
            }
        }
    }
}
