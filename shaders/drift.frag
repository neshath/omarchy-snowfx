#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float level;      // 0..1 how much snow has settled
    float maxHeight;  // px at level 1
    float radius;     // Hyprland decoration:rounding (px)
    float seed;       // per-window variation
    float tintMix;
    float wind;       // -1 (W) .. 1 (E), leans sculpted drifts downwind
    float style;      // 0 = flat, 1 = sculpted
    float edgeTaper;  // 1 = round the ends like a window corner, 0 = run to the item edges (snowbank)
    vec2 size;        // item size in px
    vec4 rect;        // x, y, w, h of the window top edge inside the item (y = top edge line)
    vec4 occ0;        // windows in front (item-local px); w <= 0 means unused
    vec4 occ1;
    vec4 occ2;
    vec4 occ3;
    vec4 tint;        // theme tint
    vec4 shade;       // theme-tinted cool shadow color
};

float inRect(vec2 p, vec4 r) {
    if (r.z <= 0.0) return 0.0;
    vec2 d = min(p - r.xy, r.xy + r.zw - p);
    return smoothstep(-0.5, 0.5, min(d.x, d.y));
}

float hash11(float n) { return fract(sin(n * 91.345) * 47453.5453); }

// Flat style: quarter-circle shoulders that match the window's corner rounding.
float shoulder(float edge, float rs) {
    float x = clamp(edge / rs, 0.0, 1.0);
    return sqrt(max(1.0 - (1.0 - x) * (1.0 - x), 0.0));
}

// 1D value noise (smooth, seeded) and a 3-octave fBm built from it.
float vnoise(float x, float sd) {
    float i = floor(x), f = x - i;
    f = f * f * (3.0 - 2.0 * f);
    return mix(hash11(i + sd), hash11(i + 1.0 + sd), f);
}
float fbm(float x, float sd) {
    return 0.55 * vnoise(x, sd) + 0.30 * vnoise(x * 2.07 + 11.3, sd + 3.1) + 0.15 * vnoise(x * 4.13 + 5.7, sd + 7.9);
}

// Sculpted style: wind-carved drift. Returns 0..1 where 1 = full peak; troughs bottom out near
// troughFrac of the peak. Crests are skewed downwind (steeper windward, longer leeward tail).
float sculpt(float lx, float w) {
    float sd = seed * 53.0;
    float u = lx * 0.021 + sd;
    float n0 = fbm(u, sd);
    // Domain warp by the noise itself pushes crests downwind and stretches the lee slope.
    float u2 = u - wind * 0.85 * (n0 - 0.5) - wind * 0.0;
    float n = fbm(u2, sd);
    n = clamp((n - 0.22) / 0.56, 0.0, 1.0);          // spread to the full 0..1 range
    n = n * n * (3.0 - 2.0 * n);
    // very gentle overall lean downwind
    n *= 1.0 + wind * 0.10 * (lx / max(w, 1.0) - 0.5);
    return mix(0.36, 1.0, clamp(n, 0.0, 1.0));       // trough ~36% of peak (~2.5 px of 7)
}

void main() {
    vec2 p = qt_TexCoord0 * size;
    float w = rect.z;
    float lx = p.x - rect.x;                       // 0..w along the window top
    float edge = min(lx, w - lx);                  // distance to nearest window corner side
    float r = min(radius, 0.5 * min(w, rect.w));

    // The top edge curves down around rounded corners; the drift's base hugs that arc.
    float dx = max(r - edge, 0.0);
    float drop = (r > 0.5 && dx > 0.0) ? (r - sqrt(max(r * r - dx * dx, 0.0))) : 0.0;
    float baseY = rect.y + drop;

    // Mound height tapers to nothing at the corners.
    float taper = mix(1.0, shoulder(edge, max(r * 1.15, 8.0)), edgeTaper);
    float prof = style < 0.5 ? 1.0 : sculpt(lx, w);
    float h = maxHeight * level * prof * taper;

    float yUp = baseY - p.y;                       // height above the base
    float inside = step(0.0, lx) * step(lx, w);

    // Soft top surface of the mound.
    float body = smoothstep(-0.6, 0.8, yUp) * (1.0 - smoothstep(h - 1.2, h + 0.4, yUp));
    // Thin underside shadow resting on the window border (just below the base).
    float shadowBand = smoothstep(-4.5, -0.2, yUp) * (1.0 - smoothstep(-0.2, 0.4, yUp));
    shadowBand *= smoothstep(0.0, 2.5, h) * inside;

    float vis = 1.0 - max(max(inRect(p, occ0), inRect(p, occ1)), max(inRect(p, occ2), inRect(p, occ3)));

    // Shading: bright crest, cooler blue-gray toward the base.
    float t = clamp(yUp / max(h, 1.0), 0.0, 1.0);
    vec3 crest = mix(vec3(1.0), tint.rgb, tintMix);
    vec3 cool = mix(vec3(0.70, 0.78, 0.90), shade.rgb, 0.25);
    vec3 col = mix(cool, crest, smoothstep(0.0, 0.85, t));
    // Ambient occlusion: soft cool darkening hugging the contact line with the window top.
    float ao = (1.0 - smoothstep(0.0, 2.8, yUp)) * 0.55;
    col = mix(col, mix(vec3(0.52, 0.62, 0.80), shade.rgb, 0.3), ao);
    // Crisp ~1px highlight along the upper silhouette of the drift.
    float hi = smoothstep(h - 1.4, h - 0.5, yUp) * (1.0 - smoothstep(h - 0.2, h + 0.4, yUp));
    col = mix(col, vec3(1.0), hi * 0.9 * step(2.0, h));
    // faint sparkle
    float sp = step(0.9965, hash11(floor(p.x * 0.5) * 7.0 + floor(p.y * 0.5) * 131.0 + seed));
    col = mix(col, vec3(1.0), sp * 0.6);

    float aBody = body * inside * 0.97 * step(0.5, h);
    float aShadow = shadowBand * 0.38;
    vec3 shadowCol = mix(vec3(0.30, 0.38, 0.52), shade.rgb, 0.3);

    float a = aBody + aShadow * (1.0 - aBody);
    vec3 c = (col * aBody + shadowCol * aShadow * (1.0 - aBody)) / max(a, 0.0001);
    a *= vis * qt_Opacity;
    fragColor = vec4(c * a, a);                    // premultiplied
}
