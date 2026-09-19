const assert = require("node:assert/strict")
const G = require("../Glow.js")
let n = 0
function t(name, fn) { n++; try { fn() } catch (e) { console.error("FAIL", name); throw e } }

t("dominant skips black, white, grey and transparent", () => {
  const px = [0,0,0,255, 255,255,255,255, 128,128,128,255, 200,30,30,0, 200,30,30,255, 180,40,40,255]
  assert.deepEqual(G.dominant(px), [190, 35, 35])
  assert.equal(G.dominant([0,0,0,255, 255,255,255,255]), null)
  assert.equal(G.dominant([]), null)
})

t("hsl round trip", () => {
  for (const c of [[200, 30, 30], [10, 200, 100], [40, 40, 200], [128, 128, 128]]) {
    const back = G.hslToRgb(G.rgbToHsl(c)).map(Math.round)
    assert.deepEqual(back, c)
  }
})

t("mix stays within 0.18 lightness of a dark background and away from it", () => {
  const out = G.mix([250, 20, 20], [100, 200, 255], [16, 19, 21])
  const l = G.rgbToHsl(out)[2], bg = G.rgbToHsl([16, 19, 21])[2]
  assert.ok(l <= bg + 0.18 + 0.01 && l >= bg, "l=" + l)
  assert.ok(l - bg >= 0.08 - 0.01)
  assert.ok(out.every(v => v >= 0 && v <= 255 && Number.isInteger(v)))
})

t("mix on a light background goes darker than it", () => {
  const out = G.mix([250, 20, 20], [100, 200, 255], [240, 240, 235])
  const l = G.rgbToHsl(out)[2], bg = G.rgbToHsl([240, 240, 235])[2]
  assert.ok(l < bg && l >= bg - 0.18 - 0.01, "l=" + l)
})

t("mix leans toward the accent hue", () => {
  const out = G.mix([255, 0, 0], [0, 0, 255], [16, 19, 21])
  assert.ok(out[2] > 0, "some blue from the accent survives")
})
console.log("test-glow: " + n + " passed")
