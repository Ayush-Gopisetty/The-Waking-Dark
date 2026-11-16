class_name AudioGen
extends RefCounted
## Placeholder audio, synthesised at startup so the prototype ships no sound
## files. Replace each function's caller with a real AudioStream when final
## audio exists.

const RATE := 22050


static func _wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


static func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## White noise through a one-pole low-pass filter.
static func _noise(count: int, cutoff_hz: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(count)
	var alpha := 1.0 - exp(-TAU * cutoff_hz / RATE)
	var y := 0.0
	for i in count:
		y += alpha * (rng.randf_range(-1.0, 1.0) - y)
		out[i] = y
	return out


static func _normalize(samples: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var top := 0.0001
	for s in samples:
		top = maxf(top, absf(s))
	var gain := peak / top
	for i in samples.size():
		samples[i] *= gain
	return samples


## Crossfades the tail of `x` (length n + fade) into its head for a seamless loop.
static func _seamless(x: PackedFloat32Array, n: int, fade: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		if i < fade:
			var t := float(i) / fade
			out[i] = x[i] * t + x[n + i] * (1.0 - t)
		else:
			out[i] = x[i]
	return out


## Low wind / room tone loop.
static func ambience() -> AudioStreamWAV:
	var n := RATE * 6
	var fade := RATE / 2
	var raw := _noise(n + fade, 180.0, _rng(11))
	var out := _seamless(raw, n, fade)
	for i in n:
		var t := float(i) / RATE
		var swell := 0.65 + 0.35 * sin(TAU * t / 6.0)
		out[i] = out[i] * swell
	out = _normalize(out, 0.5)
	for i in n:
		var t := float(i) / RATE
		out[i] += 0.05 * sin(TAU * 40.0 * t)
	return _wav(out, true)


## Spirit proximity drone: two detuned low sines that beat against each other.
static func drone() -> AudioStreamWAV:
	var n := RATE * 4
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var beat := 0.75 + 0.25 * sin(TAU * 0.5 * t)
		out[i] = beat * (0.45 * sin(TAU * 55.0 * t) + 0.35 * sin(TAU * 58.25 * t) + 0.12 * sin(TAU * 110.5 * t))
	return _wav(out, true)


static func footstep() -> AudioStreamWAV:
	var n := int(RATE * 0.13)
	var out := _noise(n, 500.0, _rng(23))
	for i in n:
		var t := float(i) / n
		out[i] *= exp(-7.0 * t)
	return _wav(_normalize(out, 0.8))


static func click() -> AudioStreamWAV:
	var n := int(RATE * 0.04)
	var out := _noise(n, 4000.0, _rng(31))
	for i in n:
		out[i] *= exp(-12.0 * float(i) / n)
	return _wav(_normalize(out, 0.6))


static func pickup() -> AudioStreamWAV:
	var n := int(RATE * 0.22)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var freq := 520.0 if t < 0.09 else 780.0
		var local := t if t < 0.09 else t - 0.09
		out[i] = 0.4 * sin(TAU * freq * t) * exp(-18.0 * local)
	return _wav(out)


## Door creak: a falling, wobbling buzz.
static func creak() -> AudioStreamWAV:
	var n := int(RATE * 0.7)
	var rng := _rng(41)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var wobble := 0.0
	for i in n:
		var t := float(i) / n
		wobble = lerpf(wobble, rng.randf_range(-1.0, 1.0), 0.01)
		var freq := lerpf(210.0, 95.0, t) * (1.0 + 0.25 * wobble)
		phase += freq / RATE
		var saw := 2.0 * fposmod(phase, 1.0) - 1.0
		out[i] = saw * sin(PI * t) * 0.35
	return _wav(out)


## Locked handle: three quick thumps.
static func rattle() -> AudioStreamWAV:
	var n := int(RATE * 0.45)
	var noise := _noise(n, 900.0, _rng(53))
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var local := fposmod(t, 0.15)
		out[i] = noise[i] * exp(-30.0 * local)
	return _wav(_normalize(out, 0.7))


## Spirit noticing the player: falling dissonant shriek.
static func screech() -> AudioStreamWAV:
	var n := int(RATE * 1.1)
	var noise := _noise(n, 3000.0, _rng(67))
	var out := PackedFloat32Array()
	out.resize(n)
	var p1 := 0.0
	var p2 := 0.0
	for i in n:
		var t := float(i) / n
		var f := lerpf(930.0, 410.0, t)
		p1 += f / RATE
		p2 += f * 1.06 / RATE
		var env := minf(1.0, t * 25.0) * exp(-3.0 * t)
		out[i] = env * (0.35 * sin(TAU * p1) + 0.3 * sin(TAU * p2) + 0.5 * noise[i])
	return _wav(_normalize(out, 0.85))


## Memory flashback: rising swell.
static func flashback() -> AudioStreamWAV:
	var n := int(RATE * 1.6)
	var noise := _noise(n, 1200.0, _rng(79))
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / n
		var env := sin(PI * t)
		var secs := float(i) / RATE
		out[i] = env * (0.3 * sin(TAU * 220.0 * secs) + 0.2 * sin(TAU * 331.0 * secs) + 0.6 * noise[i])
	return _wav(_normalize(out, 0.7))


## Father Crane's chanting through the walls: low male voices on a slow,
## repeating three-note figure, muffled as if heard through stone.
static func chanting() -> AudioStreamWAV:
	var n := RATE * 8
	var notes := [98.0, 98.0, 110.0, 92.5]  # G2 G2 A2 F#2, two seconds each
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := _rng(91)
	var phases := [0.0, 0.0, 0.0]
	var detune := [1.0, 1.005, 0.497]
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var idx := int(t / 2.0) % notes.size()
		var local := fmod(t, 2.0)
		var env := sin(PI * clampf(local / 2.0, 0.0, 1.0)) * (0.75 + 0.25 * sin(TAU * 4.5 * t))
		var s := 0.0
		for v in 3:
			phases[v] += notes[idx] * detune[v] / RATE
			var saw: float = 2.0 * fposmod(phases[v], 1.0) - 1.0
			s += saw * (0.5 if v < 2 else 0.35)
		s += rng.randf_range(-0.05, 0.05)
		lp += 0.06 * (s * env - lp)  # through the walls: heavily low-passed
		out[i] = lp
	return _wav(_normalize(out, 0.6), true)


## Lily's faint humming behind a wall: a simple, slightly sad lullaby.
static func humming() -> AudioStreamWAV:
	var melody := [523.25, 587.33, 659.25, 587.33, 523.25, 440.0, 493.88, 523.25, 0.0, 0.0]
	var note_len := 0.55
	var n := int(RATE * note_len * melody.size())
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var idx := int(t / note_len)
		var f: float = melody[idx]
		if f <= 0.0:
			continue
		var local := fmod(t, note_len) / note_len
		var vib := 1.0 + 0.008 * sin(TAU * 5.5 * t)
		phase += f * vib / RATE
		var env := sin(PI * local) * 0.9
		out[i] = env * (0.6 * sin(TAU * phase) + 0.15 * sin(TAU * phase * 2.0))
	return _wav(_normalize(out, 0.5), true)


## Tension bed: a dark, slowly pulsing pad.
static func tension() -> AudioStreamWAV:
	var n := RATE * 8
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var pulse := 0.6 + 0.4 * sin(TAU * t / 8.0 * 2.0)
		out[i] = pulse * (0.4 * sin(TAU * 65.41 * t) + 0.3 * sin(TAU * 77.78 * t) + 0.15 * sin(TAU * 98.0 * t + sin(TAU * 0.25 * t)))
	return _wav(_normalize(out, 0.5), true)


## Chase layer: a fast, heavy heartbeat with a dissonant drone.
static func chase() -> AudioStreamWAV:
	var n := RATE * 2
	var noise := _noise(n, 200.0, _rng(97))
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var beat := fmod(t, 0.5)
		var thump := exp(-beat * 22.0) + 0.6 * exp(-maxf(0.0, beat - 0.16) * 26.0) * float(beat > 0.16)
		out[i] = thump * (sin(TAU * 52.0 * t) + noise[i] * 0.8) + 0.18 * sin(TAU * 110.0 * t) * sin(TAU * 116.5 * t)
	return _wav(_normalize(out, 0.75), true)
