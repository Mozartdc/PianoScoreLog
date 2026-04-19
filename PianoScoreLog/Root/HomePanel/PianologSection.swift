import SwiftUI

struct PianologSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("피출앱")
                .font(.headline)
            Text("피출 기능 - 다음 단계에서 구현")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}
