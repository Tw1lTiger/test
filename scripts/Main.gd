# ==============================================================================
# Main.gd — Главная сцена: окружение, спавн игроков, финишная линия
# ОПТИМИЗИРОВАНО для Intel HD Graphics (без дискретной видеокарты)
# ==============================================================================
extends Node3D

## Контейнер для игроков
@onready var players_container := $Players

## Словарь экземпляров PlayerController: {peer_id: Node}
var player_instances: Dictionary = {}

## Сцена игрока (создаётся программно)
var _player_script: GDScript = preload("res://scripts/PlayerController.gd")

## Окружение (для настроек графики)
var _world_env: WorldEnvironment
var _env: Environment
var _dir_light: DirectionalLight3D

var _finish_mesh: MeshInstance3D
var _finish_label: Label3D


func _ready() -> void:
	_setup_environment()
	_setup_finish_line()
	_setup_grid_floor()

	# Подписываемся на сетевые события
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.lobby_updated.connect(_on_lobby_updated)

	# Состояние игры
	GameManager.state_changed.connect(_on_game_state_changed)
	GameManager.player_won.connect(_on_player_won)

	# Настройки графики
	UI_Manager.graphics_changed.connect(_update_graphics)
	# Применяем текущие настройки (по умолчанию LOW=0 или сохранённые)
	_update_graphics(UI_Manager.current_quality)


## Настройка окружения
func _setup_environment() -> void:
	_world_env = WorldEnvironment.new()
	_world_env.name = "WorldEnvironment"

	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.02, 0.02, 0.05)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.15, 0.18, 0.3)
	_env.ambient_light_energy = 0.6

	# Дефолт: настройки LOW
	_env.fog_enabled = false
	_env.glow_enabled = false
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.0

	_world_env.environment = _env
	add_child(_world_env)

	_dir_light = DirectionalLight3D.new()
	_dir_light.name = "DirectionalLight"
	_dir_light.light_color = Color(0.8, 0.85, 0.95)
	_dir_light.light_energy = 0.5
	_dir_light.rotation_degrees = Vector3(-45, 30, 0)
	_dir_light.shadow_enabled = false  # Дефолт: без теней
	add_child(_dir_light)


func _update_graphics(quality: int) -> void:
	print("[Main] Применяем графику: %d" % quality)
	match quality:
		0: # LOW
			_env.fog_enabled = false
			_env.glow_enabled = false
			_env.ssao_enabled = false
			_env.ssil_enabled = false
			_env.sdfgi_enabled = false
			_dir_light.shadow_enabled = false
			_env.background_color = Color(0.02, 0.02, 0.05) # Простое темное
		1: # MEDIUM
			_env.fog_enabled = true
			_env.fog_light_color = Color(0.12, 0.15, 0.25)
			_env.fog_density = 0.002
			_env.glow_enabled = true
			_env.glow_intensity = 0.8
			_env.glow_bloom = 0.02
			_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
			_env.ssao_enabled = true
			_env.ssao_intensity = 1.0
			_dir_light.shadow_enabled = true
			_dir_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			_dir_light.shadow_blur = 1.5
			_env.background_color = Color(0.04, 0.04, 0.08)
		2: # ULTRA
			_env.fog_enabled = true
			_env.fog_light_color = Color(0.1, 0.12, 0.2)
			_env.fog_density = 0.003
			
			var renderer_method = ProjectSettings.get_setting("rendering/renderer/rendering_method")
			if renderer_method == "forward_plus":
				_env.volumetric_fog_enabled = true
				_env.volumetric_fog_density = 0.015
				_env.volumetric_fog_albedo = Color(0.8, 0.85, 0.9) # Слегка синеватый
				_env.volumetric_fog_emission = Color(0.01, 0.01, 0.02)
				_env.volumetric_fog_anisotropy = 0.6
				_env.ssil_enabled = true
				_env.sdfgi_enabled = true
				
			_env.glow_enabled = true
			_env.glow_intensity = 1.2
			_env.glow_bloom = 0.05
			_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
			_env.ssao_enabled = true
			_env.ssao_radius = 1.5
			_env.ssao_intensity = 2.0
			
			_dir_light.shadow_enabled = true
			_dir_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			_dir_light.shadow_blur = 2.5
			get_viewport().msaa_3d = Viewport.MSAA_4X

	# OmniLight УБРАН — экономим один источник света


## Настройка финишной линии (упрощённая)
func _setup_finish_line() -> void:
	_finish_mesh = MeshInstance3D.new()
	_finish_mesh.name = "FinishLine"

	# Уменьшенная плоскость
	var plane := BoxMesh.new()
	plane.size = Vector3(20, 0.05, 20)
	_finish_mesh.mesh = plane

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.85, 0.0, 0.2)
	# Emission ОТКЛЮЧЁН на финишной линии — экономим
	mat.emission_enabled = false
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_finish_mesh.material_override = mat

	_finish_mesh.position = Vector3(6, GameManager.finish_height, 0)
	add_child(_finish_mesh)

	# Надпись "ФИНИШ" — уменьшен размер шрифта
	_finish_label = Label3D.new()
	_finish_label.name = "FinishLabel"
	_finish_label.text = "ФИНИШ — %.0f м" % GameManager.finish_height
	_finish_label.font_size = 48
	_finish_label.pixel_size = 0.015
	_finish_label.modulate = Color(1.0, 0.85, 0.0)
	_finish_label.outline_size = 4
	_finish_label.outline_modulate = Color(0.3, 0.2, 0.0)
	_finish_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_finish_label.position = Vector3(6, GameManager.finish_height + 0.5, 0)
	add_child(_finish_label)


## Сетка на полу — СИЛЬНО УПРОЩЕНА (меньше мешей)
func _setup_grid_floor() -> void:
	# Плоскость-пол уменьшена
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Floor"

	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	floor_mesh.mesh = plane

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.04, 0.05, 0.1)
	# Emission отключён — просто тёмный пол
	mat.emission_enabled = false
	mat.metallic = 0.0
	mat.roughness = 0.8
	floor_mesh.material_override = mat

	floor_mesh.position = Vector3(6, -0.01, 0)
	add_child(floor_mesh)

	# Коллизия пола
	var floor_body := StaticBody3D.new()
	floor_body.name = "FloorBody"
	var floor_col := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(40, 0.1, 40)
	floor_col.shape = floor_shape
	floor_body.position = Vector3(6, -0.06, 0)
	floor_body.add_child(floor_col)
	add_child(floor_body)

	# Сетка: ВСЕГО 10 линий вместо 42 (5 горизонт. + 5 вертикал.)
	# Используем один общий материал
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.0, 0.3, 0.4)
	line_mat.emission_enabled = false  # Без emission — дешевле

	for i in range(-2, 3):
		# Горизонтальная линия
		var line := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(40, 0.01, 0.03)
		line.mesh = box
		line.material_override = line_mat
		line.position = Vector3(6, 0, i * 5.0)
		add_child(line)

		# Вертикальная линия
		var line2 := MeshInstance3D.new()
		var box2 := BoxMesh.new()
		box2.size = Vector3(0.03, 0.01, 40)
		line2.mesh = box2
		line2.material_override = line_mat
		line2.position = Vector3(i * 5.0, 0, 0)
		add_child(line2)


# ==============================================================================
# Спавн и удаление игроков
# ==============================================================================

## Создать экземпляр PlayerController для данного пира
func _spawn_player(peer_id: int, info: Dictionary) -> void:
	if player_instances.has(peer_id):
		return

	var player := CharacterBody3D.new()
	player.name = "Player_%d" % peer_id
	player.set_script(_player_script)
	player.peer_id = peer_id
	player.nickname = info.get("nickname", "Игрок")
	player.player_color = info.get("color", Color.CYAN)

	players_container.add_child(player)

	var slot: int = info.get("slot", 0)
	player.set_slot(slot)

	player_instances[peer_id] = player
	print("[Main] Игрок %d (%s) заспавнен" % [peer_id, player.nickname])


## Удалить игрока
func _despawn_player(peer_id: int) -> void:
	if player_instances.has(peer_id):
		var player: Node = player_instances[peer_id]
		player.queue_free()
		player_instances.erase(peer_id)
		print("[Main] Игрок %d удалён" % peer_id)


# ==============================================================================
# Обработчики сигналов
# ==============================================================================

func _on_player_connected(peer_id: int, info: Dictionary) -> void:
	_spawn_player(peer_id, info)


func _on_player_disconnected(peer_id: int) -> void:
	_despawn_player(peer_id)


func _on_lobby_updated(players: Dictionary) -> void:
	for peer_id in players:
		if not player_instances.has(peer_id):
			_spawn_player(peer_id, players[peer_id])
		else:
			# Обновляем цвет у существующего игрока
			var player = player_instances[peer_id]
			var new_color: Color = players[peer_id].get("color", Color.CYAN)
			if player.player_color != new_color:
				player.set_player_color(new_color)


	var to_remove: Array[int] = []
	for peer_id in player_instances:
		if not players.has(peer_id):
			to_remove.append(peer_id)
	for peer_id in to_remove:
		_despawn_player(peer_id)


func _on_game_state_changed(new_state: GameManager.GameState) -> void:
	if new_state == GameManager.GameState.LOBBY:
		for peer_id in player_instances:
			var player = player_instances[peer_id]
			if player.has_method("reset_position"):
				player.reset_position()
	elif new_state == GameManager.GameState.PLAYING or new_state == GameManager.GameState.LOADING:
		if is_instance_valid(_finish_mesh):
			_finish_mesh.position = Vector3(6, GameManager.finish_height, 0)
		if is_instance_valid(_finish_label):
			_finish_label.text = "ФИНИШ — %.0f м" % GameManager.finish_height
			_finish_label.position = Vector3(6, GameManager.finish_height + 0.5, 0)


func _on_player_won(_peer_id: int, _nickname: String) -> void:
	pass
