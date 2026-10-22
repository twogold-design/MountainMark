extends SceneTree
## Original dry climbing contact foley, generated without recordings or speech.
## Six material / contact gestures, with deliberately different spectral and
## temporal profiles. No tonal resonators: the rock stays soft, dry and close.

const RATE: int = 22050
const ROOT: String = "res://assets/audio/"
const PREVIEW_PATH: String = "res://.runtime/grip-audio-preview.wav"
var rng: RandomNumberGenerator = RandomNumberGenerator.new()


class LowPass:
	extends RefCounted
	var coefficient: float
	var value: float = 0.0

	func _init(hz: float) -> void:
		coefficient = 1.0 - exp(-TAU * hz / RATE)

	func sample(input: float) -> float:
		value += coefficient * (input - value)
		return value


func _initialize() -> void:
	rng.seed = 9864122
	DirAccess.make_dir_recursive_absolute(ROOT)
	DirAccess.make_dir_recursive_absolute("res://.runtime")
	var variants: Array[Dictionary] = [
		{"duration": 0.29, "peak": 0.41, "gesture": "soft_palm", "description": "Soft low palm, brief squeeze, sparse rounded grit"},
		{"duration": 0.37, "peak": 0.48, "gesture": "firm_squeeze", "description": "Heel then fingers, coarse low-mid pressure, five gravel grains"},
		{"duration": 0.44, "peak": 0.44, "gesture": "rounded_roll", "description": "Broad dull touch, rolling three-finger pressure, slow loose grains"},
		{"duration": 0.48, "peak": 0.36, "gesture": "chalk_brush", "description": "Muted touch, fine chalk brush, diffuse fading dust"},
		{"duration": 0.52, "peak": 0.39, "gesture": "fine_fingertips", "description": "Light fingertips, two unequal friction strokes, cascading sand"},
		{"duration": 0.33, "peak": 0.46, "gesture": "dry_crag", "description": "Short dry crag catch, compact crunch, irregular chips"},
	]
	var preview: PackedFloat32Array = PackedFloat32Array()
	var reports: Array[Dictionary] = []
	for idx: int in range(variants.size()):
		var samples: PackedFloat32Array = make_grip(variants[idx], idx)
		var name_: String = "grip_%d" % (idx + 1)
		normalize(samples, float(variants[idx]["peak"]))
		save_samples(ROOT + name_ + ".wav", samples)
		var report: Dictionary = analyze(samples)
		report["name"] = name_
		report["gesture"] = variants[idx]["gesture"]
		report["description"] = variants[idx]["description"]
		reports.append(report)
		print("%s: %s" % [name_, JSON.stringify(report)])
		preview.append_array(samples)
		var silence: PackedFloat32Array = PackedFloat32Array()
		silence.resize(int(RATE * 0.35))
		preview.append_array(silence)
	save_samples(PREVIEW_PATH, preview)
	var file: FileAccess = FileAccess.open("res://.runtime/grip-audio-analysis.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(reports, "\t"))
	print("Generated six quieter original palm / chalk / dry-rock gestures and preview.")
	quit()


func make_grip(settings: Dictionary, index: int) -> PackedFloat32Array:
	var duration: float = float(settings["duration"])
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(int(duration * RATE))
	# The gestures use different sources, contact ordering, pressure envelopes and
	# grain placement, rather than six transpositions of a common noise envelope.
	match index:
		0:
			add_contact(samples, 0.0, 0.085, 370.0, 45.0, 0.023, 1.8)
			add_contact(samples, 0.017, 0.045, 680.0, 130.0, 0.010, 0.32)
			add_rub(samples, 0.012, 0.070, 760.0, 120.0, 0.25, 38.0, 1.35)
			add_grains(samples, 3, 0.105, 0.235, 1200.0, 0.010, 0.023, 0.16, 0.30)
		1:
			add_contact(samples, 0.0, 0.065, 510.0, 65.0, 0.015, 1.15)
			add_contact(samples, 0.027, 0.078, 930.0, 140.0, 0.021, 0.60)
			add_rub(samples, 0.020, 0.132, 1100.0, 160.0, 0.29, 24.0, 0.78)
			add_grains(samples, 5, 0.126, 0.303, 1550.0, 0.009, 0.021, 0.14, 0.30)
		2:
			add_contact(samples, 0.0, 0.135, 260.0, 42.0, 0.038, 1.7)
			for finger: int in range(3):
				add_contact(samples, [0.019, 0.047, 0.081][finger], 0.044, 420.0 + finger * 130.0, 80.0, 0.012, 0.35 - finger * 0.055)
			add_rub(samples, 0.028, 0.184, 640.0, 90.0, 0.33, 15.0, 0.68)
			add_grains(samples, 4, 0.176, 0.382, 980.0, 0.014, 0.030, 0.18, 0.34)
		3:
			add_contact(samples, 0.0, 0.054, 720.0, 125.0, 0.012, 0.78)
			add_rub(samples, 0.008, 0.190, 2600.0, 610.0, 0.30, 75.0, 0.72)
			add_rub(samples, 0.092, 0.272, 3500.0, 1100.0, 0.075, 105.0, 1.12)
			add_grains(samples, 21, 0.082, 0.422, 2800.0, 0.0025, 0.008, 0.033, 0.075)
		4:
			add_contact(samples, 0.0, 0.039, 1320.0, 320.0, 0.008, 0.65)
			add_contact(samples, 0.033, 0.048, 1720.0, 440.0, 0.011, 0.23)
			add_rub(samples, 0.015, 0.082, 3100.0, 800.0, 0.19, 110.0, 1.5)
			add_rub(samples, 0.107, 0.221, 2200.0, 650.0, 0.13, 52.0, 0.75)
			add_grains(samples, 28, 0.171, 0.466, 3600.0, 0.002, 0.006, 0.025, 0.070)
		5:
			add_contact(samples, 0.0, 0.032, 2400.0, 350.0, 0.006, 0.86)
			add_contact(samples, 0.024, 0.041, 3800.0, 720.0, 0.008, 0.31)
			add_contact(samples, 0.004, 0.071, 480.0, 75.0, 0.020, 0.72)
			add_rub(samples, 0.019, 0.089, 1800.0, 370.0, 0.18, 160.0, 1.1)
			add_grains(samples, 8, 0.087, 0.277, 2350.0, 0.004, 0.013, 0.09, 0.24)
	# Remove DC and soften the extreme top end without introducing ringing.
	var finish_softener: LowPass = LowPass.new(5200.0 if index >= 3 else 2300.0)
	var dc_reject: LowPass = LowPass.new(34.0)
	for n: int in range(samples.size()):
		var t: float = float(n) / RATE
		var value: float = finish_softener.sample(samples[n])
		samples[n] = (value - dc_reject.sample(value)) * smoothstep(0.0, 0.0007, t) * (1.0 - smoothstep(duration - 0.024, duration - 1.0 / RATE, t))
	samples[0] = 0.0
	samples[samples.size() - 1] = 0.0
	return samples


func add_contact(samples: PackedFloat32Array, at: float, length_: float, high_hz: float, low_hz: float, decay: float, gain: float) -> void:
	var start: int = int(at * RATE)
	var count: int = int(length_ * RATE)
	var upper: LowPass = LowPass.new(high_hz)
	var lower: LowPass = LowPass.new(low_hz)
	for n: int in range(count):
		if start + n >= samples.size():
			break
		var t: float = float(n) / RATE
		var noise: float = upper.sample(rng.randf_range(-1.0, 1.0))
		var envelope: float = smoothstep(0.0, 0.0011, t) * exp(-t / decay) * (1.0 - smoothstep(length_ * 0.65, length_, t))
		samples[start + n] += (noise - lower.sample(noise)) * envelope * gain


func add_rub(samples: PackedFloat32Array, at: float, finish: float, high_hz: float, low_hz: float, gain: float, modulation_hz: float, shape: float) -> void:
	var start: int = int(at * RATE)
	var count: int = int((finish - at) * RATE)
	var upper: LowPass = LowPass.new(high_hz)
	var lower: LowPass = LowPass.new(low_hz)
	var modulator: LowPass = LowPass.new(modulation_hz)
	for n: int in range(count):
		if start + n >= samples.size():
			break
		var u: float = float(n) / maxi(count - 1, 1)
		var noise: float = upper.sample(rng.randf_range(-1.0, 1.0))
		var roughness: float = clampf(0.68 + modulator.sample(rng.randf_range(-1.0, 1.0)) * 3.0, 0.10, 1.35)
		var envelope: float = pow(maxf(0.0, sin(u * PI)), shape) * (1.15 - u * 0.60)
		samples[start + n] += (noise - lower.sample(noise)) * envelope * roughness * gain


func add_grains(samples: PackedFloat32Array, count: int, from: float, to: float, hz: float, min_length: float, max_length: float, min_gain: float, max_gain: float) -> void:
	# Uniformly spaced grains sound like a rattle. Random times, varying grain
	# sizes and a dying density keep this closer to sand settling under a hand.
	for grain: int in range(count):
		var u: float = rng.randf()
		var at: float = lerpf(from, to, pow(u, 1.22))
		add_grain(samples, at, rng.randf_range(min_length, max_length), hz * rng.randf_range(0.65, 1.25), rng.randf_range(min_gain, max_gain) * (1.0 - u * 0.45))


func add_grain(samples: PackedFloat32Array, at: float, length_: float, hz: float, gain: float) -> void:
	var start: int = int(at * RATE)
	var count: int = int(length_ * RATE)
	var softener: LowPass = LowPass.new(hz)
	var bass_reject: LowPass = LowPass.new(maxf(95.0, hz * 0.23))
	for n: int in range(count):
		if start + n >= samples.size():
			break
		var u: float = float(n) / maxi(count - 1, 1)
		var air: float = softener.sample(rng.randf_range(-1.0, 1.0))
		var envelope: float = smoothstep(0.0, 0.07, u) * exp(-u * 3.3) * (1.0 - smoothstep(0.7, 1.0, u))
		samples[start + n] += (air - bass_reject.sample(air)) * envelope * gain


func normalize(samples: PackedFloat32Array, peak: float) -> void:
	var highest: float = 0.0
	for value: float in samples:
		highest = maxf(highest, absf(value))
	var gain: float = peak / maxf(highest, 0.001)
	for n: int in range(samples.size()):
		samples[n] *= gain


func save_samples(path: String, samples: PackedFloat32Array) -> void:
	var data: PackedByteArray = PackedByteArray()
	data.resize(samples.size() * 2)
	for n: int in range(samples.size()):
		data.encode_s16(n * 2, int(round(samples[n] * 32767.0)))
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	var error: Error = wav.save_to_wav(path)
	if error != OK:
		push_error("Could not save %s: %s" % [path, error_string(error)])
		quit(1)


func analyze(samples: PackedFloat32Array) -> Dictionary:
	var peak: float = 0.0
	var peak_sample: int = 0
	var energy: float = 0.0
	var dc: float = 0.0
	var late_energy: float = 0.0
	var time_bands: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	for n: int in range(samples.size()):
		if absf(samples[n]) > peak:
			peak_sample = n
		peak = maxf(peak, absf(samples[n]))
		energy += samples[n] * samples[n]
		dc += samples[n]
		if n >= int(0.15 * RATE):
			late_energy += samples[n] * samples[n]
		var t: float = float(n) / RATE
		var time_band: int = 0 if t < 0.04 else (1 if t < 0.10 else (2 if t < 0.20 else 3))
		time_bands[time_band] += samples[n] * samples[n]
	var bands: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var weighted_hz: float = 0.0
	var spectral_energy: float = 0.0
	const SIZE: int = 512
	for start: int in range(0, samples.size() - SIZE, SIZE / 2):
		var real: PackedFloat64Array = PackedFloat64Array()
		var imaginary: PackedFloat64Array = PackedFloat64Array()
		real.resize(SIZE)
		imaginary.resize(SIZE)
		for n: int in range(SIZE):
			real[n] = samples[start + n] * (0.5 - 0.5 * cos(TAU * n / float(SIZE - 1)))
		fft(real, imaginary)
		for bin_: int in range(1, SIZE / 2 + 1):
			var hz: float = float(bin_) * RATE / SIZE
			var power: float = real[bin_] * real[bin_] + imaginary[bin_] * imaginary[bin_]
			var band: int = 0 if hz < 200.0 else (1 if hz < 1500.0 else (2 if hz < 4000.0 else 3))
			bands[band] += power
			weighted_hz += power * hz
			spectral_energy += power
	var percentages: Array[float] = []
	for band_energy: float in bands:
		percentages.append(snappedf(band_energy / maxf(spectral_energy, 0.00001) * 100.0, 0.1))
	var time_percentages: Array[float] = []
	for band_energy: float in time_bands:
		time_percentages.append(snappedf(band_energy / maxf(energy, 0.00001) * 100.0, 0.1))
	return {
		"duration_s": snappedf(float(samples.size()) / RATE, 0.001),
		"peak": snappedf(peak, 0.001),
		"rms": snappedf(sqrt(energy / samples.size()), 0.0001),
		"dc": snappedf(dc / samples.size(), 0.000001),
		"centroid_hz": round(weighted_hz / maxf(spectral_energy, 0.00001)),
		"peak_at_ms": snappedf(float(peak_sample) / RATE * 1000.0, 0.1),
		"energy_pct_lt200_200to1500_1500to4000_gt4000": percentages,
		"energy_pct_0to40_40to100_100to200_gt200ms": time_percentages,
		"tail_energy_pct_after_150ms": snappedf(late_energy / maxf(energy, 0.00001) * 100.0, 0.01),
		"first": samples[0], "last": samples[samples.size() - 1],
	}


func fft(real: PackedFloat64Array, imaginary: PackedFloat64Array) -> void:
	var size: int = real.size()
	var reverse: int = 0
	for n: int in range(1, size):
		var bit: int = size >> 1
		while reverse & bit:
			reverse ^= bit
			bit >>= 1
		reverse ^= bit
		if n < reverse:
			var swap: float = real[n]
			real[n] = real[reverse]
			real[reverse] = swap
	var length_: int = 2
	while length_ <= size:
		var angle: float = -TAU / length_
		var cosine: float = cos(angle)
		var sine: float = sin(angle)
		for begin: int in range(0, size, length_):
			var twiddle_real: float = 1.0
			var twiddle_imaginary: float = 0.0
			for n: int in range(length_ / 2):
				var even: int = begin + n
				var odd: int = even + length_ / 2
				var odd_real: float = real[odd] * twiddle_real - imaginary[odd] * twiddle_imaginary
				var odd_imaginary: float = real[odd] * twiddle_imaginary + imaginary[odd] * twiddle_real
				real[odd] = real[even] - odd_real
				imaginary[odd] = imaginary[even] - odd_imaginary
				real[even] += odd_real
				imaginary[even] += odd_imaginary
				var next_real: float = twiddle_real * cosine - twiddle_imaginary * sine
				twiddle_imaginary = twiddle_real * sine + twiddle_imaginary * cosine
				twiddle_real = next_real
		length_ <<= 1
