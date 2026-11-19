#include <metal_stdlib>
using namespace metal;

/// A soft light on the glass, brightest near the tile's upper left, scaling the premultiplied wash so its alpha follows
/// and the wash's own shape holds. Only the selected tile (the arrow keys' choice, and the first search hit) draws it (`LaunchpadGlow`).
[[ stitchable ]] half4 selectionGlow(float2 p, half4 color, float2 size, float strength) {
    float2 q = float2(p.x, p.y) / size.x;
    float r = distance(q, float2(0.28, 0.10 * size.y / size.x));
    return color * half(1.0 + strength * (1.0 - smoothstep(0.0, 0.95, r)));
}
