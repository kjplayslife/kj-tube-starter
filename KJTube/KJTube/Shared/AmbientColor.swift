import CoreImage
import SwiftUI
import UIKit

/// The glow color behind the player (D76): the thumbnail's average color, made a little
/// brighter and more saturated so it reads as a color, not grey.
enum AmbientColor {
    // CIContext is thread-safe; Swift just can't tell.
    nonisolated(unsafe) private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    static func of(_ image: UIImage) -> Color? {
        guard let input = CIImage(image: image) else { return nil }
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: input,
            kCIInputExtentKey: CIVector(cgRect: input.extent),
        ])
        guard let output = filter?.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        let average = UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                              blue: CGFloat(pixel[2]) / 255, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        return Color(hue: hue, saturation: min(saturation * 1.4, 1), brightness: max(brightness, 0.55))
    }
}
