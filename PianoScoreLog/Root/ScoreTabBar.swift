import SwiftUI

struct ScoreTabBar: View {
    let openPieces: [Piece]
    @Binding var selectedPieceID: UUID?
    let onClose: (UUID) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(openPieces.enumerated()), id: \.element.id) { index, piece in
                        let isSelected = selectedPieceID == piece.id
                        let prevSelected = index > 0 && selectedPieceID == openPieces[index - 1].id

                        if index > 0 && !isSelected && !prevSelected {
                            Rectangle()
                                .fill(Color(.separator))
                                .frame(width: 0.5, height: 20)
                        }

                        ScoreTabItem(
                            piece: piece,
                            isSelected: isSelected,
                            onSelect: { selectedPieceID = piece.id },
                            onClose: { onClose(piece.id) }
                        )
                        .id(piece.id)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .onChange(of: selectedPieceID) { _, newID in
                guard let id = newID else { return }
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private struct ScoreTabItem: View {
    let piece: Piece
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onSelect) {
                Text(piece.title)
                    .font(.footnote.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 160, alignment: .leading)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color(.systemBackground) : Color.clear)
        )
        .animation(.spring(duration: 0.2), value: isSelected)
    }
}
