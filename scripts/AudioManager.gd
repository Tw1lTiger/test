extends Node

const MUSIC_DIR := "res://music/"
var music_files: Array[String] = []
var _player: AudioStreamPlayer
var _current_index: int = 0
var _volume_db: float = 0.0

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "MusicPlayer"
	_player.volume_db = _volume_db
	_player.bus = "Master" # Or dedicated "Music" bus
	_player.finished.connect(_on_song_finished)
	add_child(_player)

	_scan_music()
	if not music_files.is_empty():
		music_files.shuffle()
		play_next()

func _scan_music() -> void:
	var dir := DirAccess.open(MUSIC_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and (file_name.ends_with(".mp3") or file_name.ends_with(".ogg")):
				music_files.append(MUSIC_DIR + file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
	print("[AudioManager] Found %d tracks" % music_files.size())

func play_next() -> void:
	if music_files.is_empty():
		return
	
	_current_index = (_current_index + 1) % music_files.size()
	var path := music_files[_current_index]
	var stream = load(path)
	if stream:
		_player.stream = stream
		_player.play()
		print("[AudioManager] Playing: %s" % path)

func _on_song_finished() -> void:
	play_next()

func set_volume(percent: float) -> void:
	# Scale 0-100 to db (-80 to 0)
	var db := linear_to_db(percent / 100.0)
	_volume_db = db # Store for _ready if called early
	
	if _player:
		_player.volume_db = db
	
	AudioServer.set_bus_volume_db(0, db) # Sync with Master bus for now
