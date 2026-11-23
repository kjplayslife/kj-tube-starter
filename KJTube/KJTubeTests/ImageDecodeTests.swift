import Testing
import UIKit
@testable import KJTube

/// Smooth Inbox scroll: thumbnails are decoded up front and shrunk to card size.
struct ImageDecodeTests {
    private func jpeg(width: CGFloat, height: CGFloat) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
            .jpegData(withCompressionQuality: 0.8) { context in
                UIColor.red.setFill()
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            }
    }

    @Test("A maxres thumbnail shrinks to card size, keeping its shape")
    func shrinksBig() throws {
        let image = try #require(ImageCache.decode(jpeg(width: 1280, height: 720)))
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        #expect(pixels.width == CGFloat(ImageCache.maxPixels))
        #expect(abs(pixels.width / pixels.height - 16 / 9) < 0.01)
    }

    @Test("A small image (an avatar) keeps its size")
    func keepsSmall() throws {
        let image = try #require(ImageCache.decode(jpeg(width: 88, height: 88)))
        #expect(image.size.width * image.scale == 88)
    }

    @Test("Bad data gives no image")
    func badData() {
        #expect(ImageCache.decode(Data("not an image".utf8)) == nil)
    }
}
