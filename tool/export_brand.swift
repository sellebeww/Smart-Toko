// Run from the repository root on macOS:
// swift -module-cache-path /tmp/smarttoko-swift-cache tool/export_brand.swift
// Export platform sizes from the approved logo without redrawing the artwork.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = root.appendingPathComponent("assets/brand/smarttoko-logo.png")
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let logo = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("Cannot read approved logo")
}
let canvas = CGColor(red: 247/255, green: 247/255, blue: 241/255, alpha: 1)

func export(_ path: String, size: Int, opaque: Bool = false,
            scale: Double = 1, monochrome: Bool = false) throws {
    let alpha = opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast
    guard let context = CGContext(data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: size * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: alpha.rawValue) else {
        fatalError("Cannot create image context")
    }
    let bounds = CGRect(x: 0, y: 0, width: size, height: size)
    if opaque {
        context.setFillColor(canvas)
        context.fill(bounds)
    }
    context.interpolationQuality = .high
    let inset = Double(size) * (1 - scale) / 2
    context.draw(logo, in: bounds.insetBy(dx: inset, dy: inset))
    if monochrome {
        context.setBlendMode(.sourceIn)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(bounds)
    }
    let url = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                           withIntermediateDirectories: true)
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Cannot create PNG: \(path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("Cannot write PNG: \(path)")
    }
    print("\(size)x\(size) \(path)")
}

let res = "android/app/src/main/res"
for (density, factor) in [("mdpi", 1.0), ("hdpi", 1.5), ("xhdpi", 2.0),
                          ("xxhdpi", 3.0), ("xxxhdpi", 4.0)] {
    try export("\(res)/mipmap-\(density)/ic_launcher.png", size: Int(48 * factor))
    try export("\(res)/drawable-\(density)/launch_logo.png", size: Int(160 * factor))
    try export("\(res)/drawable-\(density)/ic_stat_smarttoko.png",
               size: Int(24 * factor), monochrome: true)
    // Android 12 masks splash icons to a circle; leave safe padding.
    try export("\(res)/drawable-\(density)/splash_logo.png",
               size: Int(288 * factor), scale: 0.60)
}

let catalog = "ios/Runner/Assets.xcassets"
let iconPath = "\(catalog)/AppIcon.appiconset"
let data = try Data(contentsOf: root.appendingPathComponent("\(iconPath)/Contents.json"))
let manifest = try JSONSerialization.jsonObject(with: data) as! [String: Any]
var written = Set<String>()
for entry in manifest["images"] as! [[String: String]] {
    guard let filename = entry["filename"], written.insert(filename).inserted else { continue }
    let points = Double(entry["size"]!.split(separator: "x")[0])!
    let scale = Double(entry["scale"]!.dropLast())!
    try export("\(iconPath)/\(filename)", size: Int((points * scale).rounded()), opaque: true)
}
for scale in 1...3 {
    let suffix = scale == 1 ? "" : "@\(scale)x"
    try export("\(catalog)/LaunchImage.imageset/LaunchImage\(suffix).png", size: 160 * scale)
}
