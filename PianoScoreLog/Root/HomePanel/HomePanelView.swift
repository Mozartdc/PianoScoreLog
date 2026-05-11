import SwiftUI

/// LibraryHomeView의 얇은 래퍼. 하위 호환성을 위해 유지한다.
struct HomePanelView: View {
    let onSelectPiece: (Piece) -> Void
    @Binding var isPanelOpen: Bool

    var body: some View {
        LibraryHomeView(onSelectPiece: onSelectPiece, isPanelOpen: $isPanelOpen)
    }
}
