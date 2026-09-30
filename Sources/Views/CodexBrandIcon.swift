import AppKit
import SwiftUI

struct CodexBrandIcon: View {
    var size: CGFloat = 16

    private static let image: NSImage? = {
        guard let url = Bundle.module.url(forResource: "codex-mark", withExtension: "svg") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "circle.hexagongrid")
            }
        }
        .frame(width: size, height: size)
        .foregroundStyle(.primary)
        .accessibilityLabel("Codex")
    }
}
