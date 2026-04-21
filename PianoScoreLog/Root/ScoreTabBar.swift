import SwiftUI

struct ScoreTabBar: View {
    let openPieces: [Piece]
    @Binding var selectedPieceID: UUID?
    let onClose: (UUID) -> Void

    // 컨테이너 너비를 overlay GeometryReader로 측정 — 레이아웃에 영향 없음
    @State private var containerWidth: CGFloat = 320

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(openPieces.enumerated()), id: \.element.id) { _, piece in
                        ScoreTabItem(
                            piece: piece,
                            isSelected: selectedPieceID == piece.id,
                            titleWidth: computedTitleWidth,
                            onSelect: { selectedPieceID = piece.id },
                            onClose: { onClose(piece.id) }
                        )
                        .id(piece.id)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // .bar = 네비게이션바·탭바에 쓰는 시스템 소재. 뒤에 콘텐츠가 없어도 올바른 시스템 색조를 유지.
            .background(.bar)
            // 컨테이너 너비 측정 — Color.clear이라 시각적 영향 없음
            .overlay {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { containerWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, w in containerWidth = w }
                }
            }
            .onChange(of: selectedPieceID) { _, newID in
                guard let id = newID else { return }
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    // 사파리 스타일: 탭 수에 따라 타이틀 너비를 균등 분배
    // 탭당 비-타이틀 영역: leading(8) + trailing(2) + close button(~24) = ~34pt
    // HStack spacing: 4pt, outer padding: 8pt*2 = 16pt
    private var computedTitleWidth: CGFloat {
        let count = max(1, openPieces.count)
        let itemOverhead: CGFloat = 34
        let spacing = CGFloat(count - 1) * 4
        let outerPadding: CGFloat = 16
        let available = containerWidth - outerPadding - spacing - itemOverhead * CGFloat(count)
        return max(60, available / CGFloat(count))
    }
}

private struct ScoreTabItem: View {
    let piece: Piece
    let isSelected: Bool
    let titleWidth: CGFloat
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // 타이틀 영역 — 탭 전체가 아니라 텍스트 영역만 선택 제스처
            Text(piece.title)
                .font(.footnote.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .frame(width: titleWidth, alignment: .leading)
                .padding(.leading, 8)
                .padding(.trailing, 2)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .onTapGesture(perform: onSelect)

            // × 버튼
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected ? .secondary : .tertiary)
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        // 선택: 시스템 배경색(다크모드 자동 대응) / 미선택: 투명
        .background(isSelected ? Color(.systemBackground) : Color.clear)
    }
}
