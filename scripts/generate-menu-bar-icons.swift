#!/usr/bin/env swift
//
// generate-menu-bar-icons.swift
//
// Generates 11 menu bar template icon variants:
//   status-ok       — base icon with a small checkmark
//   status-1..9     — base icon with number badge
//   status-10plus   — base icon with "10+" badge
//
// Output: PNG files dropped into the Asset Catalog as imagesets.
//
// Usage: swift scripts/generate-menu-bar-icons.swift
//

import AppKit
import Foundation

// MARK: - Configuration

let assetCatalogPath = "Vigilant/Vigilant/Assets.xcassets"

struct IconVariant {
    let name: String        // imageset name, e.g. "status-ok"
    let badgeText: String?  // nil = checkmark, otherwise the number/text
}

let variants: [IconVariant] = [
    IconVariant(name: "status-ok", badgeText: nil),
] + (1...9).map { IconVariant(name: "status-\($0)", badgeText: "\($0)") }
  + [IconVariant(name: "status-10plus", badgeText: "10+")]

// MARK: - Bug-Ant Icon Path (Heroicons, MIT License)

/// Returns the Heroicons bug-ant solid path scaled to fit within the given size.
/// The original SVG viewBox is 0 0 24 24.
func bugAntPath(fitting targetSize: CGFloat, offset: CGPoint = .zero) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 8.47762, y: 1.6008))
    path.addCurve(to: CGPoint(x: 8.75128, y: 2.62555), control1: CGPoint(x: 8.83616, y: 1.80821), control2: CGPoint(x: 8.95868, y: 2.267))
    path.addCurve(to: CGPoint(x: 8.32551, y: 3.7471), control1: CGPoint(x: 8.55271, y: 2.96881), control2: CGPoint(x: 8.40712, y: 3.34624))
    path.addCurve(to: CGPoint(x: 8.50514, y: 3.91537), control1: CGPoint(x: 8.38406, y: 3.80457), control2: CGPoint(x: 8.44396, y: 3.86068))
    path.addCurve(to: CGPoint(x: 12.0002, y: 2.25), control1: CGPoint(x: 9.32957, y: 2.90013), control2: CGPoint(x: 10.5885, y: 2.25))
    path.addCurve(to: CGPoint(x: 15.4972, y: 3.91782), control1: CGPoint(x: 13.4129, y: 2.25), control2: CGPoint(x: 14.6728, y: 2.90117))
    path.addCurve(to: CGPoint(x: 15.6754, y: 3.75117), control1: CGPoint(x: 15.5579, y: 3.86365), control2: CGPoint(x: 15.6173, y: 3.80808))
    path.addCurve(to: CGPoint(x: 15.2488, y: 2.62555), control1: CGPoint(x: 15.594, y: 3.34879), control2: CGPoint(x: 15.4481, y: 2.96997))
    path.addCurve(to: CGPoint(x: 15.5225, y: 1.6008), control1: CGPoint(x: 15.0414, y: 2.267), control2: CGPoint(x: 15.1639, y: 1.80821))
    path.addCurve(to: CGPoint(x: 16.5472, y: 1.87446), control1: CGPoint(x: 15.881, y: 1.39339), control2: CGPoint(x: 16.3398, y: 1.51591))
    path.addCurve(to: CGPoint(x: 17.2183, y: 3.91994), control1: CGPoint(x: 16.9024, y: 2.48842), control2: CGPoint(x: 17.137, y: 3.18135))
    path.addCurve(to: CGPoint(x: 17.0314, y: 4.50247), control1: CGPoint(x: 17.2416, y: 4.13185), control2: CGPoint(x: 17.1737, y: 4.34368))
    path.addCurve(to: CGPoint(x: 16.2442, y: 5.2509), control1: CGPoint(x: 16.7896, y: 4.77241), control2: CGPoint(x: 16.5263, y: 5.02277))
    path.addCurve(to: CGPoint(x: 16.5002, y: 6.75), control1: CGPoint(x: 16.41, y: 5.72038), control2: CGPoint(x: 16.5002, y: 6.22519))
    path.addCurve(to: CGPoint(x: 16.4602, y: 7.35141), control1: CGPoint(x: 16.5002, y: 6.95356), control2: CGPoint(x: 16.4866, y: 7.15434))
    path.addCurve(to: CGPoint(x: 15.0428, y: 8.75426), control1: CGPoint(x: 16.3543, y: 8.14315), control2: CGPoint(x: 15.7073, y: 8.6458))
    path.addCurve(to: CGPoint(x: 14.496, y: 8.83526), control1: CGPoint(x: 14.8614, y: 8.78388), control2: CGPoint(x: 14.6791, y: 8.81089))
    path.addCurve(to: CGPoint(x: 14.8549, y: 9.57652), control1: CGPoint(x: 14.6477, y: 9.06238), control2: CGPoint(x: 14.7692, y: 9.31137))
    path.addCurve(to: CGPoint(x: 18.6867, y: 8.77423), control1: CGPoint(x: 16.1695, y: 9.41561), control2: CGPoint(x: 17.4498, y: 9.14501))
    path.addCurve(to: CGPoint(x: 18.3417, y: 6.13978), control1: CGPoint(x: 18.6212, y: 7.88092), control2: CGPoint(x: 18.5053, y: 7.00184))
    path.addCurve(to: CGPoint(x: 18.9388, y: 5.26314), control1: CGPoint(x: 18.2645, y: 5.73282), control2: CGPoint(x: 18.5319, y: 5.34034))
    path.addCurve(to: CGPoint(x: 19.8155, y: 5.86022), control1: CGPoint(x: 19.3458, y: 5.18595), control2: CGPoint(x: 19.7383, y: 5.45327))
    path.addCurve(to: CGPoint(x: 20.2201, y: 9.27786), control1: CGPoint(x: 20.0269, y: 6.97505), control2: CGPoint(x: 20.1636, y: 8.11609))
    path.addCurve(to: CGPoint(x: 19.7043, y: 10.0271), control1: CGPoint(x: 20.2365, y: 9.61528), control2: CGPoint(x: 20.0254, y: 9.92203))
    path.addCurve(to: CGPoint(x: 14.9444, y: 11.0766), control1: CGPoint(x: 18.1774, y: 10.5268), control2: CGPoint(x: 16.5854, y: 10.882))
    path.addCurve(to: CGPoint(x: 14.5208, y: 12.1269), control1: CGPoint(x: 14.8703, y: 11.4573), control2: CGPoint(x: 14.7242, y: 11.8123))
    path.addCurve(to: CGPoint(x: 20.464, y: 13.4853), control1: CGPoint(x: 16.5869, y: 12.336), control2: CGPoint(x: 18.5788, y: 12.7993))
    path.addCurve(to: CGPoint(x: 20.9562, y: 14.2344), control1: CGPoint(x: 20.7756, y: 13.5987), control2: CGPoint(x: 20.9758, y: 13.9033))
    path.addCurve(to: CGPoint(x: 19.7674, y: 20.4842), control1: CGPoint(x: 20.8278, y: 16.4041), control2: CGPoint(x: 20.4197, y: 18.4994))
    path.addCurve(to: CGPoint(x: 18.8207, y: 20.9625), control1: CGPoint(x: 19.638, y: 20.8777), control2: CGPoint(x: 19.2142, y: 21.0918))
    path.addCurve(to: CGPoint(x: 18.3424, y: 20.0158), control1: CGPoint(x: 18.4272, y: 20.8332), control2: CGPoint(x: 18.213, y: 20.4093))
    path.addCurve(to: CGPoint(x: 19.4187, y: 14.7085), control1: CGPoint(x: 18.8983, y: 18.3245), control2: CGPoint(x: 19.2654, y: 16.5472))
    path.addCurve(to: CGPoint(x: 17.895, y: 14.2537), control1: CGPoint(x: 18.9182, y: 14.5401), control2: CGPoint(x: 18.4101, y: 14.3883))
    path.addCurve(to: CGPoint(x: 17.9993, y: 15), control1: CGPoint(x: 17.9627, y: 14.4883), control2: CGPoint(x: 17.9993, y: 14.738))
    path.addCurve(to: CGPoint(x: 11.9993, y: 22.5), control1: CGPoint(x: 17.9993, y: 18.9558), control2: CGPoint(x: 15.4775, y: 22.5))
    path.addCurve(to: CGPoint(x: 5.99928, y: 15), control1: CGPoint(x: 8.52108, y: 22.5), control2: CGPoint(x: 5.99928, y: 18.9558))
    path.addCurve(to: CGPoint(x: 6.10348, y: 14.2541), control1: CGPoint(x: 5.99928, y: 14.7382), control2: CGPoint(x: 6.03584, y: 14.4886))
    path.addCurve(to: CGPoint(x: 4.58128, y: 14.7085), control1: CGPoint(x: 5.58888, y: 14.3886), control2: CGPoint(x: 5.08127, y: 14.5403))
    path.addCurve(to: CGPoint(x: 5.65763, y: 20.0158), control1: CGPoint(x: 4.73457, y: 16.5472), control2: CGPoint(x: 5.10172, y: 18.3245))
    path.addCurve(to: CGPoint(x: 5.17932, y: 20.9625), control1: CGPoint(x: 5.78697, y: 20.4093), control2: CGPoint(x: 5.57282, y: 20.8332))
    path.addCurve(to: CGPoint(x: 4.23263, y: 20.4842), control1: CGPoint(x: 4.78582, y: 21.0918), control2: CGPoint(x: 4.36197, y: 20.8777))
    path.addCurve(to: CGPoint(x: 3.0438, y: 14.2344), control1: CGPoint(x: 3.58026, y: 18.4994), control2: CGPoint(x: 3.17221, y: 16.4041))
    path.addCurve(to: CGPoint(x: 3.53602, y: 13.4853), control1: CGPoint(x: 3.02421, y: 13.9033), control2: CGPoint(x: 3.22437, y: 13.5987))
    path.addCurve(to: CGPoint(x: 8.50042, y: 12.2456), control1: CGPoint(x: 5.12188, y: 12.9082), control2: CGPoint(x: 6.78302, y: 12.4887))
    path.addCurve(to: CGPoint(x: 8.5102, y: 12.2442), control1: CGPoint(x: 8.50368, y: 12.2451), control2: CGPoint(x: 8.50694, y: 12.2446))
    path.addCurve(to: CGPoint(x: 9.47876, y: 12.1269), control1: CGPoint(x: 8.83115, y: 12.1989), control2: CGPoint(x: 9.15404, y: 12.1597))
    path.addCurve(to: CGPoint(x: 9.05515, y: 11.0766), control1: CGPoint(x: 9.27538, y: 11.8123), control2: CGPoint(x: 9.12926, y: 11.4573))
    path.addCurve(to: CGPoint(x: 4.29529, y: 10.0271), control1: CGPoint(x: 7.4142, y: 10.882), control2: CGPoint(x: 5.82214, y: 10.5268))
    path.addCurve(to: CGPoint(x: 3.77946, y: 9.27786), control1: CGPoint(x: 3.97423, y: 9.92203), control2: CGPoint(x: 3.76304, y: 9.61528))
    path.addCurve(to: CGPoint(x: 4.18412, y: 5.86023), control1: CGPoint(x: 3.83598, y: 8.11609), control2: CGPoint(x: 3.97265, y: 6.97505))
    path.addCurve(to: CGPoint(x: 5.06076, y: 5.26314), control1: CGPoint(x: 4.26132, y: 5.45327), control2: CGPoint(x: 4.6538, y: 5.18595))
    path.addCurve(to: CGPoint(x: 5.65784, y: 6.13978), control1: CGPoint(x: 5.46772, y: 5.34034), control2: CGPoint(x: 5.73504, y: 5.73282))
    path.addCurve(to: CGPoint(x: 5.31284, y: 8.77423), control1: CGPoint(x: 5.49432, y: 7.00184), control2: CGPoint(x: 5.37836, y: 7.88092))
    path.addCurve(to: CGPoint(x: 9.14473, y: 9.57653), control1: CGPoint(x: 6.54977, y: 9.14502), control2: CGPoint(x: 7.83017, y: 9.41561))
    path.addCurve(to: CGPoint(x: 9.50389, y: 8.8352), control1: CGPoint(x: 9.23046, y: 9.31134), control2: CGPoint(x: 9.35209, y: 9.06232))
    path.addCurve(to: CGPoint(x: 8.95749, y: 8.75426), control1: CGPoint(x: 9.32092, y: 8.81085), control2: CGPoint(x: 9.13878, y: 8.78386))
    path.addCurve(to: CGPoint(x: 7.54009, y: 7.35141), control1: CGPoint(x: 8.29303, y: 8.6458), control2: CGPoint(x: 7.64601, y: 8.14315))
    path.addCurve(to: CGPoint(x: 7.50016, y: 6.75), control1: CGPoint(x: 7.51373, y: 7.15434), control2: CGPoint(x: 7.50016, y: 6.95356))
    path.addCurve(to: CGPoint(x: 7.75718, y: 5.24791), control1: CGPoint(x: 7.50016, y: 6.22408), control2: CGPoint(x: 7.59068, y: 5.71823))
    path.addCurve(to: CGPoint(x: 6.96868, y: 4.49691), control1: CGPoint(x: 7.47455, y: 5.01902), control2: CGPoint(x: 7.21083, y: 4.76779))
    path.addCurve(to: CGPoint(x: 6.78244, y: 3.91417), control1: CGPoint(x: 6.8266, y: 4.33796), control2: CGPoint(x: 6.75887, y: 4.12606))
    path.addCurve(to: CGPoint(x: 7.45287, y: 1.87446), control1: CGPoint(x: 6.86433, y: 3.17773), control2: CGPoint(x: 7.09864, y: 2.48682))
    path.addCurve(to: CGPoint(x: 8.47762, y: 1.6008), control1: CGPoint(x: 7.66028, y: 1.51591), control2: CGPoint(x: 8.11907, y: 1.39339))
    path.closeSubpath()
    let scale = targetSize / 24.0
    // Flip Y: SVG is Y-down, macOS CGContext (flipped:false) is Y-up
    var transform = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale, tx: offset.x, ty: offset.y + targetSize)
    return path.copy(using: &transform)!
}

// MARK: - Icon Rendering

/// Renders a menu bar icon at the given point size (pixels = points for @1x, 2x points for @2x).
func renderIcon(variant: IconVariant, pointSize: CGFloat, scale: Int) -> NSImage {
    let pixelSize = pointSize * CGFloat(scale)
    let size = NSSize(width: pixelSize, height: pixelSize)

    let image = NSImage(size: size, flipped: false) { rect in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

        // --- Draw base bug-ant icon ---
        let iconSize = pixelSize * 0.75
        let yOffset = pixelSize * 0.05
        let iconX = (pixelSize - iconSize) / 2
        let iconY = (pixelSize - iconSize) / 2 + yOffset

        ctx.saveGState()
        ctx.setFillColor(NSColor.black.cgColor)
        let antPath = bugAntPath(fitting: iconSize, offset: CGPoint(x: iconX, y: iconY))
        ctx.addPath(antPath)
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()

        // --- Draw badge ---
        let badgeSize = pixelSize * 0.45
        let badgeX = pixelSize - badgeSize + pixelSize * 0.05
        let badgeY: CGFloat = -pixelSize * 0.05  // bottom-right in flipped=false coords is top-right visually
        let badgeRect = CGRect(x: badgeX, y: badgeY, width: badgeSize, height: badgeSize)

        if let text = variant.badgeText {
            // Number badge: filled circle with number punched out
            ctx.saveGState()

            // Fill badge circle solid
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillEllipse(in: badgeRect)

            // Punch out the number using destination-out blend mode
            let fontSize = text.count > 2 ? badgeSize * 0.42 : badgeSize * 0.58
            let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white,
            ]
            let attrString = NSAttributedString(string: text, attributes: attributes)
            let textSize = attrString.size()
            let textX = badgeRect.midX - textSize.width / 2
            let textY = badgeRect.midY - textSize.height / 2
            let textRect = CGRect(x: textX, y: textY, width: textSize.width, height: textSize.height)

            ctx.setBlendMode(.destinationOut)
            attrString.draw(in: textRect)
            ctx.setBlendMode(.normal)

            ctx.restoreGState()
        } else {
            // Checkmark badge for "ok" status
            ctx.saveGState()

            let checkSize = badgeSize * 0.75
            let checkX = badgeRect.midX - checkSize / 2
            let checkY = badgeRect.midY - checkSize / 2

            let symbolConfig = NSImage.SymbolConfiguration(pointSize: checkSize * 0.5, weight: .bold)
            if let checkImage = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(symbolConfig) {
                let checkRect = CGRect(x: checkX, y: checkY, width: checkSize, height: checkSize)
                checkImage.draw(in: checkRect)
            }

            ctx.restoreGState()
        }

        return true
    }

    image.isTemplate = true
    return image
}

/// Converts an NSImage to PNG data.
func pngData(from image: NSImage) -> Data? {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
    return bitmap.representation(using: .png, properties: [:])
}

// MARK: - Asset Catalog Writing

func writeImageSet(variant: IconVariant, basePath: String) throws {
    let imagesetPath = "\(basePath)/\(variant.name).imageset"

    // Create directory
    try FileManager.default.createDirectory(
        atPath: imagesetPath,
        withIntermediateDirectories: true
    )

    let pointSize: CGFloat = 18  // Standard menu bar icon size

    // Generate @1x
    let image1x = renderIcon(variant: variant, pointSize: pointSize, scale: 1)
    guard let data1x = pngData(from: image1x) else {
        print("  ✗ Failed to generate 1x PNG for \(variant.name)")
        return
    }
    let file1x = "\(variant.name).png"
    try data1x.write(to: URL(fileURLWithPath: "\(imagesetPath)/\(file1x)"))

    // Generate @2x
    let image2x = renderIcon(variant: variant, pointSize: pointSize, scale: 2)
    guard let data2x = pngData(from: image2x) else {
        print("  ✗ Failed to generate 2x PNG for \(variant.name)")
        return
    }
    let file2x = "\(variant.name)@2x.png"
    try data2x.write(to: URL(fileURLWithPath: "\(imagesetPath)/\(file2x)"))

    // Write Contents.json
    let contentsJSON = """
    {
      "images" : [
        {
          "filename" : "\(file1x)",
          "idiom" : "mac",
          "scale" : "1x"
        },
        {
          "filename" : "\(file2x)",
          "idiom" : "mac",
          "scale" : "2x"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      },
      "properties" : {
        "template-rendering-intent" : "template"
      }
    }

    """
    try contentsJSON.write(
        toFile: "\(imagesetPath)/Contents.json",
        atomically: true,
        encoding: .utf8
    )

    print("  ✓ \(variant.name) (1x: \(Int(pointSize))px, 2x: \(Int(pointSize * 2))px)")
}

// MARK: - Main

print("Generating menu bar icons...")
print("Asset catalog: \(assetCatalogPath)\n")

for variant in variants {
    do {
        try writeImageSet(variant: variant, basePath: assetCatalogPath)
    } catch {
        print("  ✗ Error generating \(variant.name): \(error)")
    }
}

print("\nDone! Generated \(variants.count) icon variants.")
print("Open the Asset Catalog in Xcode to verify the icons look correct.")
