#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

// Flake motion is driven by monotonically integrated phases computed on the QML side in
// double precision (Service.qml: windPhase / fallPhase). The service converts them into one
// lattice offset per pass (o0..o5, in cells, already reduced modulo LATTICE) so the shader never
// multiplies elapsed time by a changing speed, and the wrap is seamless: the cell hash is
// periodic in LATTICE cells, so reducing the offset by LATTICE cells changes nothing on screen.
// Keep the plane tables below in sync with SnowLayer.qml.
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float sway;       // seconds wrapped on a seamless period (rates below are multiples of 0.1)
    float kind;       // 0 = six depth planes behind windows, 1 = two foreground planes
    float amount;     // 0.1..2.5 how many particles spawn (eased by the service)
    float psize;      // 0.5..2.2 particle radius multiplier (eased by the service)
    float tintMix;    // how far snow is pulled toward the theme tint
    vec2 size;        // item size in px
    vec4 o0;          // per plane: xy = main pass lattice offset, zw = second (amount > 1) pass offset
    vec4 o1;
    vec4 o2;
    vec4 o3;
    vec4 o4;
    vec4 o5;
    vec4 tint;        // theme tint color
};

const float LATTICE = 1024.0;   // hash period in cells; must match SnowLayer.qml

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// One jittered-grid pass: at most one flake per cell. Radius is clamped to the cell and the
// in-cell jitter shrinks as the flake grows, so large flakes never touch the cell border
// (no hard square edges). Every cell has its own random vertical position, so there are no rows.
float pass(vec2 p, float cell, vec2 off, float rMin, float rMax, float softness,
           float prob, float seed, float ang, float swayPx) {
    prob = min(prob, 0.96);
    if (prob <= 0.0) return 0.0;
    float ca = cos(ang), sa = sin(ang);
    vec2 qc = (mat2(ca, -sa, sa, ca) * p) / cell - off;   // rotated lattice so planes never line up
    vec2 base = floor(qc);
    vec2 f = qc - base;
    vec2 id = mod(base, LATTICE);                          // periodic hash domain (seamless wrap)
    float h1 = hash21(id + seed);
    if (h1 > prob) return 0.0;
    float h2 = hash21(id + seed + 17.3);
    float h3 = hash21(id * 1.7 + seed + 3.1);
    float h4 = hash21(id * 2.3 + seed + 9.7);
    float sw = min(swayPx, 0.12 * cell);
    float r = min(mix(rMin, rMax, h2) * psize, 0.42 * cell - sw);
    float room = max(0.0, 0.5 - (r + sw) / cell);          // jitter budget shrinks with size
    vec2 c = vec2(0.5) + (vec2(h3, h4) - 0.5) * 2.0 * room;
    float ph = h3 * 6.2831;
    float rateA = 0.5 + 0.1 * floor(h4 * 7.0);             // 0.5 .. 1.1, multiples of 0.1
    float rateB = 0.4 + 0.1 * floor(h3 * 7.0);             // 0.4 .. 1.0, multiples of 0.1
    c.x += sin(sway * rateA + ph) * sw / cell;
    c.y += cos(sway * rateB + ph) * sw * 0.4 / cell;
    float d = length((f - c) * cell);
    return (1.0 - smoothstep(r * (1.0 - softness), r, d)) * (0.55 + 0.45 * h1 / max(prob, 0.001));
}

// A depth plane = main pass (probability scales with amount up to 1x) plus, above 1x, an
// independent second pass on an offset lattice whose probability keeps growing. More amount
// means more flakes spawning, never just a brighter image.
float plane(vec2 p, float cell, vec4 off, float rMin, float rMax, float softness,
            float prob, float seed, float ang, float swayPx) {
    float a = pass(p, cell, off.xy, rMin, rMax, softness, prob * min(amount, 1.0), seed, ang, swayPx);
    if (amount > 1.0) {
        float b = pass(p + vec2(37.0, 61.0), cell * 1.17, off.zw, rMin, rMax, softness,
                       prob * 0.9 * (amount - 1.0), seed + 101.0, ang + 0.9, swayPx);
        a = 1.0 - (1.0 - a) * (1.0 - b);
    }
    return a;
}

void main() {
    vec2 p = qt_TexCoord0 * size;
    float a = 0.0;
    vec3 acc = vec3(0.0);                      // premultiplied accumulation, far to near

    if (kind < 0.5) {
        // six dense parallax planes, tight cells, tiny crisp distant flakes through larger soft near flakes
        float al; vec3 c;
        al = plane(p, 12.0, o0, 0.35, 0.70, 0.35, 0.50, 1.0, 0.31, 2.0) * 0.55;
        c = vec3(0.84, 0.91, 1.0);  acc = acc * (1.0 - al) + c * al; a = a + al * (1.0 - a);
        al = plane(p, 18.0, o1, 0.45, 0.95, 0.35, 0.50, 3.0, 0.83, 3.0) * 0.65;
        c = vec3(0.86, 0.92, 1.0);  acc = acc * (1.0 - al) + c * al; a = a + al * (1.0 - a);
        al = plane(p, 28.0, o2, 0.80, 1.50, 0.45, 0.52, 7.0, 1.21, 5.0) * 0.78;
        c = vec3(0.90, 0.95, 1.0);  acc = acc * (1.0 - al) + c * al; a = a + al * (1.0 - a);
        al = plane(p, 42.0, o3, 1.20, 2.30, 0.50, 0.52, 11.0, 1.77, 8.0) * 0.88;
        c = vec3(0.95, 0.97, 1.0);  acc = acc * (1.0 - al) + c * al; a = a + al * (1.0 - a);
        al = plane(p, 64.0, o4, 2.00, 3.60, 0.60, 0.48, 19.0, 0.59, 12.0) * 0.92;
        c = vec3(1.0);              acc = acc * (1.0 - al) + c * al; a = a + al * (1.0 - a);
        al = plane(p, 96.0, o5, 3.20, 5.40, 0.75, 0.42, 29.0, 2.10, 16.0) * 0.80;
        c = vec3(1.0);              acc = acc * (1.0 - al) + c * al; a = a + al * (1.0 - a);
    } else {
        // two subtle foreground planes: mid-large flakes and out-of-focus bokeh
        float al = plane(p, 100.0, o0, 4.0, 8.0, 0.85, 0.22, 37.0, 1.43, 20.0) * 0.28;
        acc = vec3(0.96, 0.98, 1.0) * al; a = al;
        float ab = plane(p, 180.0, o1, 9.0, 20.0, 0.97, 0.22, 23.0, 0.57, 26.0) * 0.20;
        acc = acc * (1.0 - ab) + vec3(0.95, 0.97, 1.0) * ab; a = a + ab * (1.0 - a);
    }

    vec3 col = acc / max(a, 0.001);
    col = mix(col, tint.rgb, tintMix);
    a *= qt_Opacity;
    fragColor = vec4(col * a, a);    // premultiplied
}
