class_name SoundBank
extends RefCounted
## Recorded sound sets in assets/audio (CC0, see assets/CREDITS.md). Each set is a
## folder of numbered clips: assets/audio/<folder>/<prefix>_01.wav, _02.wav, ...
## `pick` returns a random clip, never the same one twice in a row.

const DIR := "res://assets/audio/"

static var _sets: Dictionary = {}
static var _last: Dictionary = {}


static func clips(folder: String, prefix: String) -> Array[AudioStream]:
	var key := folder + "/" + prefix
	if not _sets.has(key):
		var found: Array[AudioStream] = []
		for i in range(1, 40):
			var path := "%s%s/%s_%02d.wav" % [DIR, folder, prefix, i]
			if not ResourceLoader.exists(path):
				break
			found.append(load(path))
		_sets[key] = found
	return _sets[key]


static func pick(folder: String, prefix: String) -> AudioStream:
	var set := clips(folder, prefix)
	if set.is_empty():
		return null
	var key := folder + "/" + prefix
	var index := randi() % set.size()
	if set.size() > 1 and index == _last.get(key, -1):
		index = (index + 1) % set.size()
	_last[key] = index
	return set[index]


## A long recording as a seamless loop.
static func loop(path: String) -> AudioStream:
	var wav := load(DIR + path) as AudioStreamWAV
	if wav == null:
		return null
	wav = wav.duplicate() as AudioStreamWAV
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	# (imported sounds are compressed, so count samples from the length, not the bytes)
	wav.loop_end = int(wav.get_length() * wav.mix_rate)
	return wav
