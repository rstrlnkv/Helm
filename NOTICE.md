# Third-party material in Helm

Helm itself is GPL-3.0 (see [LICENSE](LICENSE)). It ships the following
third-party artwork, which carries its own terms.

## Flag artwork — flag-icons

`Sources/Modules/Layout/UI/Flags/*.png` are rendered from the 4:3 SVGs of
**flag-icons**, one per ISO 3166-1 alpha-2 region, at 128 × 96.

- Source: <https://github.com/lipis/flag-icons>
- Copyright: © Panayiotis Lipiridis and contributors
- Licence: **MIT**

```
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

Rebuild them with `Scripts/flags/fetch-flags.sh`. They are rendered through
WebKit rather than shipped as SVG because `NSImage`'s SVG support does not
resolve `<use xlink:href>` references — China's stars are defined that way,
and CoreSVG drew a plain red rectangle while reporting success.

### Previously considered

EmojiOne v2.2.7 (CC BY 4.0) was used briefly. Its flags are round, which is
that set's own shape; flag-icons is rectangular, which is the shape a flag has.
Later EmojiOne artwork is under JoyPixels' own licence and is not usable here.

## Palette objects — PencilKit for Figma

`Sources/Modules/Screenshots/UI/PaletteObjects.xcassets` holds the Pen, Marker,
Pencil, Eraser and Ruler drawn on the screenshot editor's palette, in a light and a dark variant each.
They are taken from the Figma file **PencilKit for figma (Copy)**
(<https://www.figma.com/design/33IGj6K24Gp1BJIpWmHZJs/PencilKit-for-figma--Copy->),
a community recreation of Apple's iPadOS 13 PencilKit picker.

- Source: <https://www.figma.com/design/33IGj6K24Gp1BJIpWmHZJs/PencilKit-for-figma--Copy->
- Author: (to be filled in by the owner)
- Licence: (to be filled in by the owner)
- Use in Helm: the owner checked the file's licence on 2026-10-02 and decided
  the objects may be used.
- Modified for Helm: SVG filters removed (macOS drops them silently), the Pen, Marker and
  Pencil split into body, tip and tip highlight layers so the tip can take the ink colour (the Eraser and
  the Ruler are a body layer only),
  thickness labels removed, the shadow margin cropped, the dark Marker re-aligned to the
  light one's height.

The Spotlight object in the same catalogue (`spotlight-light-body` and `spotlight-dark-body`): its shape was drawn for Helm; the body and band
fills are the Pen's gradients from that file (the same stops as `pen-light-body` and `pen-dark-body`, the dark ones written with fewer digits), and
the beam and lens gradients are Helm's. The SVG filter its source carried was removed, as for the others, since macOS drops filters.
