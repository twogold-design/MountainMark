extends SceneTree

const RATE: int = 22050
const ROOT: String = "M:/NewGames/MountainMark/assets/audio/"
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _initialize() -> void:
	rng.seed = 64721
	DirAccess.make_dir_recursive_absolute(ROOT)
	make_noise("wind", 12.0, 0)
	make_noise("grip", 0.33, 1)
	make_noise("chalk", 0.85, 2)
	make_noise("fall", 1.25, 3)
	make_noise("breath", 2.9, 4)
	make_music("air", 16.0, 0)
	make_music("checkpoint", 3.4, 1)
	make_music("summit", 20.0, 2)
	print("Audio synthesis complete: 8 original PCM WAV files.")
	quit()

func save_samples(name_: String, samples: PackedFloat32Array, looping: bool = false) -> void:
	if looping:
		var overlap: int = mini(RATE, int(samples.size() / 8))
		for n: int in range(overlap):
			var a: float = float(n) / float(overlap)
			var mixed: float = lerpf(samples[samples.size() - overlap + n], samples[n], a)
			samples[n] = mixed
		samples.resize(samples.size() - overlap)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(samples.size() * 2)
	for n: int in range(samples.size()):
		bytes.encode_s16(n * 2, int(clampf(samples[n], -0.94, 0.94) * 32767.0))
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = bytes
	var error: Error = stream.save_to_wav(ROOT + name_ + ".wav")
	if error != OK:
		push_error("Could not save " + name_)
	print(name_, ": ", samples.size(), " samples")

func make_noise(name_: String, duration: float, kind: int) -> void:
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(int(duration * RATE))
	var low: float = 0.0
	var slow: float = 0.0
	for n: int in range(samples.size()):
		var t: float = float(n) / RATE
		var white: float = rng.randf_range(-1.0, 1.0)
		low = lerpf(low, white, 0.07 if kind == 0 else 0.26)
		slow = lerpf(slow, white, 0.012)
		var value: float = 0.0
		match kind:
			0:
				var gust: float = 0.55 + 0.23 * sin(t * 0.72) + 0.12 * sin(t * 1.81)
				value = (low * 0.95 + slow * 1.4) * gust
			1:
				var brush: float = sin(PI * minf(t / duration, 1.0)) * exp(-t * 11.0)
				var tap: float = exp(-t * 48.0) * sin(TAU * 126.0 * t)
				value = (white - low) * brush * 0.32 + tap * 0.21
			2:
				var puff: float = pow(sin(PI * t / duration), 2.0) * (0.65 + 0.35 * sin(t * 36.0))
				value = (low * 0.9 + white * 0.15) * puff * 0.8
			3:
				var rush: float = sin(PI * t / duration)
				var rope: float = exp(-maxf(0.0, t - 0.82) * 15.0) if t > 0.82 else 0.0
				value = low * rush * 0.55 + sin(TAU * (65.0 * t - 12.0 * t * t)) * rope * 0.16
			4:
				var inhale: float = pow(maxf(0.0, sin(TAU * t / duration)), 1.8)
				var exhale: float = pow(maxf(0.0, -sin(TAU * t / duration)), 1.4)
				value = (low - slow) * (inhale * 0.24 + exhale * 0.4)
		var edge: float = minf(1.0, minf(t * 160.0, (duration - t) * 50.0)) if kind != 0 else 1.0
		samples[n] = value * edge
	save_samples(name_, samples, kind == 0)

func add_note(samples: PackedFloat32Array, start: float, duration: float, pitch: float, gain: float, soft: bool) -> void:
	var begin: int = int(start * RATE)
	var count: int = mini(int(duration * RATE), samples.size() - begin)
	var frequency: float = 440.0 * pow(2.0, (pitch - 69.0) / 12.0)
	var phase: float = rng.randf() * TAU
	for n: int in range(maxi(count, 0)):
		var t: float = float(n) / RATE
		var envelope: float = minf(1.0, t / (0.8 if soft else 0.015)) * pow(maxf(0.0, 1.0 - t / duration), 1.7)
		var vibrato: float = 0.007 * sin(t * TAU * 4.7)
		var fundamental: float = sin(TAU * frequency * t + vibrato + phase)
		var overtone: float = sin(TAU * frequency * 2.002 * t + phase) * 0.22 + sin(TAU * frequency * 3.001 * t) * 0.07
		samples[begin + n] += (fundamental + overtone) * envelope * gain

func make_music(name_: String, duration: float, kind: int) -> void:
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(int(duration * RATE))
	if kind == 0:
		for idx: int in range(8):
			var pitch: float = [50.0, 57.0, 62.0, 64.0, 57.0, 69.0, 62.0, 66.0][idx]
			add_note(samples, float(idx) * 1.8, 6.0, pitch, 0.042, true)
	elif kind == 1:
		add_note(samples, 0.0, 3.3, 74.0, 0.1, false)
		add_note(samples, 0.18, 3.0, 81.0, 0.07, false)
		add_note(samples, 0.4, 2.8, 86.0, 0.045, false)
	else:
		var chords: Array = [[50, 57, 62, 66], [47, 54, 62, 66], [43, 55, 62, 67], [50, 57, 66, 69]]
		for chord: int in range(4):
			for note: int in range(4):
				add_note(samples, float(chord) * 4.0 + float(note) * 0.17, 7.0, float(chords[chord][note]), 0.065, true)
		for idx: int in range(8):
			var pitch: float = [74.0, 78.0, 81.0, 78.0, 79.0, 78.0, 76.0, 74.0][idx]
			add_note(samples, 2.0 + float(idx) * 1.75, 4.0, pitch, 0.05, false)
	save_samples(name_, samples, kind == 0)
