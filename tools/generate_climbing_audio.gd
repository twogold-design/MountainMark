extends SceneTree
## Deterministic, original climbing foley. Run with Godot --headless --script.
## No recordings, speech, or third-party audio are used.

const RATE: int = 22050
const ROOT: String = "res://assets/audio/"
var rng: RandomNumberGenerator = RandomNumberGenerator.new()


class BandPass:
	extends RefCounted
	var b0: float
	var b2: float
	var a1: float
	var a2: float
	var x1: float = 0.0
	var x2: float = 0.0
	var y1: float = 0.0
	var y2: float = 0.0

	func _init(hz: float, q: float) -> void:
		var w: float = TAU * hz / RATE
		var alpha: float = sin(w) / (2.0 * q)
		var a0: float = 1.0 + alpha
		b0 = alpha / a0
		b2 = -alpha / a0
		a1 = -2.0 * cos(w) / a0
		a2 = (1.0 - alpha) / a0

	func sample(input: float) -> float:
		var result: float = b0 * input + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = input
		y2 = y1
		y1 = result
		return result


func _initialize() -> void:
	rng.seed = 648209
	DirAccess.make_dir_recursive_absolute(ROOT)
	make_effort("effort_1", 0.44, 112.0, 520.0)
	make_effort("effort_2", 0.51, 103.0, 460.0)
	make_pant()
	make_recovery()
	print("Climbing audio: four original mono 16-bit WAV files generated.")
	quit()


func edge_fade(t: float, duration: float) -> float:
	return smoothstep(0.0, 0.012, t) * (1.0 - smoothstep(duration - 0.055, duration, t))


func make_effort(name_: String, duration: float, base_pitch: float, vowel_hz: float) -> void:
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(int(duration * RATE))
	var throat: BandPass = BandPass.new(vowel_hz, 2.7)
	var mouth: BandPass = BandPass.new(1030.0, 3.8)
	var air: BandPass = BandPass.new(1650.0, 0.65)
	var low: float = 0.0
	var voice_low: float = 0.0
	var phase: float = 0.0
	var jitter: float = 0.0
	for n: int in range(samples.size()):
		var t: float = float(n) / RATE
		var u: float = t / duration
		var white: float = rng.randf_range(-1.0, 1.0)
		low = lerpf(low, white, 0.038)
		jitter = lerpf(jitter, rng.randf_range(-1.0, 1.0), 0.0017)
		var pitch: float = base_pitch * (1.055 - 0.22 * u + jitter * 0.7)
		phase += TAU * pitch / RATE
		var glottis: float = 0.0
		for harmonic: int in range(1, 15):
			glottis += sin(phase * harmonic + harmonic * 0.13) / pow(float(harmonic), 1.45)
		voice_low = lerpf(voice_low, glottis, 0.22)
		var vowel: float = voice_low * 0.13 + throat.sample(glottis) * 1.6 + mouth.sample(glottis) * 0.85
		var airflow: float = air.sample(white) * 0.73 + low * 0.16
		var puff: float = pow(sin(PI * u), 0.86) * exp(-u * 0.9)
		var voice_envelope: float = smoothstep(0.045, 0.15, u) * (1.0 - smoothstep(0.46, 0.87, u))
		var pressure: float = 0.9 + 0.10 * sin(TAU * (8.0 * t + 1.8 * t * t))
		samples[n] = (vowel * voice_envelope * 0.47 + airflow * 0.78) * puff * pressure * edge_fade(t, duration)
	save_samples(name_, samples, 0.61)


func make_pant() -> void:
	const DURATION: float = 1.48
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(int(DURATION * RATE))
	var inhale_filter: BandPass = BandPass.new(1750.0, 0.75)
	var exhale_filter: BandPass = BandPass.new(1050.0, 0.62)
	var low: float = 0.0
	var breath_waver: float = 0.0
	for n: int in range(samples.size()):
		var t: float = float(n) / RATE
		var white: float = rng.randf_range(-1.0, 1.0)
		low = lerpf(low, white, 0.04)
		breath_waver = lerpf(breath_waver, rng.randf_range(-1.0, 1.0), 0.001)
		var inhale_phase: float = clampf((t - 0.025) / 0.50, 0.0, 1.0)
		var exhale_phase: float = clampf((t - 0.66) / 0.76, 0.0, 1.0)
		var inhale: float = pow(maxf(0.0, sin(inhale_phase * PI)), 1.25) * 0.68
		var exhale: float = pow(maxf(0.0, sin(exhale_phase * PI)), 0.95)
		var in_air: float = inhale_filter.sample(white) * 0.73 + low * 0.2
		var out_air: float = exhale_filter.sample(white) * 0.80 + low * 0.40
		var fluctuation: float = 0.94 + 0.06 * sin(t * TAU * 6.7) + breath_waver * 0.25
		samples[n] = (in_air * inhale + out_air * exhale) * fluctuation * edge_fade(t, DURATION)
	save_samples("pant", samples, 0.46)


func add_soft_note(samples: PackedFloat32Array, at: float, hz: float, gain: float) -> void:
	var begin: int = int(at * RATE)
	for n: int in range(begin, samples.size()):
		var t: float = float(n - begin) / RATE
		var end: float = float(samples.size() - begin) / RATE
		var attack: float = smoothstep(0.0, 0.038, t)
		var tail: float = 1.0 - smoothstep(end - 0.25, end, t)
		var envelope: float = attack * exp(-t * 3.2) * tail
		var fundamental: float = sin(TAU * hz * t)
		var overtones: float = sin(TAU * hz * 2.002 * t) * exp(-t * 2.3) * 0.17
		overtones += sin(TAU * hz * 3.011 * t) * exp(-t * 4.2) * 0.035
		samples[n] += (fundamental + overtones) * envelope * gain


func make_recovery() -> void:
	const DURATION: float = 1.65
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(int(DURATION * RATE))
	add_soft_note(samples, 0.0, 293.665, 0.20)
	add_soft_note(samples, 0.20, 369.994, 0.16)
	add_soft_note(samples, 0.43, 440.0, 0.13)
	# Quiet short reflections give a little space without a bright notification sound.
	var dry: PackedFloat32Array = samples.duplicate()
	var delay: int = int(RATE * 0.087)
	for n: int in range(delay, samples.size()):
		samples[n] += dry[n - delay] * 0.09
	for n: int in range(samples.size()):
		samples[n] *= edge_fade(float(n) / RATE, DURATION)
	save_samples("recovery", samples, 0.43)


func save_samples(name_: String, samples: PackedFloat32Array, peak: float) -> void:
	var highest: float = 0.0
	for sample: float in samples:
		highest = maxf(highest, absf(sample))
	var gain: float = peak / maxf(highest, 0.001)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(samples.size() * 2)
	var squared_sum: float = 0.0
	for n: int in range(samples.size()):
		var value: float = samples[n] * gain
		squared_sum += value * value
		bytes.encode_s16(n * 2, int(round(value * 32767.0)))
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = bytes
	var error: Error = stream.save_to_wav(ROOT + name_ + ".wav")
	if error != OK:
		push_error("Could not save " + name_ + ": " + error_string(error))
		quit(1)
	print("%s: %.2fs, peak %.3f, RMS %.3f, mono PCM16 %dHz" % [name_, float(samples.size()) / RATE, peak, sqrt(squared_sum / samples.size()), RATE])
