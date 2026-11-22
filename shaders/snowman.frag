#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

// A small procedural snowman (three stacked snowballs, scarf, top hat, carrot nose, coal eyes,
// buttons and stick arms), drawn entirely from signed distance functions. Original artwork.
// Model space: x right, y up, origin at the middle of the feet; units scale by `unit`.
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float prog;       // 0..1 build progress (balls stack up, then face / scarf / hat arrive)
    float sway;       // seconds (wrapped), scarf flutter
    float wind;       // -1 .. 1, scarf tail leans downwind
    float flip;       // -1 or 1: which way the nose points
    float unit;       // item px per model unit
    float lean;       // radians, tilt of the whole figure (about where it enters the snow)
    float sink;       // model units the feet are lowered below the bank surface (partly submerged)
    float tintMix;
    vec2 size;        // item size in px
    vec4 tint;        // theme tint, pulls the snow slightly toward the theme
    vec4 shade;       // theme-tinted cool shadow color
    vec4 scarf;       // scarf / hat band color (theme accent)
};

float sdCircle(vec2 p, vec2 c, float r) { return r > 0.2 ? length(p - c) - r : 1000.0; }
float sdBox(vec2 p, vec2 c, vec2 h) {
    vec2 d = abs(p - c) - h;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}
float sdSeg(vec2 p, vec2 a, vec2 b, out float h) {
    vec2 pa = p - a, ba = b - a;
    h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}
float smin(float a, float b, float k) {
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}
vec4 over(vec4 top, vec4 bottom) { return top + bottom * (1.0 - top.a); }   // premultiplied

void main() {
    vec2 p = qt_TexCoord0 * size;
    vec2 q = vec2(p.x - 0.5 * size.x, size.y - 2.0 * unit - p.y) / unit;
    float aa = 0.6 / unit;                                   // ~0.6 screen px, in model units

    // The figure leans (and swings) about the point where it enters the snow.
    vec2 pv = vec2(0.0, sink + 2.0);
    float cs = cos(lean), sn = sin(lean);
    vec2 dq = q - pv;
    q = pv + vec2(cs * dq.x + sn * dq.y, -sn * dq.x + cs * dq.y);

    // ---- build-up -----------------------------------------------------------------------
    float s1 = smoothstep(0.00, 0.35, prog);
    float s2 = smoothstep(0.28, 0.66, prog);
    float s3 = smoothstep(0.58, 0.95, prog);
    float fs = smoothstep(0.90, 1.00, prog);                 // face and scarf
    float hp = smoothstep(0.85, 1.00, prog);                 // hat drops in last
    float r1 = 13.0 * s1, r2 = 9.5 * s2, r3 = 7.0 * s3;
    // Each ball grows upward from its resting point on the one below.
    vec2 c1 = vec2(0.0, -2.0 + r1), c2 = vec2(0.0, 20.0 + r2), c3 = vec2(0.0, 34.5 + r3);
    float d1 = sdCircle(q, c1, r1), d2 = sdCircle(q, c2, r2), d3 = sdCircle(q, c3, r3);
    float d = smin(smin(d1, d2, 1.2), d3, 1.0);

    // ---- stick arms (behind the body) -------------------------------------------------------
    float h;
    float da = 1000.0;
    da = min(da, sdSeg(q, vec2(-8.0, 31.0), vec2(-19.5, 38.5), h));
    da = min(da, sdSeg(q, vec2(-15.0, 35.8), vec2(-18.2, 32.0), h));
    da = min(da, sdSeg(q, vec2(-17.2, 37.4), vec2(-19.2, 41.2), h));
    da = min(da, sdSeg(q, vec2(8.0, 31.5), vec2(19.5, 41.5), h));
    da = min(da, sdSeg(q, vec2(15.0, 37.0), vec2(18.6, 35.0), h));
    da = min(da, sdSeg(q, vec2(17.3, 39.2), vec2(18.6, 43.2), h));
    float aArm = (1.0 - smoothstep(0.55 - aa, 0.55 + aa, da)) * smoothstep(0.55, 0.80, prog);
    vec3 armCol = mix(vec3(0.34, 0.22, 0.12), shade.rgb, 0.12);
    vec4 res = vec4(armCol * aArm, aArm);

    // ---- body ------------------------------------------------------------------------------
    vec2 cc = c1; float dm = d1;
    if (d2 < dm) { dm = d2; cc = c2; }
    if (d3 < dm) { dm = d3; cc = c3; }
    vec2 n = normalize(q - cc + vec2(0.0001));
    float lit = dot(n, normalize(vec2(-0.55, 0.8))) * 0.5 + 0.5;
    vec3 snow = mix(vec3(0.97, 0.98, 1.0), tint.rgb, tintMix);
    vec3 cool = mix(vec3(0.62, 0.72, 0.88), shade.rgb, 0.3);
    vec3 bc = mix(cool, snow, smoothstep(0.15, 0.85, lit));
    // Soft creases where one ball sits in the next.
    float ao = (1.0 - smoothstep(0.0, 2.5, d2)) * step(d1, 0.0) + (1.0 - smoothstep(0.0, 2.2, d3)) * step(d2, 0.0);
    bc = mix(bc, cool * 0.88, clamp(ao, 0.0, 1.0) * 0.4);
    float aBody = (1.0 - smoothstep(-aa, aa, d)) * smoothstep(0.0, 0.08, prog);
    res = over(vec4(bc * aBody, aBody), res);

    // ---- scarf (theme accent) ---------------------------------------------------------------
    float inBody = 1.0 - smoothstep(-aa, aa, d + 0.4);
    float neck = abs(q.y - 36.3) - (1.6 + 0.25 * sin(q.x * 0.9));
    float stripe = step(0.5, fract(q.x * 0.16 + 0.2));
    vec3 scarfCol = mix(scarf.rgb, scarf.rgb * 0.62 + vec3(0.08), stripe);
    float aScarf = (1.0 - smoothstep(-aa, aa, neck)) * inBody * fs;
    res = over(vec4(scarfCol * aScarf, aScarf), res);
    float k = clamp((36.3 - q.y) / 9.0, 0.0, 1.0);
    float tailX = -flip * 5.5 + wind * 3.2 * k + sin(sway * 2.2 + q.y * 0.45) * 0.7 * k;
    float dt = sdBox(q, vec2(tailX, 31.2), vec2(1.5, 4.8));
    float tStripe = step(0.5, fract(q.y * 0.16 + 0.1));
    vec3 tailCol = mix(scarf.rgb, scarf.rgb * 0.62 + vec3(0.08), tStripe);
    float aTail = (1.0 - smoothstep(-aa, aa, dt)) * fs;
    res = over(vec4(tailCol * aTail, aTail), res);

    // ---- buttons ----------------------------------------------------------------------------
    vec3 coal = vec3(0.07, 0.08, 0.11);
    float db = min(min(sdCircle(q, vec2(0.0, 31.4), 0.95), sdCircle(q, vec2(0.0, 27.6), 0.95)),
                   sdCircle(q, vec2(0.0, 23.8), 0.95));
    float aBtn = (1.0 - smoothstep(-aa, aa, db)) * fs;
    res = over(vec4(coal * aBtn, aBtn), res);

    // ---- face: eyes, smile, carrot nose -------------------------------------------------------
    float df = min(sdCircle(q, vec2(-2.5, 43.0), 0.9), sdCircle(q, vec2(2.5, 43.0), 0.9));
    for (int i = 0; i < 5; i++) {
        float x = -3.0 + 1.5 * float(i);
        df = min(df, sdCircle(q, vec2(x, 38.4 + 0.14 * x * x), 0.55));
    }
    float aFace = (1.0 - smoothstep(-aa, aa, df)) * fs;
    res = over(vec4(coal * aFace, aFace), res);
    float hn;
    float dn = sdSeg(q, vec2(flip * 0.6, 41.3), vec2(flip * 7.2, 40.2), hn) - mix(1.15, 0.15, hn);
    vec3 carrot = vec3(1.0, 0.52, 0.12) * (0.82 + 0.18 * (1.0 - hn));
    float aNose = (1.0 - smoothstep(-aa, aa, dn)) * fs;
    res = over(vec4(carrot * aNose, aNose), res);

    // ---- top hat (drops onto the head last) -----------------------------------------------------
    vec2 qh = vec2(q.x, q.y - (1.0 - hp) * 10.0);
    float dBrim = sdBox(qh, vec2(0.0, 48.0), vec2(7.8, 0.95));
    float dCrown = sdBox(qh, vec2(0.0, 53.2), vec2(4.6, 5.2));
    float dBand = sdBox(qh, vec2(0.0, 49.5), vec2(4.6, 1.0));
    vec3 hatCol = mix(vec3(0.10, 0.11, 0.16), shade.rgb, 0.1);
    float aHat = (1.0 - smoothstep(-aa, aa, min(dBrim, dCrown))) * hp;
    res = over(vec4(hatCol * aHat, aHat), res);
    float aBand = (1.0 - smoothstep(-aa, aa, dBand)) * hp;
    res = over(vec4(scarf.rgb * aBand, aBand), res);

    fragColor = res * qt_Opacity;
}
