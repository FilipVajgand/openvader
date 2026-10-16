// Splits a line drawing into its enclosed white regions.
// Usage: regions <image.png> list                       -> every region: id, area, bbox, centroid
//        regions <image.png> silhouette <out.png>         -> the body silhouette (leader lines removed)
//        regions <image.png> contour <id|silhouette> [eps] -> outline of one region, normalised to the silhouette box
import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard let src = NSImage(contentsOf: URL(fileURLWithPath: args[1]))?.cgImage(forProposedRect: nil, context: nil, hints: nil)
else { fatalError("load") }
let w = src.width, h = src.height
var px = [UInt8](repeating: 0, count: w * h * 4)
let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))

// Ink: dark pixels, thickened by one pixel so hairline gaps in the scan close.
var ink = [Bool](repeating: false, count: w * h)
for i in 0..<(w * h) {
    let lum = (Int(px[i * 4]) * 299 + Int(px[i * 4 + 1]) * 587 + Int(px[i * 4 + 2]) * 114) / 1000
    ink[i] = lum < 170
}
func dilate(_ m: [Bool], _ r: Int) -> [Bool] {
    var out = m
    for y in 0..<h { for x in 0..<w where m[y * w + x] {
        for dy in -r...r { for dx in -r...r {
            let nx = x + dx, ny = y + dy
            if nx >= 0, ny >= 0, nx < w, ny < h { out[ny * w + nx] = true }
        } }
    } }
    return out
}
func erode(_ m: [Bool], _ r: Int) -> [Bool] { dilate(m.map { !$0 }, r).map { !$0 } }
ink = dilate(ink, Int(ProcessInfo.processInfo.environment["DILATE"] ?? "1")!)

// Label white regions (4-neighbour).
var label = [Int](repeating: -1, count: w * h)
struct Region { var id: Int; var area = 0; var minX = Int.max, minY = Int.max, maxX = 0, maxY = 0; var sx = 0, sy = 0; var border = false }
var regions: [Region] = []
for start in 0..<(w * h) where !ink[start] && label[start] < 0 {
    var r = Region(id: regions.count)
    var stack = [start]; label[start] = r.id
    while let p = stack.popLast() {
        let x = p % w, y = p / w
        r.area += 1; r.sx += x; r.sy += y
        r.minX = min(r.minX, x); r.maxX = max(r.maxX, x); r.minY = min(r.minY, y); r.maxY = max(r.maxY, y)
        if x == 0 || y == 0 || x == w - 1 || y == h - 1 { r.border = true }
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let nx = x + dx, ny = y + dy
            guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
            let q = ny * w + nx
            if !ink[q] && label[q] < 0 { label[q] = r.id; stack.append(q) }
        }
    }
    regions.append(r)
}

// Silhouette: everything not reachable from the border, opened to drop thin leader lines.
var body = (0..<(w * h)).map { label[$0] < 0 || !regions[label[$0]].border }
body = dilate(erode(body, 5), 5)
// Keep the largest blob.
var blob = [Int](repeating: -1, count: w * h)
var best = (id: -1, size: 0), next = 0
for s in 0..<(w * h) where body[s] && blob[s] < 0 {
    var stack = [s]; blob[s] = next; var size = 0
    while let p = stack.popLast() {
        size += 1
        let x = p % w, y = p / w
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let nx = x + dx, ny = y + dy
            guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
            let q = ny * w + nx
            if body[q] && blob[q] < 0 { blob[q] = next; stack.append(q) }
        }
    }
    if size > best.size { best = (next, size) }
    next += 1
}
body = blob.map { $0 == best.id }
var bx0 = w, by0 = h, bx1 = 0, by1 = 0
for y in 0..<h { for x in 0..<w where body[y * w + x] { bx0 = min(bx0, x); bx1 = max(bx1, x); by0 = min(by0, y); by1 = max(by1, y) } }
let axis = Double(bx0 + bx1) / 2
func norm(_ x: Double, _ y: Double) -> (Double, Double) { ((x - Double(bx0)) / Double(bx1 - bx0), (y - Double(by0)) / Double(by1 - by0)) }

switch args[2] {
case "list":
    print("silhouette box x \(bx0)...\(bx1) y \(by0)...\(by1), axis \(axis)")
    for r in regions where !r.border && r.area > 150 {
        let c = norm(Double(r.sx) / Double(r.area), Double(r.sy) / Double(r.area))
        let bw = Double(r.maxX - r.minX) / Double(bx1 - bx0), bh = Double(r.maxY - r.minY) / Double(by1 - by0)
        print(String(format: "id %4d area %7d  centre (%.4f, %.4f)  size %.4f x %.4f  px box %d,%d-%d,%d",
                     r.id, r.area, c.0, c.1, bw, bh, r.minX, r.minY, r.maxX, r.maxY))
    }
case "silhouette":
    let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 1,
                               hasAlpha: false, isPlanar: false, colorSpaceName: .deviceWhite, bytesPerRow: w, bitsPerPixel: 8)!
    for i in 0..<(w * h) { out.bitmapData![i] = body[i] ? 0 : 255 }
    try out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))
case "contour":
    // The region's mask, slightly grown back over the ink that bounds it.
    let mask: [Bool] = args[3] == "silhouette" ? body : dilate((0..<(w * h)).map { label[$0] == Int(args[3])! }, 2)
    let eps = args.count > 4 ? Double(args[4])! : 1.5
    func inside(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < w && y < h && mask[y * w + x] }
    var sx = 0, sy = 0
    outer: for y in 0..<h { for x in 0..<w where inside(x, y) { sx = x; sy = y; break outer } }
    let dirs = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
    var contour = [(Double(sx), Double(sy))]
    var cx = sx, cy = sy, back = 4
    repeat {
        var found = false
        for k in 1...8 {
            let d = (back + k) % 8
            let nx = cx + dirs[d].0, ny = cy + dirs[d].1
            if inside(nx, ny) { cx = nx; cy = ny; back = (d + 4) % 8; contour.append((Double(cx), Double(cy))); found = true; break }
        }
        if !found || contour.count > w * h { break }
    } while !(cx == sx && cy == sy) || contour.count < 3
    // Smooth, then simplify (Douglas-Peucker on the open polyline).
    let n = contour.count, win = 9
    let smooth = (0..<n).map { i -> (Double, Double) in
        var ax = 0.0, ay = 0.0
        for k in -(win / 2)...(win / 2) { let q = contour[(i + k + n) % n]; ax += q.0; ay += q.1 }
        return (ax / Double(win), ay / Double(win))
    }
    func simplify(_ pts: [(Double, Double)]) -> [(Double, Double)] {
        guard pts.count > 2 else { return pts }
        let a = pts.first!, b = pts.last!
        var maxD = 0.0, idx = 0
        for i in 1..<(pts.count - 1) {
            let p = pts[i]
            let num = abs((b.1 - a.1) * p.0 - (b.0 - a.0) * p.1 + b.0 * a.1 - b.1 * a.0)
            let den = max(1e-9, ((b.1 - a.1) * (b.1 - a.1) + (b.0 - a.0) * (b.0 - a.0)).squareRoot())
            if num / den > maxD { maxD = num / den; idx = i }
        }
        if maxD < eps { return [a, b] }
        return Array(simplify(Array(pts[...idx])).dropLast()) + simplify(Array(pts[idx...]))
    }
    let half = n / 2
    let pts = simplify(Array(smooth[..<half])) + simplify(Array(smooth[half...])).dropFirst()
    print("// \(pts.count) points")
    print(pts.map { let p = norm($0.0, $0.1); return String(format: "(%.4f, %.4f)", p.0, p.1) }.joined(separator: ", "))
default:
    print("unknown mode")
}
