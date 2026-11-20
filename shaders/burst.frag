#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

// Shake-off bursts: up to 6 slots, drawn procedurally (clumps, powder, mist) with
// gravity, wind drift and fade. Everything is computed per pixel; no CPU particles.
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float tintMix;
    vec2 size;
    vec4 bA0; vec4 bA1; vec4 bA2; vec4 bA3; vec4 bA4; vec4 bA5;   // x, y, width, age (s)
    vec4 bB0; vec4 bB1; vec4 bB2; vec4 bB3; vec4 bB4; vec4 bB5;   // amount, wind, seed, active
    vec4 tint;
};

const float DUR = 1.5;

float hash(float n) { return fract(sin(n * 127.1 + 311.7) * 43758.5453); }

// One particle family falling from the edge. spacing: px between columns,
// gravity: px/s^2, soft: edge softness, stretch: vertical squash of the blob.
float family(vec2 p, vec4 A, vec4 B, float spacing, float rMin, float rMax,
             float gravity, float spread, float windGain, float windVar,
             float stretch, float alpha, float salt) {
    float t = A.w;
    float amount = B.x, wind = B.y, seed = B.z;
    float fade = smoothstep(0.0, 0.06, t) * (1.0 - smoothstep(0.40, 1.0, t / DUR));
    float drift = wind * 220.0 * windGain * t;
    float prob = clamp(amount * 1.15 + 0.12, 0.0, 1.0);
    int base = int(floor((p.x - A.x - drift) / spacing));
    float acc = 0.0;
    for (int k = -2; k <= 2; k++) {
        int i = base + k;
        float bx = (float(i) + 0.5) * spacing;
        if (bx < 0.0 || bx > A.z) continue;
        float n = float(i) * 1.37 + seed * 13.1 + salt;
        if (hash(n) > prob) continue;
        float hv = hash(n + 5.3), hg = hash(n + 9.1), hs = hash(n + 2.7), hr = hash(n + 7.7);
        float vf = 1.0 + (hv - 0.5) * windVar;
        float x = A.x + bx + (hs - 0.5) * spacing * 0.8 + drift * vf + (hr - 0.5) * spread * t;
        float y = A.y - hr * 4.0 + 24.0 * t + 0.5 * gravity * (0.7 + 0.6 * hg) * t * t;
        float r = mix(rMin, rMax, hs) * (0.55 + 0.75 * sqrt(clamp(amount, 0.0, 1.0)));
        vec2 d = vec2(p.x - x, (p.y - y) * stretch);
        float v = 1.0 - smoothstep(r * 0.35, r, length(d));
        acc = max(acc, v * (0.6 + 0.4 * hv));
    }
    return acc * alpha * fade;
}

float slotAlpha(vec2 p, vec4 A, vec4 B) {
    if (B.w < 0.5) return 0.0;
    float wd = B.y * 220.0 * 1.6;
    if (p.x < A.x - 60.0 + min(wd, 0.0) || p.x > A.x + A.z + 60.0 + max(wd, 0.0)) return 0.0;
    if (p.y < A.y - 40.0 || p.y > A.y + 580.0) return 0.0;
    float clump = family(p, A, B, 18.0, 2.5, 6.5, 430.0, 26.0, 0.8, 0.24, 1.0, 0.92, 0.0);
    float powder = family(p, A, B, 7.0, 0.9, 2.1, 230.0, 30.0, 1.0, 0.0, 0.55, 0.75, 41.0);
    float mist = family(p, A, B, 34.0, 16.0, 30.0, 70.0, 40.0, 1.1, 0.0, 1.0, 0.12, 83.0);
    return 1.0 - (1.0 - clump) * (1.0 - powder) * (1.0 - mist);
}

void main() {
    vec2 p = qt_TexCoord0 * size;
    float keep = 1.0;
    keep *= 1.0 - slotAlpha(p, bA0, bB0);
    keep *= 1.0 - slotAlpha(p, bA1, bB1);
    keep *= 1.0 - slotAlpha(p, bA2, bB2);
    keep *= 1.0 - slotAlpha(p, bA3, bB3);
    keep *= 1.0 - slotAlpha(p, bA4, bB4);
    keep *= 1.0 - slotAlpha(p, bA5, bB5);
    float a = (1.0 - keep) * qt_Opacity;
    vec3 col = mix(vec3(0.97, 0.98, 1.0), tint.rgb, tintMix);
    fragColor = vec4(col * a, a);    // premultiplied
}
