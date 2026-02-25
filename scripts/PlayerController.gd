# ==============================================================================
# PlayerController.gd — Контроллер игрока (CharacterBody3D)
# Управляет визуалом, столбами и камерой
# ==============================================================================
extends CharacterBody3D

## ID пира, которому принадлежит этот игрок
@export var peer_id: int = 0

## Ник игрока
@export var nickname: String = "Игрок"

## Цвет игрока
@export var player_color: Color = Color.CYAN

## Текущая высота (верхушка последнего столба)
var current_height: float = 0.0

## Контейнер для столбов
var _pillars_container: Node3D

## Ссылка на камеру (только для локального игрока)
var _camera: Camera3D

## Ссылка на меш игрока
var _mesh: MeshInstance3D

## Ссылка на Label3D с ником
var _name_label: Label3D

## Целевая позиция (для плавного перемещения)
var _target_position: Vector3 = Vector3.ZERO
var _is_moving: bool = false
const MOVE_SPEED: float = 8.0

## Горизонтальное смещение (чтобы игроки не стояли друг на друге)
var _horizontal_offset: Vector3 = Vector3.ZERO

## Режим наблюдателя (свободная камера)
var spectator_mode: bool = false
var _orbit_yaw: float = 0.0
var _orbit_pitch: float = -25.0
var _orbit_distance: float = 15.0
var _orbit_target: Vector3 = Vector3(6, 2, 0)
var _mouse_dragging: bool = false


func _ready() -> void:
	_setup_visual()
	_setup_pillars_container()

	# Камера — только для локального игрока
	if peer_id == multiplayer.get_unique_id():
		_setup_camera()

	# Подписываемся на события GameManager
	GameManager.player_answered.connect(_on_player_answered)
	
	# Подписываемся на настройки графики
	UI_Manager.graphics_changed.connect(_on_graphics_changed)
	_update_glow_state() # Применить текущие

	# Начальная позиция
	_target_position = position
	print("[PlayerController] Игрок %d (%s) создан" % [peer_id, nickname])


## Настройка визуала игрока (капсула)
func _setup_visual() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.name = "PlayerMesh"

	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 0.8
	_mesh.mesh = capsule

	# Простой материал (без emission — для Intel HD)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = player_color
	mat.emission_enabled = false
	mat.metallic = 0.0
	mat.roughness = 0.5
	_mesh.material_override = mat

	_mesh.position = Vector3(0, 0.4, 0)  # Половина высоты капсулы
	add_child(_mesh)

	# Ник над головой
	_name_label = Label3D.new()
	_name_label.name = "NameLabel"
	_name_label.text = nickname
	_name_label.font_size = 24
	_name_label.pixel_size = 0.01
	_name_label.modulate = player_color
	_name_label.outline_size = 3
	_name_label.outline_modulate = Color.BLACK
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.no_depth_test = false
	_name_label.position = Vector3(0, 1.2, 0)
	_name_label.position = Vector3(0, 1.2, 0)
	add_child(_name_label)


func set_player_color(new_color: Color) -> void:
	player_color = new_color
	if _mesh and _mesh.material_override:
		_mesh.material_override.albedo_color = new_color
		if _mesh.material_override.emission_enabled:
			_mesh.material_override.emission = new_color
			
	if _name_label:
		_name_label.modulate = new_color
	
	_update_glow_state() # Обновить и блок тоже



## Настройка контейнера для столбов
func _setup_pillars_container() -> void:
	_pillars_container = Node3D.new()
	_pillars_container.name = "Pillars"
	# Столбы как дочерние мировой позиции, не привязаны к игроку
	add_child(_pillars_container)
	# Смещаем контейнер столбов обратно, чтобы столбы были в мировых координатах
	_pillars_container.top_level = true
	_pillars_container.position = Vector3(_horizontal_offset.x, 0, _horizontal_offset.z)


## Настройка камеры (Third-person)
func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "PlayerCamera"
	_camera.current = true
	_camera.fov = 60.0
	# Камера — top_level, чтобы плавно следовать за игроком
	add_child(_camera)
	_camera.top_level = true


## Установить горизонтальное смещение (слот игрока)
func set_slot(slot: int) -> void:
	var spacing: float = 3.0
	var total_offset: float = slot * spacing
	_horizontal_offset = Vector3(total_offset, 0, 0)
	position = _horizontal_offset
	_target_position = position

	if _pillars_container:
		_pillars_container.position = Vector3(_horizontal_offset.x, 0, _horizontal_offset.z)


func _physics_process(delta: float) -> void:
	# Плавное перемещение к целевой позиции
	if _is_moving:
		position = position.lerp(_target_position, MOVE_SPEED * delta)
		if position.distance_to(_target_position) < 0.05:
			position = _target_position
			_is_moving = false

	# Камера
	if _camera:
		if spectator_mode:
			# Режим наблюдателя: орбитальная камера
			_orbit_target = _orbit_target.lerp(Vector3(6, current_height * 0.5 + 2, 0), 2.0 * delta)
			var yaw_rad := deg_to_rad(_orbit_yaw)
			var pitch_rad := deg_to_rad(_orbit_pitch)
			var offset := Vector3(
				_orbit_distance * cos(pitch_rad) * sin(yaw_rad),
				_orbit_distance * sin(-pitch_rad),
				_orbit_distance * cos(pitch_rad) * cos(yaw_rad)
			)
			var target_pos := _orbit_target + offset
			_camera.position = _camera.position.lerp(target_pos, 5.0 * delta)
			_camera.look_at(_orbit_target)
		else:
			# Обычный режим: камера следует за игроком
			var cam_target := position + Vector3(-2, 3, 6)
			_camera.position = _camera.position.lerp(cam_target, 3.0 * delta)
			_camera.look_at(position + Vector3(0, 1, 0))


func _unhandled_input(event: InputEvent) -> void:
	if not spectator_mode or not _camera:
		return

	# Вращение камеры с зажатой ЛКМ
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_mouse_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_orbit_distance = maxf(_orbit_distance - 1.5, 5.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_orbit_distance = minf(_orbit_distance + 1.5, 50.0)

	if event is InputEventMouseMotion and _mouse_dragging:
		_orbit_yaw += event.relative.x * 0.3
		_orbit_pitch = clampf(_orbit_pitch + event.relative.y * 0.3, -80.0, 80.0)


## Обработка ответа игрока — спавн столба
func _on_player_answered(answered_peer_id: int, word: String, new_height: float) -> void:
	if answered_peer_id != peer_id:
		return

	var pillar_height: float = (new_height - current_height)

	# Создаём столб
	var pillar := preload("res://scripts/PillarGenerator.gd").create_pillar(
		word,
		pillar_height,
		player_color,
		current_height
	)
	pillar.position = Vector3.ZERO
	# Добавляем в контейнер столбов
	_pillars_container.add_child(pillar)

	# Обновляем высоту и цель
	current_height = new_height
	_target_position = Vector3(_horizontal_offset.x, current_height, _horizontal_offset.z)
	_is_moving = true
	
	_update_glow_state() # Обновить свечение (перенести на новый блок)

	print("[PlayerController] Игрок %d: столб \"%s\", высота → %.1f" % [peer_id, word, current_height])


	# Сброс позиции (для нового раунда)
func reset_position() -> void:
	current_height = 0.0
	_target_position = Vector3(_horizontal_offset.x, 0, _horizontal_offset.z)
	position = _target_position
	_is_moving = false

	# Удаляем все столбы
	for child in _pillars_container.get_children():
		child.queue_free()

	_update_glow_state()


func _on_graphics_changed(_quality: int) -> void:
	_update_glow_state()


func _update_glow_state() -> void:
	var quality: int = UI_Manager.current_quality
	var is_glowing: bool = (quality >= 1)
	
	# 1. Свечение игрока
	if _mesh and _mesh.material_override:
		var mat := _mesh.material_override as StandardMaterial3D
		if mat:
			mat.emission_enabled = is_glowing
			if is_glowing:
				mat.emission = player_color
				mat.emission_energy = 0.5 if quality == 1 else 0.8
	
	# 2. Свечение верхнего блока
	# Сначала выключаем у всех (или предыдущего), чтобы не было "шлейфа"
	for child in _pillars_container.get_children():
		var mesh_inst = child.get_node_or_null("PillarMesh")
		if mesh_inst and mesh_inst.material_override:
			mesh_inst.material_override.emission_enabled = false
			
	# Включаем у последнего (верхнего)
	if is_glowing and _pillars_container.get_child_count() > 0:
		var top_pillar = _pillars_container.get_child(_pillars_container.get_child_count() - 1)
		var mesh_inst = top_pillar.get_node_or_null("PillarMesh")
		if mesh_inst and mesh_inst.material_override:
			mesh_inst.material_override.emission_enabled = true
			mesh_inst.material_override.emission = player_color
			mesh_inst.material_override.emission_energy = 1.0 if quality == 1 else 1.5

