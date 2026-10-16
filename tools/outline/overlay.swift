// Overlays a line drawing (its dark pixels, in red) on a screenshot, matching the two silhouettes' boxes.
// Usage: overlay <screenshot> <x0 y0 x1 y1 search box> <drawing> <dx0 dy0 dx1 dy1 drawing box> <out>
import AppKit
func load(_ p: String) -> (CGImage, [UInt8]) {
    let img = NSImage(contentsOf: URL(fileURLWithPath: p))!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    var px = [UInt8](repeating: 0, count: img.width * img.height * 4)
    let ctx = CGContext(data: &px, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
    return (img, px)
}
let a = CommandLine.arguments
let (shot, spx) = load(a[1]); let sw = shot.width
let sx0 = Int(a[2])!, sy0 = Int(a[3])!, sx1 = Int(a[4])!, sy1 = Int(a[5])!
// The body in the screenshot: dark pixels inside the search box.
var bx0 = Int.max, by0 = Int.max, bx1 = 0, by1 = 0
for y in sy0..<sy1 { for x in sx0..<sx1 {
    let i = (y * sw + x) * 4
    if Int(spx[i]) + Int(spx[i + 1]) + Int(spx[i + 2]) < 3 * 70 { bx0 = min(bx0, x); bx1 = max(bx1, x); by0 = min(by0, y); by1 = max(by1, y) }
} }
if let t = ProcessInfo.processInfo.environment["TARGET"]?.split(separator: ",").compactMap({ Int($0) }), t.count == 4 {
    (bx0, by0, bx1, by1) = (t[0], t[1], t[2], t[3])
}
print("screenshot body box", bx0, by0, bx1, by1)
let (draw, dpx) = load(a[6]); let dw = draw.width
let dx0 = Double(a[7])!, dy0 = Double(a[8])!, dx1 = Double(a[9])!, dy1 = Double(a[10])!
var out = spx
for y in Int(min(dy0, dy1))...Int(max(dy0, dy1)) { for x in Int(min(dx0, dx1))...Int(max(dx0, dx1)) {
    let i = (y * dw + x) * 4
    guard Int(dpx[i]) + Int(dpx[i + 1]) + Int(dpx[i + 2]) < 3 * 140 else { continue }
    let tx = Int(Double(bx0) + (Double(x) - dx0) / (dx1 - dx0) * Double(bx1 - bx0))
    let ty = Int(Double(by0) + (Double(y) - dy0) / (dy1 - dy0) * Double(by1 - by0))
    guard tx >= 0, ty >= 0, tx < sw, ty < shot.height else { continue }
    let o = (ty * sw + tx) * 4
    out[o] = 255; out[o + 1] = 40; out[o + 2] = 40
} }
let ctx = CGContext(data: &out, width: sw, height: shot.height, bitsPerComponent: 8, bytesPerRow: sw * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[11]))
