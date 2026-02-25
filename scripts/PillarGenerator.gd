# ==============================================================================
# PillarGenerator.gd — Генерация 3D столбов с буквами (Label3D)
# ОПТИМИЗИРОВАНО: только 2 грани с текстом, без emission-кромок
# ==============================================================================
extends Node

## Материал для столба — БЕЗ emission (дешевле для Intel HD)
static func create_pillar_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	# Emission отключён — используем яркий albedo вместо свечения
	mat.emission_enabled = false
	mat.metallic = 0.0
	mat.roughness = 0.6
	return mat


## Создать столб с буквами
## ОПТИМИЗАЦИЯ: текст только на 2 гранях (передней и задней), без кромок
static func create_pillar(word: String, pillar_height: float, color: Color, base_y: float) -> Node3D:
	var pillar_node := Node3D.new()
	pillar_node.name = "Pillar_%s" % word

	# --- Столб (BoxMesh) ---
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "PillarMesh"

	var box := BoxMesh.new()
	var pillar_width: float = 1.2
	box.size = Vector3(pillar_width, pillar_height, pillar_width)
	mesh_instance.mesh = box
	mesh_instance.material_override = create_pillar_material(color)

	# Позиция: центр столба
	mesh_instance.position = Vector3(0, base_y + pillar_height / 2.0, 0)
	pillar_node.add_child(mesh_instance)

	# Коллизия столба
	var body := StaticBody3D.new()
	body.name = "PillarBody"
	var col := CollisionShape3D.new()
	var col_shape := BoxShape3D.new()
	col_shape.size = Vector3(pillar_width, pillar_height, pillar_width)
	col.shape = col_shape
	body.position = Vector3(0, base_y + pillar_height / 2.0, 0)
	body.add_child(col)
	pillar_node.add_child(body)

	# --- Буквы только на 2 гранях (передняя + задняя) ---
	var half_w: float = pillar_width / 2.0 + 0.01
	var text: String = word.to_upper()

	# Только 2 грани вместо 4 — экономим 2 Label3D на столб
	var faces: Array[Dictionary] = [
		{"offset": Vector3(0, 0, half_w), "rot_y": 0.0},           # Передняя
		{"offset": Vector3(0, 0, -half_w), "rot_y": PI},           # Задняя
	]

	for i in range(faces.size()):
		var face: Dictionary = faces[i]
		var label := Label3D.new()
		label.name = "Label_face_%d" % i
		label.text = text
		label.font_size = 36  # Уменьшен с 48
		label.pixel_size = 0.01
		label.modulate = Color.WHITE  # Белый текст — виднее без emission
		label.outline_size = 3
		label.outline_modulate = color.darkened(0.5)
		label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		label.double_sided = false
		label.no_depth_test = false

		label.position = Vector3(
			face["offset"].x,
			base_y + pillar_height / 2.0,
			face["offset"].z
		)
		label.rotation.y = face["rot_y"]

		# Уменьшаем шрифт для длинных слов
		if text.length() > 8:
			label.font_size = max(20, 36 - (text.length() - 8) * 2)

		pillar_node.add_child(label)

	# Кромки УБРАНЫ — экономим 2 MeshInstance3D на столб

	return pillar_node
