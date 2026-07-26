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
