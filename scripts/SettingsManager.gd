extends Node

const SETTINGS_FILE := "user://settings.cfg"

var settings := {
	"quality": 0, # Low
	"resolution": 0, # 1280x720
	"fullscreen": false,
	"volume": 80.0
}

func _ready() -> void:
	load_settings()

func load_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load(SETTINGS_FILE)
	if err == OK:
		settings.quality = config.get_value("graphics", "quality", 0)
		settings.resolution = config.get_value("graphics", "resolution", 0)
		settings.fullscreen = config.get_value("graphics", "fullscreen", false)
		settings.volume = config.get_value("audio", "volume", 80.0)
		print("[SettingsManager] Loaded: ", settings)
	else:
		print("[SettingsManager] No settings file found, using defaults.")

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("graphics", "quality", settings.quality)
	config.set_value("graphics", "resolution", settings.resolution)
	config.set_value("graphics", "fullscreen", settings.fullscreen)
	config.set_value("audio", "volume", settings.volume)
	config.save(SETTINGS_FILE)
	print("[SettingsManager] Saved.")
