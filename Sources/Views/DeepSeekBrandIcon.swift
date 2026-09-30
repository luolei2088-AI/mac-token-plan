import AppKit
import SwiftUI

struct DeepSeekBrandIcon: View {
    var size: CGFloat = 16

    private static let image: NSImage? = {
        guard let url = Bundle.module.url(forResource: "deepseek-mark", withExtension: "svg") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "sparkle")
                    .foregroundStyle(Color(red: 0.30, green: 0.42, blue: 1.0))
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("DeepSeek")
    }
}
