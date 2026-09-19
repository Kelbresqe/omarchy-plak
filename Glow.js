// Glow.js — art colour → theme-safe glow colour. Pure functions, node-tested.

// Mean of the saturated, mid-luminance pixels of an RGBA buffer; null when
// nothing qualifies (a black-and-white cover gets the accent instead).
function dominant(px) {
  var r = 0, g = 0, b = 0, n = 0
  for (var i = 0; i + 3 < px.length; i += 4) {
    var R = px[i], G = px[i + 1], B = px[i + 2]
    if (px[i + 3] < 128) continue
    var max = Math.max(R, G, B), min = Math.min(R, G, B)
    var lum = (max + min) / 2
    if (lum < 25 || lum > 235) continue           // near black / near white
    if (max - min < 24) continue                  // grey
    r += R; g += G; b += B; n++
  }
  if (n === 0) return null
  return [r / n, g / n, b / n]
}

function rgbToHsl(c) {
  var r = c[0] / 255, g = c[1] / 255, b = c[2] / 255
  var max = Math.max(r, g, b), min = Math.min(r, g, b)
  var h = 0, s = 0, l = (max + min) / 2
  if (max !== min) {
    var d = max - min
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
    if (max === r) h = (g - b) / d + (g < b ? 6 : 0)
    else if (max === g) h = (b - r) / d + 2
    else h = (r - g) / d + 4
    h /= 6
  }
  return [h, s, l]
}

function hue2rgb(p, q, t) {
  if (t < 0) t += 1
  if (t > 1) t -= 1
  if (t < 1 / 6) return p + (q - p) * 6 * t
  if (t < 1 / 2) return q
  if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6
  return p
}

function hslToRgb(c) {
  var h = c[0], s = c[1], l = c[2], r, g, b
  if (s === 0) { r = g = b = l }
  else {
    var q = l < 0.5 ? l * (1 + s) : l + s - l * s
    var p = 2 * l - q
    r = hue2rgb(p, q, h + 1 / 3); g = hue2rgb(p, q, h); b = hue2rgb(p, q, h - 1 / 3)
  }
  return [r * 255, g * 255, b * 255]
}

// 60 % art, 40 % accent, then lightness clamped to within 0.18 of the theme
// background's so the glow never blows out a dark theme or muddies a light one.
function mix(art, accent, background) {
  var m = [art[0] * 0.6 + accent[0] * 0.4, art[1] * 0.6 + accent[1] * 0.4, art[2] * 0.6 + accent[2] * 0.4]
  var hsl = rgbToHsl(m)
  var bgL = rgbToHsl(background)[2]
  var lo = Math.max(0, bgL - 0.18), hi = Math.min(1, bgL + 0.18)
  // Push away from the background rather than toward it: a glow the same
  // lightness as the backdrop is invisible.
  var target = bgL < 0.5 ? hi : lo
  hsl[2] = Math.max(lo, Math.min(hi, hsl[2]))
  if (Math.abs(hsl[2] - bgL) < 0.08) hsl[2] = target
  hsl[1] = Math.min(0.85, Math.max(0.35, hsl[1]))
  var out = hslToRgb(hsl)
  return [Math.round(out[0]), Math.round(out[1]), Math.round(out[2])]
}

if (typeof module !== "undefined") module.exports = { dominant: dominant, mix: mix, rgbToHsl: rgbToHsl, hslToRgb: hslToRgb }
