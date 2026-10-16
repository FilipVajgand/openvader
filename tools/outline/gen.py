import re, sys
def load(f):
    t = open(f).read().split("\n", 1)[1]
    return [tuple(map(float, m)) for m in re.findall(r"\(([-\d.]+), ([-\d.]+)\)", t)]
def mirrored_whole(pts):
    """Left half of a symmetric closed outline plus its mirror image."""
    n = len(pts)
    left = [p[0] < 0.5 for p in pts]
    best = (0, 0)
    for s in range(n):
        if left[s] and not left[s - 1]:
            k = 0
            while left[(s + k) % n] and k < n: k += 1
            if k > best[1]: best = (s, k)
    s, k = best
    arc = [pts[(s + i) % n] for i in range(k)]
    def cross(a, b):
        t = (0.5 - a[0]) / (b[0] - a[0]); return (0.5, a[1] + t * (b[1] - a[1]))
    arc = [cross(pts[(s - 1) % n], pts[s])] + arc + [cross(pts[(s + k - 1) % n], pts[(s + k) % n])]
    if arc[0][1] > arc[-1][1]: arc.reverse()
    return arc + [(1 - x, y) for x, y in reversed(arc[1:-1])]
def swift(name, pts, doc):
    body = ",\n".join("        " + ", ".join(f"({x:.4f}, {y:.4f})" for x, y in pts[i:i + 5]) for i in range(0, len(pts), 5))
    return f"    /// {doc}\n    static let {name}: [(CGFloat, CGFloat)] = [\n{body}\n    ]\n"
if sys.argv[1] == "check":
    for f in sys.argv[2:]:
        pts = mirrored_whole(load(f))
        print(f, len(pts)); print("  " + " ".join(f"({x:.3f},{y:.3f})" for x, y in pts[:len(pts)//2 + 1]))
if sys.argv[1] == "emit":
    front = [p for p in load("sil.txt") if not (0.025 < p[0] < 0.034 and 0.525 < p[1] < 0.55)]
    plate_left = [(0.5, 0.060), (0.383, 0.063), (0.289, 0.082), (0.272, 0.100), (0.245, 0.117), (0.240, 0.200),
                  (0.230, 0.340), (0.222, 0.500), (0.228, 0.560), (0.240, 0.620), (0.255, 0.680), (0.270, 0.730),
                  (0.285, 0.777), (0.340, 0.768), (0.440, 0.764), (0.5, 0.764)]
    plate = plate_left + [(1 - x, y) for x, y in reversed(plate_left[1:-1])]
    out = ["// Generated from the Vader 5 Pro manual's appearance page (front and back line drawings):",
           "// each part is the outline of an enclosed region, left half mirrored. Fractions of the",
           "// silhouette's bounding box. Regenerate rather than edit by hand.",
           "import CoreGraphics", "", "enum VaderOutline {"]
    out.append(swift("front", mirrored_whole(front), "The whole front silhouette, bumpers and trigger tips included."))
    out.append(swift("back", mirrored_whole(load("back-sil.txt")), "The back silhouette; the triggers stand taller from behind."))
    out.append(swift("frontBumper", load("bumper.txt"), "Left bumper on the front view; mirror for the right."))
    out.append(swift("frontTriggerTip", load("trigtip.txt"), "The part of the left trigger that shows above the bumper from the front."))
    out.append(swift("backTrigger", load("back-2.txt"), "Left trigger on the back view (seen through the controller)."))
    out.append(swift("backBumper", load("back-4.txt"), "Left bumper on the back view."))
    # The left paddles touch label lines in the manual, so mirror the clean right-hand ones.
    out.append(swift("upperPaddle", [(1 - x, y) for x, y in load("back-19.txt")], "Left upper back button (M1)."))
    out.append(swift("lowerPaddle", [(1 - x, y) for x, y in load("back-26.txt")], "Left lower, detachable back paddle (M3)."))
    out.append(swift("backPlate", plate, "The raised panel on the back."))
    out.append("}")
    open(sys.argv[2], "w").write("\n".join(out) + "\n")
    print("wrote", sys.argv[2])
