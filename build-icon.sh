#!/usr/bin/env bash
# 把 logo.png 处理成 macOS AppIcon.icns
# 每个图标 PNG 在 iconset 内为正方形，源图等比缩放居中，空白区域透明
set -euo pipefail

SRC="${1:-logo.png}"
ICONS_DIR="${2:-Resources/AppIcon.iconset}"
ICNS="${3:-Resources/AppIcon.icns}"

[ -f "$SRC" ] || { echo "找不到 $SRC"; exit 1; }
mkdir -p "$ICONS_DIR"
rm -f "$ICONS_DIR"/*.png

swift - <<SWIFT_EOF
import AppKit
import ImageIO
import UniformTypeIdentifiers

guard let img = NSImage(contentsOfFile: "$SRC"),
      let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let src = rep.cgImage else {
    FileHandle.standardError.write("无法读取 $SRC\n".data(using: .utf8)!)
    exit(1)
}
let sw = src.width
let sh = src.height
let sizes: [(Int, String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]
for (dim, name) in sizes {
    let outURL = URL(fileURLWithPath: "$ICONS_DIR/\(name)")
    let cs = CGColorSpaceCreateDeviceRGB()
    let info = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let ctx = CGContext(
        data: nil, width: dim, height: dim,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: cs, bitmapInfo: info
    ) else { exit(1) }
    let scale = Double(dim) / Double(max(sw, sh))
    let w = Int(Double(sw) * scale)
    let h = Int(Double(sh) * scale)
    let x = (dim - w) / 2
    let y = (dim - h) / 2
    ctx.clear(CGRect(x: 0, y: 0, width: dim, height: dim))
    ctx.draw(src, in: CGRect(x: x, y: y, width: w, height: h))
    guard let out = ctx.makeImage(),
          let dst = CGImageDestinationCreateWithURL(
            outURL as CFURL,
            UTType.png.identifier as CFString, 1, nil
          ) else { exit(1) }
    CGImageDestinationAddImage(dst, out, nil)
    if !CGImageDestinationFinalize(dst) { exit(1) }
}
SWIFT_EOF

rm -f "$ICNS"
iconutil -c icns "$ICONS_DIR" -o "$ICNS"
echo "Generated: $ICNS"
