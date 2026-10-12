// Run with: node tests/model.test.js
const fs = require("fs")
const path = require("path")
const assert = require("assert")

const src = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8").replace(/^\.pragma library\s*/, "")
const M = new Function(src + "; return { parseDuration, formatDuration, remainingSeconds, nextTickDelay, clockString, soundOptions }")()

const parse = [
  ["90", 90], ["1h 30m 10s", 5410], ["1.5m", 90], ["25m", 1500], ["1H30M", 5400],
  ["", 0], ["abc", 0], ["  45s ", 45], ["2h", 7200], ["0", 0],
]
for (const [input, want] of parse) assert.strictEqual(M.parseDuration(input), want, `parse ${input}`)

const format = [[0, "0s"], [45, "45s"], [60, "1m"], [90, "1m30s"], [3600, "1h"], [3661, "1h1m1s"], [3930, "1h5m30s"]]
for (const [secs, want] of format) assert.strictEqual(M.formatDuration(secs), want, `format ${secs}`)

// Everything formatted parses back to itself.
for (let s = 0; s < 4000; s += 7) assert.strictEqual(M.parseDuration(M.formatDuration(s)), s)

assert.strictEqual(M.remainingSeconds(10000, 9001), 1)
assert.strictEqual(M.remainingSeconds(10000, 10000), 0)
assert.strictEqual(M.remainingSeconds(10000, 8999), 2)
assert.strictEqual(M.nextTickDelay(10000, 8500), 504)
assert.strictEqual(M.nextTickDelay(10000, 9000), 1004)
assert.strictEqual(M.nextTickDelay(10000, 10001), 0)

const opts = M.soundOptions(["bell", "zzz", "audio-channel-front-left", "complete"])
assert.deepStrictEqual(opts.map(o => o.value),
  ["none", "builtin-chime", "builtin-bell", "builtin-click", "complete", "bell", "zzz"])

console.log("ok")
