// Synthesises OsumTimer's own alarm tones, with no samples or sound libraries
// involved — every one is a handful of decaying sine waves and a reverb.
//
// The system sounds are short and bright: they are built to cut through, which
// is right for an error and wrong for the end of a focus session. These are the
// opposite brief. Low-to-mid pitches, soft attacks, long natural decays, and
// room around them, so the sound arrives rather than interrupts. Each one is
// modelled on a real instrument's physics — the inharmonic overtones of a bowl,
// a bell, a tine, a bar — because that is what makes a tone read as an object
// being struck rather than as a beep.
//
// Each file is also one loop of the alarm: the app repeats it for as long as
// the ring setting says, so every sound fades to silence before it ends and
// the next strike lands like the next breath.
//
// Usage: swift scripts/make-sounds.swift <output-directory>
// (Compiled with -O by package.sh; interpreted, it works but takes a while.)

import Foundation

let rate = 48_000.0
let twoPi = 2 * Double.pi
/// Natural-log drop over a T60: the amplitude falls a thousandfold (−60 dB).
let ln1000 = log(1000.0)

// MARK: - Building blocks

/// SplitMix64. Seeded, so a rebuild produces the same files bit for bit.
struct Random {
    var state: UInt64
    /// Uniform in [-1, 1).
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(UInt64(1) << 53) * 2 - 1
    }
}

/// Constant-power pan, scaled so a centred voice keeps unity gain.
func panGains(_ pan: Double) -> (Double, Double) {
    let angle = (pan + 1) * .pi / 4
    return (cos(angle) * 2.0.squareRoot(), sin(angle) * 2.0.squareRoot())
}

/// A raised-cosine ramp from 0 to 1. Even a 1 ms attack is enough to keep a
/// sine starting at full amplitude from clicking.
func ramp(_ t: Double, over attack: Double) -> Double {
    t >= attack ? 1 : 0.5 - 0.5 * cos(.pi * t / attack)
}

final class Track {
    var left: [Double]
    var right: [Double]
    var count: Int { left.count }

    init(seconds: Double) {
        left = Array(repeating: 0, count: Int(seconds * rate))
        right = left
    }

    /// Mixes in one voice, `sample(t)` with t in seconds since its onset.
    func add(at onset: Double, pan: Double = 0, length: Double? = nil, _ sample: (Double) -> Double) {
        let start = Int(onset * rate)
        let end = length.map { min(count, start + Int($0 * rate)) } ?? count
        guard start < end else { return }
        let (gl, gr) = panGains(pan)
        for i in start..<end {
            let s = sample(Double(i - start) / rate)
            left[i] += s * gl
            right[i] += s * gr
        }
    }
}

/// One resonance of a struck body.
struct Mode {
    /// Frequency as a multiple of the fundamental. Rarely a whole number:
    /// bowls, bells and bars are not strings.
    var ratio: Double
    var amp: Double
    /// Seconds to fall by 60 dB.
    var t60: Double
    /// Hz between the two halves of a split mode. A round body that is not
    /// perfectly round rings each mode as a near-identical pair, and the slow
    /// beating between them is the "wah-wah" of a singing bowl.
    var beat: Double = 0
    /// How far apart in the stereo field the two halves sit, so the beating
    /// also drifts from side to side.
    var spread: Double = 0
}

/// Strikes a resonant body: every mode starts at once and dies exponentially.
/// A softer strike excites the upper modes less, as a real mallet does.
func strike(
    _ track: Track, at onset: Double, fundamental f: Double, modes: [Mode],
    velocity: Double = 1, pan: Double = 0, attack: Double = 0.002
) {
    for mode in modes {
        let amp = mode.amp * velocity * pow(velocity, max(0, log2(mode.ratio)) * 0.5)
        // Past −96 dB it is below the 16-bit floor; stop computing it.
        let length = mode.t60 * 1.6
        let halves: [(freq: Double, amp: Double, pan: Double)] = mode.beat == 0
            ? [(f * mode.ratio, amp, pan)]
            : [(f * mode.ratio - mode.beat / 2, amp / 2, pan - mode.spread),
               (f * mode.ratio + mode.beat / 2, amp / 2, pan + mode.spread)]
        for half in halves {
            let w = twoPi * half.freq
            let decay = ln1000 / mode.t60
            track.add(at: onset, pan: max(-1, min(1, half.pan)), length: length) { t in
                half.amp * ramp(t, over: attack) * exp(-decay * t) * sin(w * t)
            }
        }
    }
}

/// Freeverb (Jezar at Dreampoint, public domain): eight damped combs into four
/// allpasses per channel, the right side's delays offset so the two decorrelate
/// into width. Its tunings are for 44.1 kHz and are scaled to ours.
func reverb(_ track: Track, room: Double, damping: Double, wet: Double, predelay: Double = 0.015) {
    struct Comb {
        var buffer: [Double], index = 0, store = 0.0
        mutating func run(_ x: Double, feedback: Double, damp: Double) -> Double {
            let out = buffer[index]
            store = out * (1 - damp) + store * damp
            buffer[index] = x + store * feedback
            index = index + 1 == buffer.count ? 0 : index + 1
            return out
        }
    }
    struct Allpass {
        var buffer: [Double], index = 0
        mutating func run(_ x: Double) -> Double {
            let delayed = buffer[index]
            buffer[index] = x + delayed * 0.5
            index = index + 1 == buffer.count ? 0 : index + 1
            return delayed - x
        }
    }

    let scale = rate / 44_100
    let combTunings = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
    let allpassTunings = [556, 441, 341, 225]
    let spread = 23
    func combs(_ offset: Int) -> [Comb] {
        combTunings.map { Comb(buffer: Array(repeating: 0, count: Int(Double($0 + offset) * scale))) }
    }
    func allpasses(_ offset: Int) -> [Allpass] {
        allpassTunings.map { Allpass(buffer: Array(repeating: 0, count: Int(Double($0 + offset) * scale))) }
    }
    var combsL = combs(0), combsR = combs(spread)
    var allL = allpasses(0), allR = allpasses(spread)
    let feedback = room * 0.28 + 0.7
    let damp = damping * 0.4
    let lag = Int(predelay * rate)

    var outL = [Double](repeating: 0, count: track.count)
    var outR = outL
    for i in 0..<track.count {
        let j = i - lag
        let input = j >= 0 ? (track.left[j] + track.right[j]) * 0.015 : 0
        var l = 0.0, r = 0.0
        for k in 0..<combsL.count {
            l += combsL[k].run(input, feedback: feedback, damp: damp)
            r += combsR[k].run(input, feedback: feedback, damp: damp)
        }
        for k in 0..<allL.count {
            l = allL[k].run(l)
            r = allR[k].run(r)
        }
        outL[i] = l
        outR[i] = r
    }
    for i in 0..<track.count {
        track.left[i] += outL[i] * wet
        track.right[i] += outR[i] * wet
    }
}

/// Fades the tail to true silence — the loop restarts on the last sample —
/// and sets the level. Gentle sounds are mostly quiet tail, so matching peaks
/// would leave them all much softer than the system sounds; instead the
/// loudest half second is brought to a common RMS, with the peak kept clear of
/// clipping.
func finish(_ track: Track, fade: Double = 0.6) {
    // Cut the tail once it is 30 dB under the loudest moment, plus a short fade.
    // Past that it is a faint tail an alarm can lose, and since the alarm loops the
    // file, every second of near-silence is a second of gap between strikes.
    let step = Int(0.05 * rate)
    var levels: [Double] = []
    for start in stride(from: 0, to: track.count, by: step) {
        let end = min(track.count, start + step)
        var e = 0.0
        for i in start..<end { e += track.left[i] * track.left[i] + track.right[i] * track.right[i] }
        levels.append(e / Double(end - start))
    }
    let floor = (levels.max() ?? 0) * pow(10, -30.0 / 10)
    let audible = (levels.lastIndex { $0 > floor } ?? 0) + 1
    let fade = min(fade, 0.2)
    let length = min(track.count, audible * step + Int(fade * rate))
    track.left.removeSubrange(length...)
    track.right.removeSubrange(length...)

    let fadeStart = track.count - Int(fade * rate)
    for i in fadeStart..<track.count {
        let g = 0.5 + 0.5 * cos(.pi * Double(i - fadeStart) / Double(track.count - fadeStart))
        track.left[i] *= g
        track.right[i] *= g
    }

    let window = Int(0.5 * rate)
    var sum = 0.0, loudest = 0.0, peak = 0.0
    for i in 0..<track.count {
        let e = (track.left[i] * track.left[i] + track.right[i] * track.right[i]) / 2
        sum += e
        if i >= window {
            let o = (track.left[i - window] * track.left[i - window] + track.right[i - window] * track.right[i - window]) / 2
            sum -= o
        }
        loudest = max(loudest, sum)
        peak = max(peak, abs(track.left[i]), abs(track.right[i]))
    }
    let rms = (loudest / Double(window)).squareRoot()
    let gain = min(0.07 / rms, 0.93 / peak)
    for i in 0..<track.count {
        track.left[i] *= gain
        track.right[i] *= gain
    }
}

/// 16-bit stereo PCM with TPDF dither, so the long fade-outs decay into noise
/// rather than into quantisation crackle.
func wav(_ track: Track) -> Data {
    var samples = [Int16]()
    samples.reserveCapacity(track.count * 2)
    var random = Random(state: 0x05_0D)
    for i in 0..<track.count {
        for s in [track.left[i], track.right[i]] {
            let dithered = s * 32_767 + (random.next() + random.next()) * 0.5
            samples.append(Int16(max(-32_768, min(32_767, dithered.rounded()))))
        }
    }

    var data = Data()
    func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    let bytes = UInt32(samples.count * 2)
    data.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes)
    data.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16)
    u16(1); u16(2); u32(UInt32(rate)); u32(UInt32(rate) * 4); u16(4); u16(16)
    data.append(contentsOf: Array("data".utf8)); u32(bytes)
    samples.withUnsafeBytes { raw in
        // Int16 is little-endian on every Mac this builds on.
        data.append(contentsOf: raw)
    }
    return data
}

// MARK: - The sounds

/// A large Himalayan singing bowl struck once with a felt mallet. Bowl modes
/// sit at roughly 1 : 2.76 : 5.12 : 8.07, and each is a beating pair, so the
/// tone breathes and wanders across the stereo field as it fades.
func bowl() -> Track {
    let track = Track(seconds: 7)
    strike(track, at: 0.01, fundamental: 196, modes: [
        Mode(ratio: 1.00, amp: 1.00, t60: 8.0, beat: 0.9, spread: 0.45),
        Mode(ratio: 2.76, amp: 0.55, t60: 5.5, beat: 1.7, spread: 0.35),
        Mode(ratio: 5.12, amp: 0.22, t60: 3.0, beat: 2.3, spread: 0.3),
        Mode(ratio: 8.07, amp: 0.09, t60: 1.6, beat: 3.1, spread: 0.3),
        Mode(ratio: 11.4, amp: 0.035, t60: 0.8, beat: 3.7, spread: 0.2),
    ], attack: 0.004)
    reverb(track, room: 0.75, damping: 0.5, wet: 0.35)
    finish(track, fade: 1.2)
    return track
}

/// A pure quartz crystal bowl: almost a sine, the overtones barely there, with
/// a slow shimmer and a rubber-mallet attack you hear as a bloom, not a hit.
func crystal() -> Track {
    let track = Track(seconds: 6.5)
    strike(track, at: 0.01, fundamental: 392, modes: [
        Mode(ratio: 1.00, amp: 1.00, t60: 7.5, beat: 0.6, spread: 0.5),
        Mode(ratio: 2.00, amp: 0.04, t60: 3.0, beat: 0.9, spread: 0.3),
        Mode(ratio: 2.92, amp: 0.05, t60: 2.5, beat: 1.4, spread: 0.3),
    ], attack: 0.03)
    reverb(track, room: 0.85, damping: 0.45, wet: 0.4)
    finish(track, fade: 1.2)
    return track
}

/// A bronze temple bell, heard from across the courtyard. Bell partials are
/// named for where they sit against the strike note: a hum an octave below, a
/// minor-third "tierce" that gives bells their wistful colour, a quint, and a
/// nominal an octave up — plus a cluster of short inharmonic modes that make
/// the clang of the strike itself.
func temple() -> Track {
    let track = Track(seconds: 7)
    strike(track, at: 0.01, fundamental: 207.65, modes: [
        Mode(ratio: 0.50, amp: 0.55, t60: 9.0, beat: 0.35, spread: 0.3),
        Mode(ratio: 1.00, amp: 0.70, t60: 7.0, beat: 0.5, spread: 0.3),
        Mode(ratio: 1.19, amp: 0.45, t60: 5.0, beat: 0.6, spread: 0.3),
        Mode(ratio: 1.50, amp: 0.22, t60: 3.0),
        Mode(ratio: 2.00, amp: 0.55, t60: 4.5, beat: 0.8, spread: 0.25),
        Mode(ratio: 2.66, amp: 0.18, t60: 2.5),
        Mode(ratio: 4.00, amp: 0.10, t60: 1.4),
        Mode(ratio: 3.05, amp: 0.06, t60: 0.35),
        Mode(ratio: 3.62, amp: 0.05, t60: 0.3),
        Mode(ratio: 4.61, amp: 0.05, t60: 0.25),
        Mode(ratio: 5.93, amp: 0.04, t60: 0.2),
        Mode(ratio: 7.21, amp: 0.03, t60: 0.15),
    ], attack: 0.002)
    reverb(track, room: 0.88, damping: 0.35, wet: 0.45)
    finish(track, fade: 1.2)
    return track
}

/// Three kalimba tines falling to the tonic — D, B, G — the shape of "done".
/// A tine is a clamped bar, so its overtones are far from harmonic (6.27×,
/// 17.55×) and die almost at once, leaving the warm fundamental.
func kalimba() -> Track {
    let track = Track(seconds: 4)
    let tine = [
        Mode(ratio: 1.00, amp: 1.00, t60: 2.4),
        Mode(ratio: 2.00, amp: 0.06, t60: 0.6),
        Mode(ratio: 6.27, amp: 0.13, t60: 0.25),
        Mode(ratio: 17.55, amp: 0.04, t60: 0.06),
    ]
    for (i, note) in [(587.33, 0.9, -0.25), (493.88, 0.8, 0.2), (392.0, 1.0, 0.0)].enumerated() {
        strike(track, at: 0.01 + Double(i) * 0.24, fundamental: note.0, modes: tine,
               velocity: note.1, pan: note.2, attack: 0.0008)
    }
    reverb(track, room: 0.6, damping: 0.5, wet: 0.28)
    finish(track, fade: 0.8)
    return track
}

/// Two low rosewood marimba bars, a falling fifth. The bars are tuned so their
/// overtones land near 4× and 10×, and the resonator tube under each one holds
/// the fundamental long after the wood's own knock has gone.
func marimba() -> Track {
    let track = Track(seconds: 3.5)
    let bar = [
        Mode(ratio: 1.00, amp: 1.00, t60: 1.9),
        Mode(ratio: 3.99, amp: 0.22, t60: 0.45),
        Mode(ratio: 9.80, amp: 0.05, t60: 0.12),
    ]
    strike(track, at: 0.01, fundamental: 293.66, modes: bar, velocity: 0.85, pan: 0.15, attack: 0.0015)
    strike(track, at: 0.31, fundamental: 196.0, modes: bar, velocity: 1.0, pan: -0.1, attack: 0.0015)
    reverb(track, room: 0.55, damping: 0.5, wet: 0.22)
    finish(track, fade: 0.7)
    return track
}

/// Water dripping into a still pool in a cave. A drop's "plip" is the bubble it
/// traps ringing as it shrinks, so the pitch rises; the cave does the rest.
func droplet() -> Track {
    let track = Track(seconds: 4)
    for drop in [(0.02, 520.0, 1.0, -0.2), (0.62, 440.0, 0.55, 0.3)] {
        var phase = 0.0
        track.add(at: drop.0, pan: drop.3, length: 0.5) { t in
            let f = drop.1 * (1 + 0.75 * (1 - exp(-t / 0.022)))
            phase += twoPi * f / rate
            return drop.2 * ramp(t, over: 0.001) * exp(-t / 0.07) * sin(phase)
        }
    }
    reverb(track, room: 0.9, damping: 0.6, wet: 0.4, predelay: 0.03)
    finish(track, fade: 1.0)
    return track
}

/// Aluminium wind chimes in a light breeze: a pentatonic set, so whatever order
/// the tubes are struck in, nothing clashes. A tube rings free at both ends,
/// which puts its overtones at 2.76×, 5.40× and 8.93×.
func chimes() -> Track {
    let track = Track(seconds: 6)
    let tube = [
        Mode(ratio: 1.00, amp: 1.00, t60: 4.0, beat: 0.4, spread: 0.1),
        Mode(ratio: 2.76, amp: 0.35, t60: 2.0),
        Mode(ratio: 5.40, amp: 0.12, t60: 0.8),
        Mode(ratio: 8.93, amp: 0.05, t60: 0.4),
    ]
    let strikes: [(time: Double, freq: Double, velocity: Double, pan: Double)] = [
        (0.00, 659.26, 1.00, -0.4),
        (0.38, 880.00, 0.65, 0.35),
        (0.71, 523.25, 0.80, -0.1),
        (1.24, 783.99, 0.50, 0.5),
        (1.88, 587.33, 0.55, -0.5),
        (2.62, 440.00, 0.45, 0.2),
    ]
    for s in strikes {
        strike(track, at: 0.01 + s.time, fundamental: s.freq, modes: tube,
               velocity: s.velocity, pan: s.pan, attack: 0.0006)
    }
    reverb(track, room: 0.7, damping: 0.45, wet: 0.3)
    finish(track, fade: 1.0)
    return track
}

/// A rolled Fmaj9 on an electric piano — the warm, blurred chord of a late
/// night lo-fi track. Each note is two-operator FM, its brightness fading as
/// the modulation index decays, with the short metallic "tine" on top and a
/// slow tremolo that sways the chord across the stereo field.
func velvet() -> Track {
    let track = Track(seconds: 5)
    let chord = [174.61, 220.0, 329.63, 392.0, 523.25]
    for (i, f) in chord.enumerated() {
        let velocity = 0.75 + 0.05 * Double(i % 3)
        let t60 = 4.2 * pow(220 / f, 0.3)
        track.add(at: 0.01 + Double(i) * 0.03, pan: -0.3 + 0.15 * Double(i)) { t in
            let index = velocity * (1.6 * exp(-t / 0.25) + 0.3)
            let body = sin(twoPi * f * t + index * sin(twoPi * f * t))
            let tine = 0.04 * velocity * exp(-t / 0.015) * sin(twoPi * f * 13.9 * t)
            return 0.35 * velocity * ramp(t, over: 0.003) * exp(-ln1000 / t60 * t) * (body + tine)
        }
    }
    for i in 0..<track.count {
        let sway = 0.25 * sin(twoPi * 3.2 * Double(i) / rate)
        track.left[i] *= 1 + sway
        track.right[i] *= 1 - sway
    }
    reverb(track, room: 0.7, damping: 0.5, wet: 0.25)
    finish(track, fade: 0.9)
    return track
}

/// A harp glissando up a pentatonic scale to the octave. A plucked string is
/// harmonic, its overtone mix set by where it was plucked, and the higher ones
/// fade first, so each note mellows as it rings.
func harp() -> Track {
    let track = Track(seconds: 4.5)
    let notes = [261.63, 293.66, 329.63, 392.0, 440.0, 523.25]
    for (i, f) in notes.enumerated() {
        let t60 = 3.6 * pow(262 / f, 0.4)
        let velocity = i == notes.count - 1 ? 1.0 : 0.6 + 0.05 * Double(i)
        let modes = (1...12).map { k -> Mode in
            let k = Double(k)
            return Mode(ratio: k, amp: abs(sin(k * .pi * 0.27)) / pow(k, 1.4),
                        t60: t60 / (1 + 0.3 * (k - 1)))
        }
        strike(track, at: 0.01 + Double(i) * 0.09, fundamental: f, modes: modes,
               velocity: velocity, pan: -0.4 + 0.16 * Double(i), attack: 0.001)
    }
    reverb(track, room: 0.7, damping: 0.4, wet: 0.3)
    finish(track, fade: 0.9)
    return track
}

// MARK: - Main

// Names avoid the fourteen in /System/Library/Sounds: the app bundle is
// searched first, so a clash would hide a system sound behind ours.
let sounds: [(String, () -> Track)] = [
    ("Bowl", bowl), ("Chimes", chimes), ("Crystal", crystal), ("Droplet", droplet),
    ("Harp", harp), ("Kalimba", kalimba), ("Marimba", marimba), ("Temple", temple),
    ("Velvet", velvet),
]

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: make-sounds <output-directory>\n".data(using: .utf8)!)
    exit(1)
}
let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

for (name, make) in sounds {
    let pcm = out.appendingPathComponent("\(name).wav")
    let m4a = out.appendingPathComponent("\(name).m4a")
    try wav(make()).write(to: pcm)
    // AAC in an M4A: a tenth the size of the PCM, and the container records the
    // encoder's priming frames, so a looping alarm has no gap at the seam. Not
    // CAF: `NSSound(named:)` skips .caf files in a bundle, so the app would
    // never find them.
    let convert = Process()
    convert.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
    convert.arguments = ["-f", "m4af", "-d", "aac", "-b", "160000", pcm.path, m4a.path]
    try convert.run()
    convert.waitUntilExit()
    guard convert.terminationStatus == 0 else {
        FileHandle.standardError.write("afconvert failed for \(name)\n".data(using: .utf8)!)
        exit(1)
    }
    try FileManager.default.removeItem(at: pcm)
    print(name)
}
