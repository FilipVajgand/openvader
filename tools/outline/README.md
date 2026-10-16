# Controller outlines

`Sources/OpenVader/Views/VaderOutline.swift` is generated from the line drawings on the appearance page
(page 8) of the Vader 5 Pro user manual. Each part is the outline of an enclosed white region of the
drawing, with the left half mirrored so both sides match. The manual itself is not in this repository.

```sh
swiftc -O -o render render.swift && swiftc -O -o regions regions.swift && swiftc -O -o overlay overlay.swift
./render Flydigi-Vader-5-Pro-EN.pdf 7 page8.png          # page index 7, rendered at 4x
sips --cropToHeightWidth 1000 1500 --cropOffset 420 430 page8.png --out front-wide.png
sips --cropToHeightWidth 1100 1500 --cropOffset 1500 430 page8.png --out back-crop2.png

./regions front-wide.png list                             # region ids, centres and sizes
./regions front-wide.png contour silhouette 1.2 > sil.txt
./regions front-wide.png contour 1 1.0 > bumper.txt       # left bumper
./regions front-wide.png contour 3 0.8 > trigtip.txt      # left trigger tip
export DILATE=3                                           # the back drawing has gaps in its outline
./regions back-crop2.png contour silhouette 1.2 > back-sil.txt
./regions back-crop2.png contour 2 1.2 > back-2.txt       # trigger
./regions back-crop2.png contour 4 1.2 > back-4.txt       # bumper
./regions back-crop2.png contour 19 1.6 > back-19.txt     # upper paddle (right side, mirrored by gen.py)
./regions back-crop2.png contour 26 1.6 > back-26.txt     # lower paddle
python3 gen.py emit ../../Sources/OpenVader/Views/VaderOutline.swift
```

Region ids depend on the crop; check them with `list` first. Control positions in
`ControllerDiagram.swift` come from the same `list` output. To check the result, render the app
(`OpenVader --demo --snapshot <dir>`) and lay the drawing over it with `overlay`.
