.pragma library

// Deterministic contour finder for the wallpaper. Input is RGBA pixels of the wallpaper as it
// appears on screen, downscaled so one sample = `cell` screen px. Output is a list of contours
// [{ pts: [x0, y0, x1, y1, ...] }] in screen px, left to right, where snow can settle.
//
// 1. luminance, blurred more along x than y, 2. Sobel gradients with an adaptive threshold,
// 3. keep edges flatter than 45 degrees, thinned to one sample per column, 4. trace each edge
// left to right, stepping at most one row per column, 5. drop undersides of floating shapes
// (clouds, logos), 6. keep the longest, strongest, smoothest contours and smooth them.
function detect(px, w, h, cell, opts) {
  opts = opts || {}
  var maxThreshold = opts.threshold || 28  // gradient strength cap, 0..255
  var minSpan = opts.minSpan || 24         // samples (x extent) a contour needs
  var maxCount = opts.maxCount || 14
  var topSkip = Math.round(h * (opts.topSkip || 0.04))

  var lum = new Float32Array(w * h)
  for (var i = 0, p = 0; i < w * h; i++, p += 4)
    lum[i] = 0.299 * px[p] + 0.587 * px[p + 1] + 0.114 * px[p + 2]

  // Separable box blur, stronger along x than y: removes vertical texture (grass, trees) and
  // resampling noise while keeping thin horizontal ridges and rim lights sharp.
  var tmp = new Float32Array(w * h)
  function boxX(src, dst, r) {
    for (var yb = 0; yb < h; yb++)
      for (var xb = 0; xb < w; xb++) {
        var s0 = 0, n0 = 0
        for (var o = -r; o <= r; o++) { var xo = xb + o; if (xo >= 0 && xo < w) { s0 += src[yb * w + xo]; n0++ } }
        dst[yb * w + xb] = s0 / n0
      }
  }
  function boxY(src, dst, r) {
    for (var yb = 0; yb < h; yb++)
      for (var xb = 0; xb < w; xb++) {
        var s0 = 0, n0 = 0
        for (var o = -r; o <= r; o++) { var yo = yb + o; if (yo >= 0 && yo < h) { s0 += src[yo * w + xb]; n0++ } }
        dst[yb * w + xb] = s0 / n0
      }
  }
  boxX(lum, tmp, 2); boxX(tmp, lum, 2); boxY(lum, tmp, 1)
  var sw = lum; lum = tmp; tmp = sw

  // Sobel |gy| and |gx|, 0..255.
  var GY = new Float32Array(w * h), GX = new Float32Array(w * h)
  var hist = new Uint32Array(256)
  var x, y
  for (y = 1; y < h - 1; y++) {
    for (x = 1; x < w - 1; x++) {
      var a = (y - 1) * w + x, b = y * w + x, c = (y + 1) * w + x
      var gy = (lum[c - 1] + 2 * lum[c] + lum[c + 1]) - (lum[a - 1] + 2 * lum[a] + lum[a + 1])
      var gx = (lum[a + 1] + 2 * lum[b + 1] + lum[c + 1]) - (lum[a - 1] + 2 * lum[b - 1] + lum[c - 1])
      GY[b] = Math.abs(gy) / 4; GX[b] = Math.abs(gx) / 4
      hist[Math.min(255, GY[b] | 0)]++
    }
  }

  // Adaptive threshold: the strongest ~4% of vertical gradients (dark wallpapers still work).
  function pctOf(hg, count) {
    var tgt = count * 0.04, sum0 = 0
    for (var t = 255; t >= 0; t--) { sum0 += hg[t]; if (sum0 >= tgt) return t }
    return 255
  }
  var threshold = Math.max(6, Math.min(maxThreshold, pctOf(hist, (w - 2) * (h - 2))))

  // Edge samples: strong, flatter than 45 degrees, local maximum along y (thin lines).
  var str = new Float32Array(w * h)
  for (y = Math.max(2, topSkip); y < h - 2; y++) {
    var ty = threshold
    for (x = 1; x < w - 1; x++) {
      var k = y * w + x, v = GY[k]
      if (v >= ty && v >= GX[k] && v >= GY[k - w] && v > GY[k + w]) str[k] = v
    }
  }

  // Trace left to right. Each step goes to the next column (or skips one column) and moves at
  // most one row per column; the strongest unused candidate wins.
  var used = new Uint8Array(w * h)
  var chains = []
  for (x = 1; x < w - 1; x++) {
    for (y = 2; y < h - 2; y++) {
      if (!str[y * w + x] || used[y * w + x]) continue
      var cx = x, cy = y, pts = [cx, cy], sum = str[y * w + x], pdy = 0
      used[y * w + x] = 1
      for (;;) {
        var best = -1, by = 0, bx = 0
        for (var step = 1; step <= 2 && best < 0; step++) {
          var nx = cx + step
          if (nx >= w - 1) break
          for (var dy = -step; dy <= step; dy++) {
            var ny = cy + dy
            if (ny < 2 || ny >= h - 2) continue
            var s = str[ny * w + nx]
            if (!s || used[ny * w + nx]) continue
            var sc = s * (1 - 0.3 * Math.abs(dy / step - pdy))   // keep direction, avoid zigzags
            if (sc > best) { best = sc; by = ny; bx = nx }
          }
        }
        if (best < 0) break
        if (bx - cx === 2) pts.push(cx + 1, (cy + by) / 2)     // fill the skipped column
        pts.push(bx, by)
        used[by * w + bx] = 1
        sum += best
        pdy = 0.6 * pdy + 0.4 * (by - cy) / (bx - cx)
        cx = bx; cy = by
      }
      var span = cx - x
      if (span < minSpan) continue
      var m0 = pts.length / 2, wig = 0
      for (var wi = 1; wi < m0 - 1; wi++) wig += Math.abs(pts[2 * wi + 3] - 2 * pts[2 * wi + 1] + pts[2 * wi - 1])
      wig /= m0                                              // rows of direction change per sample
      chains.push({ pts: pts, score: span * (sum / m0) / (1 + 3 * wig) })
    }
  }

  // Snow lies on top of things, not under them. A contour is the underside of a floating band
  // (cloud, logo) when, scanning up past the band to the next edge, the colour beyond matches
  // the colour below the contour while the band itself differs from both. Stacked hills pass:
  // sky, far hill and near hill all differ.
  function colAt(cx0, cy0) {
    var r = 0, g2 = 0, b2 = 0, cn = 0
    for (var yy = cy0 - 1; yy <= cy0 + 1; yy++)
      for (var xx = cx0 - 1; xx <= cx0 + 1; xx++) {
        if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue
        var cp = 4 * (yy * w + xx); r += px[cp]; g2 += px[cp + 1]; b2 += px[cp + 2]; cn++
      }
    return [r / cn, g2 / cn, b2 / cn]
  }
  function dist3(a3, b3) { var dr = a3[0] - b3[0], dg = a3[1] - b3[1], db = a3[2] - b3[2]; return Math.sqrt(dr * dr + dg * dg + db * db) }
  var off = 3, maxBand = Math.round(h * 0.3)
  function isUnderside(ch) {
    var under = 0, all = 0
    for (var ci = 0; ci < ch.pts.length; ci += 4) {
      var cx1 = ch.pts[ci], cy1 = Math.round(ch.pts[ci + 1])
      var below = colAt(cx1, cy1 + off), band = colAt(cx1, cy1 - off)
      all++
      var ey = -1
      for (var yy = cy1 - off - 1; yy > Math.max(1, cy1 - maxBand); yy--)
        if (GY[yy * w + cx1] >= threshold) { ey = yy; break }
      if (ey < 0) continue                                   // open above: a top surface
      var beyond = colAt(cx1, ey - off)
      if (dist3(beyond, below) < 0.6 * dist3(band, below)) under++
    }
    return under > 0.5 * all
  }
  chains = chains.filter(function(ch) { return !isUnderside(ch) })

  chains.sort(function(p, q) { return q.score - p.score || p.pts[1] - q.pts[1] || p.pts[0] - q.pts[0] })
  chains = chains.slice(0, maxCount)

  // Smooth y (moving average over 7 samples) and convert to screen px at sample centers.
  var out = []
  for (var n = 0; n < chains.length; n++) {
    var src = chains[n].pts, m = src.length / 2, dst = []
    for (var j = 0; j < m; j++) {
      var sy = 0, cnt = 0
      for (var q = Math.max(0, j - 3); q <= Math.min(m - 1, j + 3); q++) { sy += src[2 * q + 1]; cnt++ }
      dst.push((src[2 * j] + 0.5) * cell, (sy / cnt + 0.5) * cell)
    }
    out.push({ pts: dst })
  }
  return out
}
