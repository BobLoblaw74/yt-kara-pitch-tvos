// Synthesizes the audience reaction sounds (clap, ovation, boo, laugh) as 44.1 kHz mono WAVs, so
// the app ships no third-party recordings. Run from the repo root:
//   swift scripts/make-sounds.swift
// To use real recordings instead, replace the files in KaraPitchTV/Resources/sounds, keeping the names.
import Foundation

let rate = 44_100.0
let outDir = URL(fileURLWithPath: "KaraPitchTV/Resources/sounds", isDirectory: true)

// MARK: - Building blocks

/// Deterministic, so re-running the script gives the same files.
struct RNG {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func uniform(_ range: ClosedRange<Double> = 0...1) -> Double {
        range.lowerBound + Double(next() >> 11) / Double(1 << 53) * (range.upperBound - range.lowerBound)
    }
    mutating func noise() -> Double { uniform(-1...1) }
}

/// RBJ band-pass with 0 dB peak gain.
struct BandPass {
    let b0, b2, a1, a2: Double
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    init(_ frequency: Double, q: Double) {
        let w = 2 * Double.pi * frequency / rate
        let alpha = sin(w) / (2 * q)
        let a0 = 1 + alpha
        b0 = alpha / a0
        b2 = -alpha / a0
        a1 = -2 * cos(w) / a0
        a2 = (1 - alpha) / a0
    }

    mutating func callAsFunction(_ x: Double) -> Double {
        let y = b0 * x + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x; y2 = y1; y1 = y
        return y
    }
}

/// Three formant resonators: what turns a buzz into a vowel.
struct Vowel {
    var filters: [BandPass]
    let gains: [Double]

    init(formants: [(f: Double, bandwidth: Double, gain: Double)], shift: Double) {
        filters = formants.map { BandPass($0.f * shift, q: $0.f * shift / $0.bandwidth) }
        gains = formants.map(\.gain)
    }

    mutating func callAsFunction(_ x: Double) -> Double {
        var y = 0.0
        for i in filters.indices { y += filters[i](x) * gains[i] }
        return y
    }
}

let oo: [(f: Double, bandwidth: Double, gain: Double)] = [(300, 60, 1), (870, 90, 0.45), (2240, 120, 0.12)]
let ah: [(f: Double, bandwidth: Double, gain: Double)] = [(750, 90, 1), (1200, 110, 0.7), (2500, 160, 0.2)]

func samples(_ seconds: Double) -> [Double] { [Double](repeating: 0, count: Int(seconds * rate)) }

/// Linear fade in over `attack` and out over the last `release` seconds.
func envelope(_ t: Double, length: Double, attack: Double, release: Double) -> Double {
    if t < 0 || t > length { return 0 }
    return min(1, t / attack, (length - t) / release)
}

/// One hand clap at `start`: a band-passed noise burst with a fast decay.
func addClap(_ out: inout [Double], at start: Double, gain: Double, rng: inout RNG) {
    var filter = BandPass(rng.uniform(900...1900), q: rng.uniform(0.9...1.6))
    let first = Int(start * rate)
    let decay = rng.uniform(0.008...0.016)
    for n in 0..<Int(0.09 * rate) where first + n < out.count {
        let t = Double(n) / rate
        let level = min(1, t / 0.0008) * exp(-t / decay)
        out[first + n] += filter(rng.noise()) * level * gain
    }
}

/// `count` people clapping out of step, each at their own pace.
func applause(seconds: Double, people: Int, swell: Double, fade: Double, seed: UInt64) -> [Double] {
    var rng = RNG(state: seed)
    var out = samples(seconds)
    for _ in 0..<people {
        let interval = 1 / rng.uniform(3.6...5.8)
        var t = rng.uniform(0...interval)
        let gain = rng.uniform(0.5...1)
        while t < seconds - 0.1 {
            addClap(&out, at: t, gain: gain * envelope(t, length: seconds, attack: swell, release: fade), rng: &rng)
            t += interval * rng.uniform(0.85...1.15)
        }
    }
    return out
}

/// A crowd sound under the claps: low band-passed noise.
func roar(seconds: Double, level: Double, seed: UInt64) -> [Double] {
    var rng = RNG(state: seed)
    var low = BandPass(420, q: 0.7), mid = BandPass(1100, q: 0.9)
    var out = samples(seconds)
    for n in out.indices {
        let x = rng.noise()
        let t = Double(n) / rate
        out[n] = (low(x) + 0.5 * mid(x)) * level * envelope(t, length: seconds, attack: 0.6, release: 1.4)
    }
    return out
}

/// A buzzing voice source at `pitch(t)` Hz, with a little breath.
struct Voice {
    var phase = 0.0
    var smooth = 0.0

    mutating func callAsFunction(pitch: Double, breath: Double, rng: inout RNG) -> Double {
        phase += pitch / rate
        if phase >= 1 { phase -= 1 }
        // A sawtooth softened by a one-pole low-pass is close enough to a glottal pulse here.
        smooth += 0.35 * ((1 - 2 * phase) - smooth)
        return smooth + breath * rng.noise()
    }
}

/// A crowd booing: many low "oo" voices that swell, hold and sag.
func boo(seconds: Double, seed: UInt64) -> [Double] {
    var rng = RNG(state: seed)
    var out = samples(seconds)
    for _ in 0..<14 {
        let f0 = rng.uniform(0...1) < 0.65 ? rng.uniform(85...130) : rng.uniform(165...230)
        let start = rng.uniform(0...0.35)
        let length = seconds - start - rng.uniform(0...0.4)
        let vibratoRate = rng.uniform(4.5...6), vibratoPhase = rng.uniform(0...6.28)
        let gain = rng.uniform(0.6...1)
        var vowel = Vowel(formants: oo, shift: f0 > 150 ? 1.12 : rng.uniform(0.95...1.03))
        var voice = Voice()
        for n in Int(start * rate)..<min(out.count, Int((start + length) * rate)) {
            let t = Double(n) / rate - start
            let pitch = f0 * (1 - 0.1 * t / length) * (1 + 0.015 * sin(2 * .pi * vibratoRate * t + vibratoPhase))
            let level = envelope(t, length: length, attack: 0.25, release: 0.6) * gain
            out[n] += vowel(voice(pitch: pitch, breath: 0.15, rng: &rng)) * level
        }
    }
    return out
}

/// A few people laughing: runs of "ha" that fall in pitch, each person on their own rhythm.
func laugh(seconds: Double, seed: UInt64) -> [Double] {
    var rng = RNG(state: seed)
    var out = samples(seconds)
    for person in 0..<6 {
        let base = person % 2 == 0 ? rng.uniform(170...230) : rng.uniform(260...340)
        let rate_ = rng.uniform(4.5...6)
        var t = rng.uniform(0...0.7)
        let syllables = Int(rng.uniform(7...11))
        let gain = rng.uniform(0.55...1)
        var vowel = Vowel(formants: ah, shift: base > 250 ? 1.15 : 1)
        var voice = Voice()
        for i in 0..<syllables where t < seconds - 0.25 {
            let fall = 1 - 0.25 * Double(i) / Double(syllables)
            let aspiration = 0.035, voiced = rng.uniform(0.08...0.11)
            let first = Int(t * rate)
            for n in 0..<Int((aspiration + voiced + 0.04) * rate) where first + n < out.count {
                let s = Double(n) / rate
                // "h": breath through the vowel shape, then "a": voiced, dropping in pitch.
                let breathy = s < aspiration
                let pitch = base * fall * (1 - 0.12 * max(0, s - aspiration) / voiced)
                let level = breathy
                    ? 0.5 * s / aspiration
                    : max(0, 1 - max(0, s - aspiration - voiced * 0.6) / (voiced * 0.4 + 0.04))
                let source = breathy ? rng.noise() * 1.6 : voice(pitch: pitch, breath: 0.25, rng: &rng)
                out[first + n] += vowel(source) * level * gain * (1 - 0.3 * Double(i) / Double(syllables))
            }
            t += 1 / rate_ * rng.uniform(0.9...1.1)
        }
    }
    return out
}

// MARK: - Output

func mix(_ tracks: [Double]...) -> [Double] {
    var out = samples(Double(tracks.map(\.count).max()!) / rate)
    for track in tracks { for n in track.indices { out[n] += track[n] } }
    return out
}

/// Scales to about the same loudness as the others (RMS `loudness`) without going over `peak`, and
/// fades the last 80 ms so the sound never ends on a click.
func finish(_ x: [Double], loudness: Double = 0.12, peak: Double = 0.95) -> [Double] {
    let top = x.map(abs).max() ?? 1
    let rms = sqrt(x.reduce(0) { $0 + $1 * $1 } / Double(x.count))
    let gain = min(loudness / rms, peak / top)
    let tail = Int(0.08 * rate)
    return x.enumerated().map { n, v in v * gain * min(1, Double(x.count - n) / Double(tail)) }
}

func writeWAV(_ x: [Double], name: String) throws {
    var data = Data()
    func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
    let bytes = UInt32(x.count * 2)
    data.append(contentsOf: Array("RIFF".utf8)); append(36 + bytes)
    data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
    append(UInt32(rate)); append(UInt32(rate) * 2); append(UInt16(2)); append(UInt16(16))
    data.append(contentsOf: Array("data".utf8)); append(bytes)
    for v in x { append(Int16(max(-1, min(1, v)) * 32767)) }
    let url = outDir.appendingPathComponent("\(name).wav")
    try data.write(to: url)
    let rms = sqrt(x.reduce(0) { $0 + $1 * $1 } / Double(x.count))
    print("\(url.path): \(String(format: "%.1f", Double(x.count) / rate)) s, rms \(String(format: "%.3f", rms))")
}

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
try writeWAV(finish(applause(seconds: 2.4, people: 4, swell: 0.05, fade: 0.6, seed: 1)), name: "clap")
try writeWAV(finish(mix(applause(seconds: 5, people: 45, swell: 0.8, fade: 1.6, seed: 2), roar(seconds: 5, level: 0.35, seed: 3))), name: "ovation")
try writeWAV(finish(boo(seconds: 3, seed: 4)), name: "boo")
try writeWAV(finish(laugh(seconds: 3, seed: 5)), name: "laugh")
