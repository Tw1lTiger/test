# ==============================================================================
# UI_Manager.gd — Управление всеми UI-экранами (CanvasLayer)
# ==============================================================================
extends CanvasLayer

signal graphics_changed(quality: int)

# ==============================================================================
# Узлы UI (создаются программно)
# ==============================================================================

## --- Лобби ---
var _lobby_panel: PanelContainer
var _nickname_input: LineEdit
var _ip_input: LineEdit
var _port_input: LineEdit
var _create_btn: Button
var _join_btn: Button
var _start_btn: Button
var _players_list: VBoxContainer
var _lobby_status: Label
var _question_mode_toggle: CheckButton
var _color_buttons: Array[Button] = []
var _topic_input: LineEdit
var _points_input: LineEdit

## --- Викторина UI ---
var _quiz_mode_toggle: CheckButton
var _quiz_time_option: OptionButton
var _quiz_rounds_option: OptionButton
var _quiz_settings_container: VBoxContainer
var _word_race_settings_container: VBoxContainer

## --- Панель серверов ---
var _servers_container: VBoxContainer
var _servers_scroll: ScrollContainer
var _no_servers_label: Label

## --- Игровой экран ---
var _game_panel: PanelContainer
var _question_label: Label
var _answer_input: LineEdit
var _submit_btn: Button
var _round_label: Label
var _timer_label: Label
var _validation_label: Label
var _height_info: VBoxContainer
var _answer_log: VBoxContainer

## --- Викторина: многострочный ввод ---
var _quiz_answer_edit: TextEdit
var _quiz_submit_btn: Button
var _quiz_char_count: Label
var _quiz_input_container: VBoxContainer
var _word_input_container: HBoxContainer

## --- Наблюдение (спектатор) ---
var _spectator_btn: Button
var _spectator_hint: Label
var _is_spectating: bool = false

## --- Экран победы ---
var _win_panel: PanelContainer
var _winner_label: Label
var _scores_list: VBoxContainer
var _lobby_return_btn: Button

## --- Меню паузы ---
var _pause_overlay: ColorRect
var _pause_panel: PanelContainer
var _resume_btn: Button
var _settings_btn: Button
var _exit_lobby_btn: Button
var _is_paused: bool = false

## --- Панель настроек ---
var _settings_panel: PanelContainer
var _settings_back_btn: Button
var _volume_slider: HSlider
var _volume_label: Label
var _fullscreen_toggle: CheckButton

var _quality_option: OptionButton
var _resolution_option: OptionButton
var _settings_visible: bool = false
var current_quality: int = 0  # 0=Low, 1=Med, 2=Ultra

## --- Панель результатов викторины ---
var _quiz_results_panel: PanelContainer
var _quiz_results_vbox: VBoxContainer

## --- Панель истории ---
var _history_panel: PanelContainer
var _history_vbox: VBoxContainer

## --- Код комнаты ---
var _room_code_label: Label
var _room_code_input: LineEdit
var _join_code_btn: Button

## --- Панель аналитики ---
var _analytics_panel: PanelContainer
var _analytics_vbox: VBoxContainer

## --- План изучения ---
var _study_plan_panel: PanelContainer
var _study_plan_vbox: VBoxContainer

## --- Ссылка на GeminiAPI ---
var _gemini_api: Node

## --- Диалог экспорта ---
var _export_dialog: FileDialog
enum ExportMode { HISTORY, STUDY_PLAN }
var _export_mode: ExportMode = ExportMode.HISTORY
var _current_study_plan: Dictionary = {}

## --- Общие стили ---
var _font_color := Color(0.9, 0.95, 1.0)
var _accent_color := Color(0.0, 1.0, 0.9)

var _panel_color := Color(0.08, 0.09, 0.16, 0.95)
var _input_bg := Color(0.12, 0.14, 0.25, 0.95)


func _ready() -> void:
	layer = 10  # Поверх всего

	_create_lobby_ui()
	_create_game_ui()
	_create_win_ui()
	_create_pause_menu()
	_create_settings_panel()
	_create_quiz_results_panel()
	_create_history_panel()
	_create_analytics_panel()
	_create_study_plan_panel()
	_create_export_dialog()

	# Начальное состояние — показываем лобби
	_show_lobby()

	# Подключаем сигналы
	NetworkManager.lobby_updated.connect(_on_lobby_updated)
	NetworkManager.server_created.connect(_on_server_created)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)

	GameManager.state_changed.connect(_on_state_changed)
	GameManager.question_received.connect(_on_question_received)
	GameManager.player_answered.connect(_on_player_answered)
	GameManager.player_won.connect(_on_player_won)
	GameManager.answer_rejected.connect(_on_answer_rejected)
	GameManager.round_number_changed.connect(_on_round_changed)
	GameManager.timer_updated.connect(_on_timer_updated)
	GameManager.answer_invalid.connect(_on_answer_invalid)
	GameManager.answer_checking.connect(_on_answer_checking)
	GameManager.loading_status.connect(_on_loading_status)
	GameManager.answer_accepted.connect(_on_answer_accepted)

	# Сигналы викторины
	GameManager.quiz_question_received.connect(_on_quiz_question_received)
	GameManager.quiz_answer_accepted.connect(_on_quiz_answer_accepted)
	GameManager.quiz_results_received.connect(_on_quiz_results_received)
	GameManager.quiz_game_finished.connect(_on_quiz_game_finished)
	GameManager.quiz_evaluating.connect(_on_quiz_evaluating)

	# LAN Discovery
	LANDiscovery.server_list_updated.connect(_on_server_list_updated)
	
	# === Загрузка настроек ===
	_apply_loaded_settings()


func _apply_loaded_settings() -> void:
	# 1. Volume
	var vol: float = SettingsManager.settings.volume
	_volume_slider.value = vol
	_on_volume_changed(vol) # Применить звук
	
	# 2. Quality
	var quality: int = SettingsManager.settings.quality
	current_quality = quality
	if _quality_option:
		_quality_option.selected = quality
	# Сигнал для Main.gd отправится позже, когда Main загрузится, 
	# или Main сам должен взять настройки.
	# Но так как Main слушает UI_Manager.graphics_changed, то эмитим сейчас:
	graphics_changed.emit(quality)

	# 3. Resolution
	var res_idx: int = SettingsManager.settings.resolution
	if _resolution_option:
		_resolution_option.selected = res_idx
	_on_resolution_selected(res_idx)
	
	# 4. Fullscreen
	var fs: bool = SettingsManager.settings.fullscreen
	_fullscreen_toggle.button_pressed = fs
	_on_fullscreen_toggled(fs)


func _on_quality_selected(index: int) -> void:
	current_quality = index
	graphics_changed.emit(index)
	SettingsManager.settings.quality = index
	SettingsManager.save_settings()


func _on_resolution_selected(index: int) -> void:
	SettingsManager.settings.resolution = index
	SettingsManager.save_settings()
	
	match index:
		0: _set_window_size(1280, 720)
		1: _set_window_size(1600, 900)
		2: _set_window_size(1920, 1080)
		3: _set_window_size(2560, 1440)
		4: 
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			_fullscreen_toggle.button_pressed = true


func _set_window_size(w: int, h: int) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(w, h))
	_fullscreen_toggle.button_pressed = false
	# Центрируем окно
	var screen_size := DisplayServer.screen_get_size()
	var pos := Vector2i((Vector2(screen_size) - Vector2(w, h)) / 2.0)
	DisplayServer.window_set_position(pos)


func _on_volume_changed(value: float) -> void:
	_volume_label.text = "%d%%" % int(value)
	AudioManager.set_volume(value)
	SettingsManager.settings.volume = value
	SettingsManager.save_settings()


func _on_fullscreen_toggled(enabled: bool) -> void:
	SettingsManager.settings.fullscreen = enabled
	SettingsManager.save_settings()

	if enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


# ==============================================================================
# Создание UI-экранов
# ==============================================================================

## Создаёт общий стиль для панелей
func _create_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = _panel_color
	style.border_color = _accent_color.darkened(0.5)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(20)
	return style


func _create_input_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = _input_bg
	style.border_color = _accent_color.darkened(0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	return style


func _create_button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color.darkened(0.4)
	style.border_color = color
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	return style


func _create_styled_button(text: String, color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", color)
	btn.add_theme_stylebox_override("normal", _create_button_style(color))

	var hover_style := _create_button_style(color)
	hover_style.bg_color = color.darkened(0.2)
	btn.add_theme_stylebox_override("hover", hover_style)

	var pressed_style := _create_button_style(color)
	pressed_style.bg_color = color.darkened(0.1)
	btn.add_theme_stylebox_override("pressed", pressed_style)

	btn.custom_minimum_size.y = 44
	return btn


func _create_styled_input(placeholder: String) -> LineEdit:
	var input := LineEdit.new()
	input.placeholder_text = placeholder
	input.add_theme_font_size_override("font_size", 16)
	input.add_theme_color_override("font_color", _font_color)
	input.add_theme_color_override("font_placeholder_color", Color(0.4, 0.45, 0.6))
	input.add_theme_stylebox_override("normal", _create_input_style())
	input.add_theme_stylebox_override("focus", _create_input_style())
	input.custom_minimum_size.y = 40
	return input


func _create_label(text: String, size: int = 16, color: Color = Color(0.9, 0.95, 1.0)) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


# ==============================================================================
# Лобби UI
# ==============================================================================

func _create_lobby_ui() -> void:
	_lobby_panel = PanelContainer.new()
	_lobby_panel.name = "LobbyPanel"
	_lobby_panel.add_theme_stylebox_override("panel", _create_panel_style())
	_lobby_panel.set_anchors_preset(Control.PRESET_CENTER)
	_lobby_panel.custom_minimum_size = Vector2(500, 0)

	# Центрируем вручную — используем больше экрана по высоте
	_lobby_panel.anchor_left = 0.5
	_lobby_panel.anchor_top = 0.0
	_lobby_panel.anchor_right = 0.5
	_lobby_panel.anchor_bottom = 1.0
	_lobby_panel.offset_left = -270
	_lobby_panel.offset_right = 270
	_lobby_panel.offset_top = 20
	_lobby_panel.offset_bottom = -20

	# Прокручиваемое содержимое лобби
	var lobby_scroll := ScrollContainer.new()
	lobby_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lobby_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lobby_panel.add_child(lobby_scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_scroll.add_child(vbox)

	# Заголовок
	var title := _create_label("⚡ WORD RACE ⚡", 32, _accent_color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var subtitle := _create_label("Гонка на словах", 16, Color(0.5, 0.55, 0.7))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)
	
	# Выбор цвета
	var color_picker := _create_color_buttons()
	vbox.add_child(color_picker)

	# Разделитель
	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", _accent_color.darkened(0.5))
	vbox.add_child(sep)

	# Ник
	vbox.add_child(_create_label("Никнейм:", 14, Color(0.6, 0.65, 0.8)))
	_nickname_input = _create_styled_input("Введите никнейм...")
	_nickname_input.text = "Игрок"
	_nickname_input.max_length = 20
	vbox.add_child(_nickname_input)

	# IP / Порт
	var net_hbox := HBoxContainer.new()
	net_hbox.add_theme_constant_override("separation", 8)

	var ip_vbox := VBoxContainer.new()
	ip_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ip_vbox.add_child(_create_label("IP адрес:", 14, Color(0.6, 0.65, 0.8)))
	_ip_input = _create_styled_input("127.0.0.1")
	_ip_input.text = "127.0.0.1"
	ip_vbox.add_child(_ip_input)
	net_hbox.add_child(ip_vbox)

	var port_vbox := VBoxContainer.new()
	port_vbox.custom_minimum_size.x = 100
	port_vbox.add_child(_create_label("Порт:", 14, Color(0.6, 0.65, 0.8)))
	_port_input = _create_styled_input("9876")
	_port_input.text = "9876"
	port_vbox.add_child(_port_input)
	net_hbox.add_child(port_vbox)

	net_hbox.visible = false
	vbox.add_child(net_hbox)

	# Тема вопросов
	vbox.add_child(_create_label("Тема вопросов:", 14, Color(0.6, 0.65, 0.8)))
	_topic_input = _create_styled_input("Например: Космос")
	vbox.add_child(_topic_input)

	# ============ РЕЖИМ ИГРЫ ============
	var mode_sep := HSeparator.new()
	mode_sep.add_theme_color_override("separator", _accent_color.darkened(0.5))
	vbox.add_child(mode_sep)

	# Переключатель режима: Гонка слов / Викторина
	_quiz_mode_toggle = CheckButton.new()
	_quiz_mode_toggle.text = "🏫 Режим: Гонка слов"
	_quiz_mode_toggle.button_pressed = false
	_quiz_mode_toggle.add_theme_font_size_override("font_size", 16)
	_quiz_mode_toggle.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	_quiz_mode_toggle.add_theme_color_override("font_pressed_color", Color(0.4, 1.0, 0.6))
	_quiz_mode_toggle.toggled.connect(_on_quiz_mode_toggled)
	vbox.add_child(_quiz_mode_toggle)

	# === Настройки Гонки слов ===
	_word_race_settings_container = VBoxContainer.new()
	_word_race_settings_container.add_theme_constant_override("separation", 8)

	# Режим вопросов (ИИ / Обычные)
	var wr_mode_hbox := HBoxContainer.new()
	wr_mode_hbox.add_theme_constant_override("separation", 10)
	_question_mode_toggle = CheckButton.new()
	_question_mode_toggle.text = "🤖 Вопросы от ИИ"
	_question_mode_toggle.button_pressed = true
	_question_mode_toggle.add_theme_font_size_override("font_size", 16)
	_question_mode_toggle.add_theme_color_override("font_color", _accent_color)
	_question_mode_toggle.add_theme_color_override("font_pressed_color", Color(0.2, 1.0, 0.4))
	_question_mode_toggle.add_theme_color_override("font_hover_color", _accent_color.lightened(0.3))
	_question_mode_toggle.toggled.connect(_on_question_mode_toggled)
	wr_mode_hbox.add_child(_question_mode_toggle)
	_word_race_settings_container.add_child(wr_mode_hbox)

	# Очки для победы
	_word_race_settings_container.add_child(_create_label("Очки для победы:", 14, Color(0.6, 0.65, 0.8)))
	_points_input = _create_styled_input("300")
	_points_input.text = "300"
	_word_race_settings_container.add_child(_points_input)
	vbox.add_child(_word_race_settings_container)

	# === Настройки Викторины ===
	_quiz_settings_container = VBoxContainer.new()
	_quiz_settings_container.add_theme_constant_override("separation", 8)
	_quiz_settings_container.visible = false

	# Время на ответ
	var time_hbox := HBoxContainer.new()
	time_hbox.add_theme_constant_override("separation", 10)
	time_hbox.add_child(_create_label("⏱ Время на ответ:", 14, Color(0.6, 0.65, 0.8)))
	_quiz_time_option = OptionButton.new()
	_quiz_time_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quiz_time_option.add_item("30 секунд")
	_quiz_time_option.add_item("60 секунд")
	_quiz_time_option.add_item("90 секунд")
	_quiz_time_option.add_item("120 секунд")
	_quiz_time_option.select(1)  # 60 сек по умолчанию
	time_hbox.add_child(_quiz_time_option)
	_quiz_settings_container.add_child(time_hbox)

	# Количество раундов
	var rounds_hbox := HBoxContainer.new()
	rounds_hbox.add_theme_constant_override("separation", 10)
	rounds_hbox.add_child(_create_label("🔄 Раундов:", 14, Color(0.6, 0.65, 0.8)))
	_quiz_rounds_option = OptionButton.new()
	_quiz_rounds_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quiz_rounds_option.add_item("3 раунда")
	_quiz_rounds_option.add_item("5 раундов")
	_quiz_rounds_option.add_item("7 раундов")
	_quiz_rounds_option.add_item("10 раундов")
	_quiz_rounds_option.select(1)  # 5 раундов по умолчанию
	rounds_hbox.add_child(_quiz_rounds_option)
	_quiz_settings_container.add_child(rounds_hbox)

	vbox.add_child(_quiz_settings_container)

	# API Key (только хост) — УБРАНО (используется встроенный ключ)

	# Кнопки создания/подключения

	# Кнопки создания/подключения
	var btn_hbox := HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 10)

	_create_btn = _create_styled_button("🖥️ Создать", _accent_color)
	_create_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_create_btn.pressed.connect(_on_create_pressed)
	btn_hbox.add_child(_create_btn)

	_join_btn = _create_styled_button("🔗 Подключиться", Color(0.4, 0.8, 1.0))
	_join_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_join_btn.pressed.connect(_on_join_pressed)
	btn_hbox.add_child(_join_btn)

	vbox.add_child(btn_hbox)

	# ============ ПОДКЛЮЧЕНИЕ ПО КОДУ ============
	var code_sep := HSeparator.new()
	code_sep.add_theme_color_override("separator", _accent_color.darkened(0.5))
	vbox.add_child(code_sep)

	# Лейбл для отображения кода комнаты (виден только после создания сервера)
	_room_code_label = _create_label("", 20, Color(0.2, 1.0, 0.4))
	_room_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_code_label.visible = false
	vbox.add_child(_room_code_label)

	# Поле ввода кода + кнопка подключения
	vbox.add_child(_create_label("🔑 Войти по коду комнаты:", 14, Color(0.6, 0.65, 0.8)))
	var code_hbox := HBoxContainer.new()
	code_hbox.add_theme_constant_override("separation", 8)

	_room_code_input = _create_styled_input("ABC123")
	_room_code_input.max_length = 6
	_room_code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_code_input.add_theme_font_size_override("font_size", 20)
	_room_code_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_code_input.text_submitted.connect(func(_t): _on_join_by_code())
	code_hbox.add_child(_room_code_input)

	_join_code_btn = _create_styled_button("🚀 Войти", Color(0.2, 1.0, 0.4))
	_join_code_btn.pressed.connect(_on_join_by_code)
	code_hbox.add_child(_join_code_btn)

	vbox.add_child(code_hbox)

	# ============ ПАНЕЛЬ СЕРВЕРОВ В СЕТИ ============
	var servers_sep := HSeparator.new()
	servers_sep.add_theme_color_override("separator", _accent_color.darkened(0.5))
	vbox.add_child(servers_sep)

	vbox.add_child(_create_label("📡 Серверы в сети:", 16, _accent_color))

	_servers_scroll = ScrollContainer.new()
	_servers_scroll.custom_minimum_size.y = 50
	vbox.add_child(_servers_scroll)

	_servers_container = VBoxContainer.new()
	_servers_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_servers_container.add_theme_constant_override("separation", 6)
	_servers_scroll.add_child(_servers_container)

	_no_servers_label = _create_label("Поиск серверов...", 13, Color(0.5, 0.5, 0.6))
	_no_servers_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_servers_container.add_child(_no_servers_label)

	# Статус
	_lobby_status = _create_label("", 14, Color(0.8, 0.6, 0.2))
	_lobby_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lobby_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_lobby_status)

	# Разделитель
	var sep2 := HSeparator.new()
	sep2.add_theme_color_override("separator", _accent_color.darkened(0.5))
	vbox.add_child(sep2)

	# Список игроков
	vbox.add_child(_create_label("Игроки в лобби:", 16, _accent_color))
	_players_list = VBoxContainer.new()
	_players_list.add_theme_constant_override("separation", 6)
	vbox.add_child(_players_list)

	# Кнопка старта (только хост)
	_start_btn = _create_styled_button("🚀 НАЧАТЬ ИГРУ", Color(0.2, 1.0, 0.4))
	_start_btn.pressed.connect(_on_start_pressed)
	_start_btn.visible = false
	_start_btn.visible = false
	vbox.add_child(_start_btn)

	var sep3 := HSeparator.new()
	sep3.add_theme_color_override("separator", _accent_color.darkened(0.5))
	vbox.add_child(sep3)

	# Кнопка настроек в лобби
	var settings_btn := _create_styled_button("⚙️ Настройки", Color(0.4, 0.8, 1.0))
	settings_btn.pressed.connect(_on_settings_pressed)
	vbox.add_child(settings_btn)

	# Кнопка истории студента
	var history_btn := _create_styled_button("📊 Моя история", Color(0.8, 0.6, 1.0))
	history_btn.pressed.connect(_on_history_pressed)
	vbox.add_child(history_btn)

	# Кнопка аналитики преподавателя
	var analytics_btn := _create_styled_button("📈 Аналитика", Color(0.4, 0.8, 0.6))
	analytics_btn.pressed.connect(_on_analytics_pressed)
	vbox.add_child(analytics_btn)

	add_child(_lobby_panel)


# ==============================================================================
# Игровой экран UI
# ==============================================================================

func _create_color_buttons() -> HBoxContainer:
	var container := HBoxContainer.new()
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	container.add_theme_constant_override("separation", 15)
	
	_color_buttons.clear()
	var colors: Array[Color] = NetworkManager.PLAYER_COLORS
	
	for i in range(colors.size()):
		var color := colors[i]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(40, 40)
		btn.flat = false
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		
		# Стиль
		var style := StyleBoxFlat.new()
		style.bg_color = color
		style.set_corner_radius_all(20) # Круг
		style.set_border_width_all(2)
		style.border_color = Color.WHITE.darkened(0.2)
		
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("pressed", style)
		
		# Обработка нажатия
		btn.pressed.connect(_on_color_button_pressed.bind(i))
		container.add_child(btn)
		_color_buttons.append(btn)
		
	# Инициализация визуала
	_update_color_selection_visuals()
	return container


func _on_color_button_pressed(idx: int) -> void:
	if idx < 0 or idx >= NetworkManager.PLAYER_COLORS.size():
		return
		
	var color := NetworkManager.PLAYER_COLORS[idx]
	
	# Обновляем локально
	NetworkManager.local_player_info["color"] = color
	
	# Визуальная обратная связь
	_update_color_selection_visuals()
	
	# Если уже подключены — обновляем на сервере (ID 1 = Хост)
	if NetworkManager.multiplayer.has_multiplayer_peer():
		NetworkManager.request_color_change.rpc_id(1, idx)


func _update_color_selection_visuals() -> void:
	var current_color: Color = NetworkManager.local_player_info.get("color", Color.WHITE)
	var colors: Array[Color] = NetworkManager.PLAYER_COLORS
	
	for i in range(_color_buttons.size()):
		if i >= colors.size(): break
		
		var btn := _color_buttons[i]
		var color := colors[i]
		var style: StyleBoxFlat = btn.get_theme_stylebox("normal").duplicate()
		
		if color == current_color:
			# Выбранный: белая обводка, чуть больше
			style.set_border_width_all(4)
			style.border_color = Color.WHITE
			btn.custom_minimum_size = Vector2(48, 48)
		else:
			# Обычный
			style.set_border_width_all(2)
			style.border_color = Color.WHITE.darkened(0.2)
			btn.custom_minimum_size = Vector2(40, 40)
			
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("pressed", style)



func _create_game_ui() -> void:
	_game_panel = PanelContainer.new()
	_game_panel.name = "GamePanel"

	# Расположение: снизу по центру
	_game_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_game_panel.anchor_top = 0.65
	_game_panel.offset_left = 20
	_game_panel.offset_right = -20
	_game_panel.offset_bottom = -20

	var game_style := _create_panel_style()
	game_style.bg_color = Color(0.04, 0.05, 0.1, 0.85)
	_game_panel.add_theme_stylebox_override("panel", game_style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 20)
	_game_panel.add_child(hbox)

	# Левая часть: вопрос + ввод
	var left_vbox := VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.add_theme_constant_override("separation", 10)
	hbox.add_child(left_vbox)

	# Строка: раунд + таймер
	var top_hbox := HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 20)
	left_vbox.add_child(top_hbox)

	_round_label = _create_label("Раунд 1", 14, Color(0.5, 0.55, 0.7))
	top_hbox.add_child(_round_label)

	_timer_label = _create_label("⏱ 30", 20, Color(0.2, 1.0, 0.4))
	top_hbox.add_child(_timer_label)

	_question_label = _create_label("Ожидание вопроса...", 22, Color.WHITE)
	_question_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	left_vbox.add_child(_question_label)

	# Статус валидации ("Проверяю ответ...")
	_validation_label = _create_label("", 14, Color(0.8, 0.8, 0.2))
	_validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	left_vbox.add_child(_validation_label)

	# Ввод + кнопка (Гонка слов)
	_word_input_container = HBoxContainer.new()
	_word_input_container.add_theme_constant_override("separation", 10)
	_word_input_container.visible = true

	_answer_input = _create_styled_input("Введите слово...")
	_answer_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_answer_input.max_length = 30
	_answer_input.text_submitted.connect(_on_answer_submitted)
	_word_input_container.add_child(_answer_input)

	_submit_btn = _create_styled_button("✏️ Ответить", _accent_color)
	_submit_btn.pressed.connect(func(): _on_answer_submitted(_answer_input.text))
	_word_input_container.add_child(_submit_btn)

	left_vbox.add_child(_word_input_container)

	# Ввод для Викторины (многострочный)
	_quiz_input_container = VBoxContainer.new()
	_quiz_input_container.add_theme_constant_override("separation", 6)
	_quiz_input_container.visible = false

	_quiz_answer_edit = TextEdit.new()
	_quiz_answer_edit.placeholder_text = "Напишите развёрнутый ответ..."
	_quiz_answer_edit.custom_minimum_size = Vector2(0, 100)
	_quiz_answer_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quiz_answer_edit.add_theme_font_size_override("font_size", 15)
	_quiz_answer_edit.add_theme_color_override("font_color", _font_color)
	_quiz_answer_edit.add_theme_color_override("font_placeholder_color", Color(0.4, 0.45, 0.6))
	var edit_style := _create_input_style()
	_quiz_answer_edit.add_theme_stylebox_override("normal", edit_style)
	_quiz_answer_edit.add_theme_stylebox_override("focus", edit_style)
	_quiz_answer_edit.text_changed.connect(_on_quiz_text_changed)
	_quiz_input_container.add_child(_quiz_answer_edit)

	var quiz_bottom := HBoxContainer.new()
	quiz_bottom.add_theme_constant_override("separation", 10)
	_quiz_char_count = _create_label("0 / 1000", 12, Color(0.5, 0.55, 0.7))
	quiz_bottom.add_child(_quiz_char_count)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quiz_bottom.add_child(spacer)
	_quiz_submit_btn = _create_styled_button("✅ Отправить ответ", Color(0.2, 1.0, 0.4))
	_quiz_submit_btn.pressed.connect(_on_quiz_submit_pressed)
	quiz_bottom.add_child(_quiz_submit_btn)
	_quiz_input_container.add_child(quiz_bottom)

	left_vbox.add_child(_quiz_input_container)

	# Правая часть: высоты игроков + лог
	var right_vbox := VBoxContainer.new()
	right_vbox.custom_minimum_size.x = 280
	right_vbox.add_theme_constant_override("separation", 8)
	hbox.add_child(right_vbox)

	right_vbox.add_child(_create_label("📊 Прогресс:", 16, _accent_color))

	_height_info = VBoxContainer.new()
	_height_info.add_theme_constant_override("separation", 4)
	right_vbox.add_child(_height_info)

	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", Color(0.2, 0.25, 0.4))
	right_vbox.add_child(sep)

	right_vbox.add_child(_create_label("📝 Ответы:", 14, Color(0.5, 0.55, 0.7)))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 80
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(scroll)

	_answer_log = VBoxContainer.new()
	_answer_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_answer_log.add_theme_constant_override("separation", 2)
	scroll.add_child(_answer_log)

	_game_panel.visible = false
	add_child(_game_panel)

	# Кнопка наблюдения (правый верхний угол)
	_spectator_btn = Button.new()
	_spectator_btn.text = "👁 Наблюдение"
	_spectator_btn.add_theme_font_size_override("font_size", 14)
	_spectator_btn.add_theme_color_override("font_color", Color.WHITE)
	var spec_style := StyleBoxFlat.new()
	spec_style.bg_color = Color(0.15, 0.15, 0.3, 0.8)
	spec_style.set_corner_radius_all(8)
	spec_style.set_content_margin_all(8)
	_spectator_btn.add_theme_stylebox_override("normal", spec_style)
	var spec_hover := spec_style.duplicate()
	spec_hover.bg_color = Color(0.2, 0.2, 0.4, 0.9)
	_spectator_btn.add_theme_stylebox_override("hover", spec_hover)
	var spec_pressed := spec_style.duplicate()
	spec_pressed.bg_color = Color(0.0, 0.8, 0.7, 0.9)
	_spectator_btn.add_theme_stylebox_override("pressed", spec_pressed)
	_spectator_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_spectator_btn.offset_left = -170
	_spectator_btn.offset_top = 15
	_spectator_btn.offset_right = -15
	_spectator_btn.offset_bottom = 50
	_spectator_btn.pressed.connect(_on_spectator_toggled)
	_spectator_btn.visible = false
	add_child(_spectator_btn)

	# Подсказка в режиме наблюдения
	_spectator_hint = Label.new()
	_spectator_hint.text = "👁 Режим наблюдения\nЛКМ + движение мыши = вращение   |   Колёсико = приближение"
	_spectator_hint.add_theme_font_size_override("font_size", 14)
	_spectator_hint.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 0.9))
	_spectator_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spectator_hint.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_spectator_hint.offset_top = 15
	_spectator_hint.offset_left = 20
	_spectator_hint.offset_right = -20
	_spectator_hint.visible = false
	add_child(_spectator_hint)


# ==============================================================================
# Экран победы
# ==============================================================================

func _create_win_ui() -> void:
	_win_panel = PanelContainer.new()
	_win_panel.name = "WinPanel"
	_win_panel.set_anchors_preset(Control.PRESET_CENTER)

	_win_panel.anchor_left = 0.5
	_win_panel.anchor_top = 0.5
	_win_panel.anchor_right = 0.5
	_win_panel.anchor_bottom = 0.5
	_win_panel.offset_left = -250
	_win_panel.offset_right = 250
	_win_panel.offset_top = -200
	_win_panel.offset_bottom = 200

	var win_style := _create_panel_style()
	win_style.border_color = Color(1.0, 0.85, 0.0)
	win_style.set_border_width_all(3)
	_win_panel.add_theme_stylebox_override("panel", win_style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	_win_panel.add_child(vbox)

	var crown := _create_label("👑", 48, Color.WHITE)
	crown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(crown)

	_winner_label = _create_label("Победитель!", 28, Color(1.0, 0.85, 0.0))
	_winner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_winner_label)

	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", Color(0.3, 0.3, 0.15))
	vbox.add_child(sep)

	_scores_list = VBoxContainer.new()
	_scores_list.add_theme_constant_override("separation", 6)
	vbox.add_child(_scores_list)

	_lobby_return_btn = _create_styled_button("🔙 В лобби", Color(0.4, 0.8, 1.0))
	_lobby_return_btn.pressed.connect(_on_lobby_return_pressed)
	vbox.add_child(_lobby_return_btn)

	_win_panel.visible = false
	add_child(_win_panel)


# ==============================================================================
# Меню паузы (Esc)
# ==============================================================================

func _create_pause_menu() -> void:
	# Полупрозрачный оверлей
	_pause_overlay = ColorRect.new()
	_pause_overlay.name = "PauseOverlay"
	_pause_overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	_pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	# Панель меню паузы
	_pause_panel = PanelContainer.new()
	_pause_panel.name = "PausePanel"

	_pause_panel.anchor_left = 0.5
	_pause_panel.anchor_top = 0.5
	_pause_panel.anchor_right = 0.5
	_pause_panel.anchor_bottom = 0.5
	_pause_panel.offset_left = -200
	_pause_panel.offset_right = 200
	_pause_panel.offset_top = -180
	_pause_panel.offset_bottom = 180

	var pause_style := _create_panel_style()
	pause_style.bg_color = Color(0.06, 0.07, 0.14, 0.98)
	pause_style.border_color = _accent_color
	pause_style.set_border_width_all(2)
	_pause_panel.add_theme_stylebox_override("panel", pause_style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_pause_panel.add_child(vbox)

	# Заголовок
	var title := _create_label("⏸ ПАУЗА", 32, _accent_color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", _accent_color.darkened(0.5))
	vbox.add_child(sep)

	# Кнопка "Продолжить"
	_resume_btn = _create_styled_button("▶️  Продолжить", Color(0.2, 1.0, 0.4))
	_resume_btn.pressed.connect(_on_resume_pressed)
	vbox.add_child(_resume_btn)

	# Кнопка "Настройки"
	_settings_btn = _create_styled_button("⚙️  Настройки", Color(0.4, 0.8, 1.0))
	_settings_btn.pressed.connect(_on_settings_pressed)
	vbox.add_child(_settings_btn)

	var sep2 := HSeparator.new()
	sep2.add_theme_color_override("separator", Color(0.3, 0.1, 0.1))
	vbox.add_child(sep2)

	# Кнопка "Выйти в лобби"
	_exit_lobby_btn = _create_styled_button("🚪  Выйти в лобби", Color(1.0, 0.3, 0.3))
	_exit_lobby_btn.pressed.connect(_on_exit_to_lobby_pressed)
	vbox.add_child(_exit_lobby_btn)

	_pause_overlay.add_child(_pause_panel)
	_pause_overlay.visible = false
	add_child(_pause_overlay)


# ==============================================================================
# Панель настроек
# ==============================================================================

func _create_settings_panel() -> void:
	_settings_panel = PanelContainer.new()
	_settings_panel.name = "SettingsPanel"

	_settings_panel.anchor_left = 0.5
	_settings_panel.anchor_top = 0.5
	_settings_panel.anchor_right = 0.5
	_settings_panel.anchor_bottom = 0.5
	_settings_panel.offset_left = -220
	_settings_panel.offset_right = 220
	_settings_panel.offset_top = -200
	_settings_panel.offset_bottom = 200

	var settings_style := _create_panel_style()
	settings_style.bg_color = Color(0.06, 0.07, 0.14, 0.98)
	settings_style.border_color = Color(0.4, 0.8, 1.0)
	settings_style.set_border_width_all(2)
	_settings_panel.add_theme_stylebox_override("panel", settings_style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	_settings_panel.add_child(vbox)

	# Заголовок
	var title := _create_label("⚙️ НАСТРОЙКИ", 28, Color(0.4, 0.8, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", Color(0.4, 0.8, 1.0).darkened(0.5))
	vbox.add_child(sep)

	# Громкость
	vbox.add_child(_create_label("🔊 Громкость:", 16, Color(0.7, 0.75, 0.9)))

	var vol_hbox := HBoxContainer.new()
	vol_hbox.add_theme_constant_override("separation", 10)

	_volume_slider = HSlider.new()
	_volume_slider.min_value = 0.0
	_volume_slider.max_value = 100.0
	_volume_slider.value = 80.0
	_volume_slider.step = 1.0
	_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume_slider.custom_minimum_size.y = 30
	_volume_slider.value_changed.connect(_on_volume_changed)
	vol_hbox.add_child(_volume_slider)

	_volume_label = _create_label("80%", 14, _font_color)
	_volume_label.custom_minimum_size.x = 45
	vol_hbox.add_child(_volume_label)

	vbox.add_child(vol_hbox)

	# Полноэкранный режим
	_fullscreen_toggle = CheckButton.new()
	_fullscreen_toggle.text = "🖥️ Полный экран"
	_fullscreen_toggle.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	_fullscreen_toggle.add_theme_font_size_override("font_size", 16)
	_fullscreen_toggle.add_theme_color_override("font_color", Color(0.7, 0.75, 0.9))
	_fullscreen_toggle.add_theme_color_override("font_pressed_color", Color(0.2, 1.0, 0.4))
	_fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)
	vbox.add_child(_fullscreen_toggle)

	var sep_q := HSeparator.new()
	sep_q.add_theme_color_override("separator", Color(0.4, 0.8, 1.0).darkened(0.5))
	vbox.add_child(sep_q)

	# Качество графики
	var q_hbox := HBoxContainer.new()
	q_hbox.add_child(_create_label("🎨 Качество:", 16, Color(0.7, 0.75, 0.9)))
	
	_quality_option = OptionButton.new()
	_quality_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quality_option.add_item("Низкое (Intel HD)")
	_quality_option.add_item("Среднее")
	_quality_option.add_item("Ультра")
	_quality_option.select(current_quality)
	_quality_option.item_selected.connect(_on_quality_selected)
	q_hbox.add_child(_quality_option)
	vbox.add_child(q_hbox)

	var sep2 := HSeparator.new()
	sep2.add_theme_color_override("separator", Color(0.4, 0.8, 1.0).darkened(0.5))
	vbox.add_child(sep2)

	# Разрешение экрана
	var res_hbox := HBoxContainer.new()
	res_hbox.add_child(_create_label("🖥️ Разрешение:", 16, Color(0.7, 0.75, 0.9)))
	
	_resolution_option = OptionButton.new()
	_resolution_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resolution_option.add_item("1280x720")
	_resolution_option.add_item("1600x900")
	_resolution_option.add_item("1920x1080")
	_resolution_option.add_item("2560x1440")
	_resolution_option.add_item("Full Screen")
	_resolution_option.select(2) # Default 1920x1080
	_resolution_option.item_selected.connect(_on_resolution_selected)
	res_hbox.add_child(_resolution_option)
	vbox.add_child(res_hbox)

	var sep3 := HSeparator.new()
	sep3.add_theme_color_override("separator", Color(0.4, 0.8, 1.0).darkened(0.5))
	vbox.add_child(sep3)

	# Кнопка назад
	_settings_back_btn = _create_styled_button("🔙  Назад", Color(0.4, 0.8, 1.0))
	_settings_back_btn.pressed.connect(_on_settings_back_pressed)
	vbox.add_child(_settings_back_btn)

	_settings_panel.visible = false
	_pause_overlay.add_child(_settings_panel)


# ==============================================================================
# Управление видимостью экранов
# ==============================================================================

func _show_lobby() -> void:
	_lobby_panel.visible = true
	_game_panel.visible = false
	_win_panel.visible = false
	_quiz_results_panel.visible = false
	_history_panel.visible = false
	_analytics_panel.visible = false
	_study_plan_panel.visible = false
	_hide_pause_menu()
	_set_spectator_mode(false)
	_spectator_btn.visible = false
	# Начинаем слушать LAN-серверы
	LANDiscovery.start_listening()


func _show_game() -> void:
	_lobby_panel.visible = false
	_game_panel.visible = true
	_win_panel.visible = false
	_quiz_results_panel.visible = false
	_history_panel.visible = false
	_analytics_panel.visible = false
	_study_plan_panel.visible = false
	_hide_pause_menu()

	# Переключаем ввод в зависимости от режима
	if GameManager.quiz_mode:
		# Расширяем панель для длинных вопросов викторины
		_game_panel.anchor_top = 0.35
		_word_input_container.visible = false
		_quiz_input_container.visible = true
		_quiz_answer_edit.text = ""
		_quiz_answer_edit.editable = true
		_quiz_answer_edit.grab_focus()
		_quiz_submit_btn.disabled = false
	else:
		_game_panel.anchor_top = 0.65
		_word_input_container.visible = true
		_quiz_input_container.visible = false
		_answer_input.text = ""
		_answer_input.editable = true
		_submit_btn.disabled = false
		_answer_input.grab_focus()

	_update_height_display()
	# Останавливаем слушание LAN
	LANDiscovery.stop_listening()

	# Показываем кнопку наблюдения
	_spectator_btn.visible = true
	_set_spectator_mode(false)

	# Очищаем лог ответов
	for child in _answer_log.get_children():
		child.queue_free()


func _show_win(winner_nickname: String) -> void:
	_lobby_panel.visible = false
	_game_panel.visible = false
	_win_panel.visible = true
	_winner_label.text = "🏆 %s победил!" % winner_nickname
	_update_scores_display()


# ==============================================================================
# Обработчики кнопок
# ==============================================================================

func _on_create_pressed() -> void:
	var nickname := _nickname_input.text.strip_edges()
	if nickname == "":
		nickname = "Хост"
	NetworkManager.local_player_info["nickname"] = nickname


	var port := int(_port_input.text) if _port_input.text.is_valid_int() else NetworkManager.DEFAULT_PORT
	var error := NetworkManager.create_server(port)
	if error != OK:
		_lobby_status.text = "❌ Не удалось создать сервер"
		_lobby_status.add_theme_color_override("font_color", Color.RED)
	else:
		_lobby_status.text = "✅ Сервер создан! Ожидание игроков..."
		_lobby_status.add_theme_color_override("font_color", Color.GREEN)
		_create_btn.disabled = true
		_join_btn.disabled = true

		# Показываем код комнаты
		_room_code_label.text = "🔑 Код комнаты: %s" % NetworkManager.room_code
		_room_code_label.visible = true


func _on_join_pressed() -> void:
	var nickname := _nickname_input.text.strip_edges()
	if nickname == "":
		nickname = "Игрок"
	NetworkManager.local_player_info["nickname"] = nickname

	var ip := _ip_input.text.strip_edges()
	var port := int(_port_input.text) if _port_input.text.is_valid_int() else NetworkManager.DEFAULT_PORT

	var error := NetworkManager.join_server(ip, port)
	if error != OK:
		_lobby_status.text = "❌ Не удалось подключиться"
		_lobby_status.add_theme_color_override("font_color", Color.RED)
	else:
		_lobby_status.text = "⏳ Подключение к %s:%d..." % [ip, port]
		_lobby_status.add_theme_color_override("font_color", Color.YELLOW)
		_create_btn.disabled = true
		_join_btn.disabled = true


func _on_join_by_code() -> void:
	var code := _room_code_input.text.strip_edges().to_upper()
	if code.length() < 6:
		_lobby_status.text = "❌ Код должен состоять из 6 символов"
		_lobby_status.add_theme_color_override("font_color", Color.RED)
		return

	var nickname := _nickname_input.text.strip_edges()
	if nickname == "":
		nickname = "Ученик"
	NetworkManager.local_player_info["nickname"] = nickname

	_lobby_status.text = "⏳ Поиск комнаты '%s'..." % code
	_lobby_status.add_theme_color_override("font_color", Color.YELLOW)

	var error := NetworkManager.join_by_code(code)
	if error != OK:
		_lobby_status.text = "❌ Комната не найдена или ошибка подключения"
		_lobby_status.add_theme_color_override("font_color", Color.RED)
	else:
		_create_btn.disabled = true
		_join_btn.disabled = true
		_join_code_btn.disabled = true



func _on_question_mode_toggled(enabled: bool) -> void:
	GameManager.set_question_mode(enabled)
	# Меняем текст переключателя
	if enabled:
		_question_mode_toggle.text = "🤖 Вопросы от ИИ"
	else:
		_question_mode_toggle.text = "📋 Обычные вопросы"


func _on_quiz_mode_toggled(enabled: bool) -> void:
	GameManager.quiz_mode = enabled
	_quiz_settings_container.visible = enabled
	_word_race_settings_container.visible = not enabled
	if enabled:
		_quiz_mode_toggle.text = "🏫 Режим: Викторина"
	else:
		_quiz_mode_toggle.text = "🏫 Режим: Гонка слов"


func _on_spectator_toggled() -> void:
	_set_spectator_mode(not _is_spectating)


func _set_spectator_mode(enabled: bool) -> void:
	_is_spectating = enabled
	# Показываем/скрываем панель только если мы в игре (не в лобби)
	var in_game := GameManager.current_state == GameManager.GameState.PLAYING or GameManager.current_state == GameManager.GameState.LOADING
	if in_game:
		_game_panel.visible = not enabled
	_spectator_hint.visible = enabled

	if enabled:
		_spectator_btn.text = "❌ Вернуться"
	else:
		_spectator_btn.text = "👁 Наблюдение"

	# Находим локального игрока и переключаем режим камеры
	var main_node = get_tree().root.get_node_or_null("Main/Players")
	if main_node:
		var my_id := multiplayer.get_unique_id()
		var player_node = main_node.get_node_or_null("Player_%d" % my_id)
		if player_node and "spectator_mode" in player_node:
			player_node.spectator_mode = enabled


func _on_start_pressed() -> void:
	var topic := _topic_input.text.strip_edges()

	if GameManager.quiz_mode:
		# Настройки викторины
		var time_values := [30.0, 60.0, 90.0, 120.0]
		var round_values := [3, 5, 7, 10]
		GameManager.quiz_round_time = time_values[_quiz_time_option.selected]
		GameManager.quiz_total_rounds = round_values[_quiz_rounds_option.selected]
		GameManager.start_game(topic, 0.0)
	else:
		var points := float(_points_input.text.strip_edges())
		if points <= 0:
			points = 300.0
		GameManager.start_game(topic, points)


func _on_answer_submitted(text: String) -> void:
	var word := text.strip_edges()
	if word == "":
		return
	# ВАЖНО: сначала блокируем ввод, потом отправляем
	# send_answer() для хоста выполняется СИНХРОННО,
	# и если ответ неверный — обработчик _on_answer_invalid РАЗБЛОКИРУЕТ ввод
	_answer_input.text = ""
	_answer_input.editable = false
	_submit_btn.disabled = true
	_validation_label.text = ""
	GameManager.send_answer(word)


func _on_lobby_return_pressed() -> void:
	GameManager.return_to_lobby()


# ==============================================================================
# Обработчики меню паузы
# ==============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		# Esc работает только во время игры (PLAYING / LOADING)
		if GameManager.current_state == GameManager.GameState.PLAYING or GameManager.current_state == GameManager.GameState.LOADING:
			if _settings_visible:
				_on_settings_back_pressed()
			elif _is_paused:
				_hide_pause_menu()
			else:
				_show_pause_menu()
			get_viewport().set_input_as_handled()


func _show_pause_menu() -> void:
	_is_paused = true
	_pause_overlay.visible = true
	_pause_panel.visible = true
	_settings_panel.visible = false
	_settings_visible = false
	_resume_btn.grab_focus()


func _hide_pause_menu() -> void:
	_is_paused = false
	_settings_visible = false
	_pause_overlay.visible = false
	_pause_panel.visible = false
	_settings_panel.visible = false
	# Возвращаем фокус на ввод ответа если игра идёт
	if GameManager.current_state == GameManager.GameState.PLAYING:
		if _answer_input and _answer_input.editable:
			_answer_input.grab_focus()


func _on_resume_pressed() -> void:
	_hide_pause_menu()


func _on_settings_pressed() -> void:
	_settings_visible = true
	_settings_panel.visible = true
	_pause_overlay.visible = true # Показываем фон
	
	if GameManager.current_state == GameManager.GameState.LOBBY:
		_lobby_panel.visible = false
	else:
		_pause_panel.visible = false


func _on_settings_back_pressed() -> void:
	_settings_panel.visible = false
	_settings_visible = false
	
	if GameManager.current_state == GameManager.GameState.LOBBY:
		_lobby_panel.visible = true
		_pause_overlay.visible = false
	else:
		_pause_panel.visible = true
		_is_paused = true



func _on_exit_to_lobby_pressed() -> void:
	_hide_pause_menu()
	if multiplayer.is_server():
		# Хост — вернуть всех в лобби
		GameManager.return_to_lobby()
	else:
		# Клиент — отключиться от сервера
		NetworkManager.disconnect_from_server()
		GameManager.current_state = GameManager.GameState.LOBBY
		GameManager.state_changed.emit(GameManager.GameState.LOBBY)





# ==============================================================================
# Обработчики сигналов
# ==============================================================================

func _on_server_created() -> void:
	_start_btn.visible = true


func _on_connection_succeeded() -> void:
	_lobby_status.text = "✅ Подключено!"
	_lobby_status.add_theme_color_override("font_color", Color.GREEN)


func _on_connection_failed() -> void:
	_lobby_status.text = "❌ Не удалось подключиться к серверу"
	_lobby_status.add_theme_color_override("font_color", Color.RED)
	_create_btn.disabled = false
	_join_btn.disabled = false
	_join_code_btn.disabled = false
	_room_code_label.visible = false
	_room_code_label.text = ""

## Обновление списка LAN-серверов
func _on_server_list_updated(server_list: Dictionary) -> void:
	# Очищаем контейнер
	for child in _servers_container.get_children():
		child.queue_free()

	if server_list.is_empty():
		_no_servers_label = _create_label("Нет серверов. Создайте свой или введите IP.", 13, Color(0.5, 0.5, 0.6))
		_no_servers_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_no_servers_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		_servers_container.add_child(_no_servers_label)
		return

	for key in server_list:
		var info: Dictionary = server_list[key]
		var ip: String = info.get("ip", "?")
		var port: int = info.get("port", 9876)
		var nick: String = info.get("nickname", "Сервер")
		var players_count: int = info.get("players", 1)
		var max_p: int = info.get("max_players", 5)
		var mode_str: String = "🤖" if info.get("mode", "normal") == "ai" else "📋"

		var btn_text := "%s 🖥 %s (%d/%d) — %s:%d" % [mode_str, nick, players_count, max_p, ip, port]
		var code_str: String = info.get("room_code", "")
		if code_str != "":
			btn_text = "%s 🖥 %s [🔑%s] (%d/%d)" % [mode_str, nick, code_str, players_count, max_p]
		var server_btn := _create_styled_button(btn_text, Color(0.3, 0.7, 1.0))
		server_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# Замыкание для захвата ip и port
		var captured_ip := ip
		var captured_port := port
		server_btn.pressed.connect(func():
			_on_server_button_pressed(captured_ip, captured_port)
		)
		_servers_container.add_child(server_btn)


## Нажатие на сервер в списке — автоподключение
func _on_server_button_pressed(ip: String, port: int) -> void:
	_ip_input.text = ip
	_port_input.text = str(port)
	# Запускаем подключение
	_on_join_pressed()


func _on_lobby_updated(players: Dictionary) -> void:
	# Обновляем список игроков в лобби
	for child in _players_list.get_children():
		child.queue_free()

	for peer_id in players:
		var info: Dictionary = players[peer_id]
		var color: Color = info.get("color", Color.WHITE)
		var nick: String = info.get("nickname", "Игрок")
		var is_host := " (Хост)" if peer_id == 1 else ""

		var lbl := _create_label("● %s%s" % [nick, is_host], 16, color)
		_players_list.add_child(lbl)


func _on_state_changed(new_state: GameManager.GameState) -> void:
	match new_state:
		GameManager.GameState.LOBBY:
			_show_lobby()
		GameManager.GameState.LOADING:
			# Показываем игровой экран с сообщением загрузки
			_show_game()
			_question_label.text = "⏳ Загрузка вопросов..."
			_answer_input.editable = false
			_submit_btn.disabled = true
		GameManager.GameState.PLAYING:
			_show_game()
		GameManager.GameState.GAME_OVER:
			pass  # Победу обрабатываем в _on_player_won


func _on_question_received(question: String) -> void:
	_question_label.text = "❓ " + question
	_answer_input.editable = true
	_answer_input.text = ""
	_answer_input.grab_focus()
	_submit_btn.disabled = false
	_validation_label.text = ""


func _on_round_changed(round_num: int) -> void:
	if GameManager.quiz_mode:
		_round_label.text = "Раунд %d / %d" % [round_num, GameManager.quiz_total_rounds]
	else:
		_round_label.text = "Раунд %d — Финиш: %.0f очков" % [round_num, GameManager.finish_height]


func _on_player_answered(peer_id: int, word: String, new_height: float) -> void:
	# Добавляем в лог
	var info: Dictionary = NetworkManager.players.get(peer_id, {})
	var nick: String = info.get("nickname", "Игрок")
	var color: Color = info.get("color", Color.WHITE)

	var log_lbl := _create_label(
		"%s: \"%s\" (+%d → %.0f очков)" % [nick, word, word.length() * GameManager.DISTANCE_COEFF, new_height],
		13, color
	)
	_answer_log.add_child(log_lbl)

	# Обновляем прогресс
	_update_height_display()


func _on_player_won(_peer_id: int, nickname: String) -> void:
	_show_win(nickname)


func _on_answer_rejected(reason: String) -> void:
	_validation_label.text = "⚠️ " + reason
	_validation_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	_answer_input.editable = true
	_submit_btn.disabled = false


func _on_answer_accepted(word: String) -> void:
	_validation_label.text = "✅ Ответ \"%s\" принят! Ждём..." % word
	_validation_label.add_theme_color_override("font_color", Color.GREEN)
	_answer_input.editable = false
	_submit_btn.disabled = true


func _on_answer_checking(peer_id: int) -> void:
	if peer_id == multiplayer.get_unique_id():
		_validation_label.text = "⏳ Проверяю (ИИ)..."
		_validation_label.add_theme_color_override("font_color", Color.YELLOW)
		_answer_input.editable = false
		_submit_btn.disabled = true


func _on_timer_updated(seconds_left: int) -> void:
	_timer_label.text = "⏱ %d" % seconds_left
	# Цвет: зелёный → жёлтый → красный
	if seconds_left > 10:
		_timer_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
	elif seconds_left > 5:
		_timer_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.0))
	else:
		_timer_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))


func _on_loading_status(message: String) -> void:
	_question_label.text = message
	_validation_label.text = ""


func _on_answer_invalid(peer_id: int, word: String, reason: String) -> void:
	var info: Dictionary = NetworkManager.players.get(peer_id, {})
	var nick: String = info.get("nickname", "Игрок")
	var color: Color = info.get("color", Color.WHITE)

	# Показываем в логе
	var log_lbl := _create_label(
		"❌ %s: \"%s\" — %s" % [nick, word, reason],
		13, color.darkened(0.3)
	)
	_answer_log.add_child(log_lbl)

	# Если это наш ответ — разрешаем повторный ввод
	if peer_id == multiplayer.get_unique_id():
		_validation_label.text = "❌ %s" % reason
		_validation_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		_answer_input.editable = true
		_answer_input.text = ""
		_answer_input.grab_focus()
		_submit_btn.disabled = false


## Обновить отображение высот всех игроков
func _update_height_display() -> void:
	for child in _height_info.get_children():
		child.queue_free()

	# Сортируем по высоте (убывание)
	var sorted_players: Array = []
	for peer_id in NetworkManager.players:
		var info: Dictionary = NetworkManager.players[peer_id]
		sorted_players.append({"peer_id": peer_id, "info": info})

	sorted_players.sort_custom(func(a, b):
		return a["info"].get("height", 0.0) > b["info"].get("height", 0.0)
	)

	for entry in sorted_players:
		var info: Dictionary = entry["info"]
		var height: float = info.get("height", 0.0)
		var nick: String = info.get("nickname", "Игрок")
		var color: Color = info.get("color", Color.WHITE)

		var lbl: Label
		if GameManager.quiz_mode:
			var max_score: float = GameManager.quiz_total_rounds * 10.0
			lbl = _create_label(
				"● %s: %.0f / %.0f баллов" % [nick, height, max_score],
				14, color
			)
		else:
			var progress: float = clampf(height / GameManager.finish_height, 0.0, 1.0) * 100.0
			lbl = _create_label(
				"● %s: %.0f / %.0f очков (%.0f%%)" % [nick, height, GameManager.finish_height, progress],
				14, color
			)
		_height_info.add_child(lbl)


## Обновить таблицу результатов на экране победы
func _update_scores_display() -> void:
	for child in _scores_list.get_children():
		child.queue_free()

	var sorted_players: Array = []
	for peer_id in NetworkManager.players:
		var info: Dictionary = NetworkManager.players[peer_id]
		sorted_players.append(info)

	sorted_players.sort_custom(func(a, b):
		return a.get("height", 0.0) > b.get("height", 0.0)
	)

	var place := 1
	for info in sorted_players:
		var nick: String = info.get("nickname", "Игрок")
		var height: float = info.get("height", 0.0)
		var color: Color = info.get("color", Color.WHITE)
		var medal := "🥇" if place == 1 else ("🥈" if place == 2 else "🥉" if place == 3 else "  ")

		var score_text: String
		if GameManager.quiz_mode:
			score_text = "%s %d. %s — %.0f баллов" % [medal, place, nick, height]
		else:
			score_text = "%s %d. %s — %.1f м" % [medal, place, nick, height]

		var lbl := _create_label(score_text, 18, color)
		_scores_list.add_child(lbl)
		place += 1


# ==============================================================================
# Панель результатов викторины
# ==============================================================================

func _create_quiz_results_panel() -> void:
	_quiz_results_panel = PanelContainer.new()
	_quiz_results_panel.name = "QuizResultsPanel"
	var style := _create_panel_style()
	_quiz_results_panel.add_theme_stylebox_override("panel", style)
	_quiz_results_panel.set_anchors_preset(Control.PRESET_CENTER)
	_quiz_results_panel.custom_minimum_size = Vector2(500, 400)
	_quiz_results_panel.position = Vector2(-250, -200)
	_quiz_results_panel.visible = false

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_quiz_results_panel.add_child(scroll)

	_quiz_results_vbox = VBoxContainer.new()
	_quiz_results_vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(_quiz_results_vbox)

	add_child(_quiz_results_panel)


# ==============================================================================
# Панель истории студента
# ==============================================================================

func _create_history_panel() -> void:
	_history_panel = PanelContainer.new()
	_history_panel.name = "HistoryPanel"
	var style := _create_panel_style()
	_history_panel.add_theme_stylebox_override("panel", style)
	_history_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_history_panel.set_anchor_and_offset(SIDE_LEFT, 0.1, 0)
	_history_panel.set_anchor_and_offset(SIDE_RIGHT, 0.9, 0)
	_history_panel.set_anchor_and_offset(SIDE_TOP, 0.05, 0)
	_history_panel.set_anchor_and_offset(SIDE_BOTTOM, 0.95, 0)
	_history_panel.visible = false

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	_history_panel.add_child(main_vbox)

	# Заголовок + кнопка назад
	var header := HBoxContainer.new()
	header.add_child(_create_label("📊 Моя история", 22, _accent_color))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var back_btn := _create_styled_button("🔙 Назад", Color(0.4, 0.8, 1.0))
	back_btn.pressed.connect(func(): _history_panel.visible = false; _lobby_panel.visible = true)
	header.add_child(back_btn)
	main_vbox.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(scroll)

	_history_vbox = VBoxContainer.new()
	_history_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(_history_vbox)

	add_child(_history_panel)


# ==============================================================================
# Панель аналитики преподавателя
# ==============================================================================

func _create_analytics_panel() -> void:
	_analytics_panel = PanelContainer.new()
	_analytics_panel.name = "AnalyticsPanel"
	var style := _create_panel_style()
	_analytics_panel.add_theme_stylebox_override("panel", style)
	_analytics_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_analytics_panel.set_anchor_and_offset(SIDE_LEFT, 0.1, 0)
	_analytics_panel.set_anchor_and_offset(SIDE_RIGHT, 0.9, 0)
	_analytics_panel.set_anchor_and_offset(SIDE_TOP, 0.05, 0)
	_analytics_panel.set_anchor_and_offset(SIDE_BOTTOM, 0.95, 0)
	_analytics_panel.visible = false

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	_analytics_panel.add_child(main_vbox)

	var header := HBoxContainer.new()
	header.add_child(_create_label("📊 Аналитика", 22, _accent_color))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var back_btn := _create_styled_button("🔙 Назад", Color(0.4, 0.8, 1.0))
	back_btn.pressed.connect(func(): _analytics_panel.visible = false; _lobby_panel.visible = true)
	header.add_child(back_btn)
	main_vbox.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(scroll)

	_analytics_vbox = VBoxContainer.new()
	_analytics_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(_analytics_vbox)

	add_child(_analytics_panel)


# ==============================================================================
# Обработчики викторины
# ==============================================================================

func _on_quiz_text_changed() -> void:
	var length := _quiz_answer_edit.text.length()
	_quiz_char_count.text = "%d / 1000" % length
	if length > 900:
		_quiz_char_count.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	else:
		_quiz_char_count.add_theme_color_override("font_color", Color(0.5, 0.55, 0.7))


func _on_quiz_submit_pressed() -> void:
	var text := _quiz_answer_edit.text.strip_edges()
	if text == "":
		return
	_quiz_answer_edit.editable = false
	_quiz_submit_btn.disabled = true
	_validation_label.text = "✉️ Отправляю ответ..."
	_validation_label.add_theme_color_override("font_color", Color.YELLOW)
	GameManager.send_quiz_answer(text)


func _on_quiz_question_received(question: String) -> void:
	_question_label.text = "❓ " + question
	_quiz_answer_edit.text = ""
	_quiz_answer_edit.editable = true
	_quiz_answer_edit.grab_focus()
	_quiz_submit_btn.disabled = false
	_validation_label.text = ""
	_quiz_char_count.text = "0 / 1000"


func _on_quiz_answer_accepted() -> void:
	_validation_label.text = "✅ Ответ принят! Ждём остальных..."
	_validation_label.add_theme_color_override("font_color", Color.GREEN)
	_quiz_answer_edit.editable = false
	_quiz_submit_btn.disabled = true


func _on_quiz_evaluating() -> void:
	_validation_label.text = "🤖 ИИ оценивает ответы..."
	_validation_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.2))


func _on_quiz_results_received(results: Dictionary) -> void:
	# Показываем результаты в логе ответов
	for peer_id in results:
		var data: Dictionary = results[peer_id]
		var info: Dictionary = NetworkManager.players.get(peer_id, {})
		var nick: String = info.get("nickname", "Студент")
		var color: Color = info.get("color", Color.WHITE)
		var score: int = data.get("score", 0)
		var feedback: String = data.get("feedback", "")

		# Звезды для оценки
		var stars := ""
		for i in range(score):
			stars += "⭐"
		for i in range(10 - score):
			stars += "☆"

		var log_lbl := _create_label(
			"%s: %s (%d/10)" % [nick, stars, score],
			14, color
		)
		_answer_log.add_child(log_lbl)

		if feedback != "":
			var fb_lbl := _create_label("   ↳ %s" % feedback, 12, color.darkened(0.2))
			fb_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			_answer_log.add_child(fb_lbl)

	# Показать свой детальный фидбэк
	var my_id := multiplayer.get_unique_id()
	if results.has(my_id):
		var my_data: Dictionary = results[my_id]
		var score: int = my_data.get("score", 0)
		var explanation: String = my_data.get("explanation", "")
		var correct_answer: String = my_data.get("correct_answer", "")
		var topics_to_review: Array = my_data.get("topics_to_review", [])

		# Основная оценка
		var val_text := "📝 Ваша оценка: %d/10" % score
		if score >= 8:
			_validation_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
		elif score >= 5:
			_validation_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.0))
		else:
			_validation_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		_validation_label.text = val_text

		# Объяснение ошибки
		if explanation != "":
			var expl_lbl := _create_label("📕 Разбор ошибок: %s" % explanation, 12, Color(1.0, 0.7, 0.5))
			expl_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			_answer_log.add_child(expl_lbl)

		# Правильный ответ
		if correct_answer != "":
			var ca_lbl := _create_label("✅ Правильный ответ: %s" % correct_answer, 12, Color(0.5, 1.0, 0.7))
			ca_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			_answer_log.add_child(ca_lbl)

		# Темы для повторения
		if not topics_to_review.is_empty():
			var topics_str := ", ".join(topics_to_review)
			var tr_lbl := _create_label("📚 Повторить: %s" % topics_str, 12, Color(0.8, 0.6, 1.0))
			tr_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			_answer_log.add_child(tr_lbl)

		# Разделитель
		var sep := HSeparator.new()
		sep.add_theme_color_override("separator", Color(0.2, 0.25, 0.4))
		_answer_log.add_child(sep)

	_update_height_display()


func _on_quiz_game_finished(final_data: Dictionary) -> void:
	# Обновляем отображение
	_update_height_display()

	# Показываем панель с подробными результатами
	_show_quiz_final_results(final_data)


# ==============================================================================
# Кнопка истории
# ==============================================================================

func _on_history_pressed() -> void:
	_lobby_panel.visible = false
	_history_panel.visible = true
	_populate_history()


func _populate_history() -> void:
	for child in _history_vbox.get_children():
		child.queue_free()

	var history := StudentHistory.get_recent(30)
	if history.is_empty():
		_history_vbox.add_child(_create_label("📋 История пуста. Сыграйте в викторину!", 16, Color(0.5, 0.55, 0.7)))
		return

	# Кнопки действий
	var btn_hbox := HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 10)

	var export_btn := _create_styled_button("📥 Экспорт в файл", Color(0.4, 0.8, 0.4))
	export_btn.pressed.connect(_on_export_history_pressed)
	btn_hbox.add_child(export_btn)

	var study_btn := _create_styled_button("🧠 План изучения", Color(0.8, 0.6, 1.0))
	study_btn.pressed.connect(_on_study_plan_pressed)
	btn_hbox.add_child(study_btn)

	_history_vbox.add_child(btn_hbox)

	var sep_top := HSeparator.new()
	sep_top.add_theme_color_override("separator", _accent_color.darkened(0.5))
	_history_vbox.add_child(sep_top)

	# Рекомендации
	var recs := StudentHistory.get_recommendations()
	if not recs.is_empty():
		_history_vbox.add_child(_create_label("💡 Рекомендации:", 16, _accent_color))
		for r in recs:
			var r_lbl := _create_label("  " + r, 13, Color(0.7, 0.75, 0.9))
			r_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			_history_vbox.add_child(r_lbl)

		var sep := HSeparator.new()
		sep.add_theme_color_override("separator", _accent_color.darkened(0.5))
		_history_vbox.add_child(sep)

	# Слабые зоны
	var weak_zones := StudentHistory.get_weak_zones(5)
	if not weak_zones.is_empty():
		_history_vbox.add_child(_create_label("⚠️ Слабые зоны:", 16, Color(1.0, 0.7, 0.3)))
		for zone in weak_zones:
			_history_vbox.add_child(_create_label(
				"  • %s (встречается %d раз)" % [zone["zone"], zone["count"]],
				13, Color(1.0, 0.8, 0.5)
			))

		var sep2 := HSeparator.new()
		sep2.add_theme_color_override("separator", _accent_color.darkened(0.5))
		_history_vbox.add_child(sep2)

	# Темы для повторения
	var review_topics := StudentHistory.get_topics_to_review(5)
	if not review_topics.is_empty():
		_history_vbox.add_child(_create_label("📚 Темы для повторения:", 16, Color(0.8, 0.6, 1.0)))
		for t in review_topics:
			_history_vbox.add_child(_create_label(
				"  • %s (рекомендовано %d раз)" % [t["topic"], t["count"]],
				13, Color(0.7, 0.6, 0.9)
			))

		var sep3 := HSeparator.new()
		sep3.add_theme_color_override("separator", _accent_color.darkened(0.5))
		_history_vbox.add_child(sep3)

	# Динамика результатов
	var dynamics := StudentHistory.get_results_dynamics()
	if dynamics.size() >= 2:
		_history_vbox.add_child(_create_label("📈 Динамика результатов:", 16, _accent_color))
		for d in dynamics:
			var bar := ""
			var filled := int(d["avg_score"])
			for _i in range(filled):
				bar += "█"
			for _i in range(10 - filled):
				bar += "░"
			_history_vbox.add_child(_create_label(
				"  %s: %s %.1f/10 (%d ответов)" % [d["date"], bar, d["avg_score"], d["count"]],
				12, Color(0.6, 0.8, 1.0)
			))

		var sep4 := HSeparator.new()
		sep4.add_theme_color_override("separator", _accent_color.darkened(0.5))
		_history_vbox.add_child(sep4)

	# Последние ответы
	_history_vbox.add_child(_create_label("📝 Последние ответы:", 16, _accent_color))
	for i in range(history.size() - 1, -1, -1):
		var entry: Dictionary = history[i]
		var score: int = entry.get("score", 0)
		var topic: String = entry.get("topic", "?")
		var question: String = entry.get("question", "?")
		var date: String = entry.get("date", "").left(16)
		var feedback: String = entry.get("feedback", "")
		var explanation: String = entry.get("explanation", "")
		var correct_answer: String = entry.get("correct_answer", "")

		var score_color := Color(0.2, 1.0, 0.4) if score >= 8 else (Color(1.0, 0.8, 0.0) if score >= 5 else Color(1.0, 0.3, 0.3))
		_history_vbox.add_child(_create_label(
			"%s | %s | %d/10" % [date, topic, score],
			14, score_color
		))
		_history_vbox.add_child(_create_label("  ❓ %s" % question, 12, Color(0.6, 0.65, 0.8)))
		if correct_answer != "":
			var ca_lbl := _create_label("  ✅ Правильный ответ: %s" % correct_answer, 12, Color(0.5, 1.0, 0.7))
			ca_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			_history_vbox.add_child(ca_lbl)
		if explanation != "":
			var e_lbl := _create_label("  📕 %s" % explanation, 12, Color(1.0, 0.7, 0.5))
			e_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			_history_vbox.add_child(e_lbl)
		if feedback != "":
			_history_vbox.add_child(_create_label("  💬 %s" % feedback, 12, Color(0.5, 0.55, 0.7)))


# ==============================================================================
# Экспорт результатов
# ==============================================================================

func _on_export_history_pressed() -> void:
	_show_export_dialog()


# ==============================================================================
# План изучения
# ==============================================================================

func _create_study_plan_panel() -> void:
	_study_plan_panel = PanelContainer.new()
	_study_plan_panel.name = "StudyPlanPanel"
	var style := _create_panel_style()
	_study_plan_panel.add_theme_stylebox_override("panel", style)
	_study_plan_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_study_plan_panel.set_anchor_and_offset(SIDE_LEFT, 0.1, 0)
	_study_plan_panel.set_anchor_and_offset(SIDE_RIGHT, 0.9, 0)
	_study_plan_panel.set_anchor_and_offset(SIDE_TOP, 0.05, 0)
	_study_plan_panel.set_anchor_and_offset(SIDE_BOTTOM, 0.95, 0)
	_study_plan_panel.visible = false

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	_study_plan_panel.add_child(main_vbox)

	var header := HBoxContainer.new()
	header.add_child(_create_label("🧠 План изучения", 22, _accent_color))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var export_btn := _create_styled_button("📥 Экспорт плана", Color(0.4, 0.8, 0.4))
	export_btn.pressed.connect(func():
		_show_export_dialog(ExportMode.STUDY_PLAN)
	)
	header.add_child(export_btn)

	var back_btn := _create_styled_button("🔙 Назад", Color(0.4, 0.8, 1.0))
	back_btn.pressed.connect(func():
		_study_plan_panel.visible = false
		_history_panel.visible = true
	)
	header.add_child(back_btn)
	main_vbox.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(scroll)

	_study_plan_vbox = VBoxContainer.new()
	_study_plan_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(_study_plan_vbox)

	add_child(_study_plan_panel)


func _on_study_plan_pressed() -> void:
	_history_panel.visible = false
	_study_plan_panel.visible = true

	for child in _study_plan_vbox.get_children():
		child.queue_free()

	_study_plan_vbox.add_child(_create_label("⏳ ИИ генерирует персональный план изучения...", 16, Color(1.0, 0.8, 0.2)))

	# Получаем данные для плана
	var plan_data := StudentHistory.get_study_plan_data()

	# Получаем ссылку на GeminiAPI
	var api := _get_gemini_api()
	if api == null:
		_study_plan_vbox.add_child(_create_label("❌ Ошибка: GeminiAPI не найден", 14, Color.RED))
		return

	# Подключаем сигнал
	if not api.study_plan_ready.is_connected(_on_study_plan_received):
		api.study_plan_ready.connect(_on_study_plan_received)

	api.generate_study_plan(plan_data["weak_zones"], plan_data["weak_topics"], plan_data["recent_mistakes"])


func _on_study_plan_received(plan: Dictionary) -> void:
	_current_study_plan = plan
	for child in _study_plan_vbox.get_children():
		child.queue_free()

	var summary: String = plan.get("summary", "")
	if summary != "":
		var sum_lbl := _create_label("📋 %s" % summary, 15, Color(0.8, 0.9, 1.0))
		sum_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		_study_plan_vbox.add_child(sum_lbl)

		var sep := HSeparator.new()
		sep.add_theme_color_override("separator", _accent_color.darkened(0.5))
		_study_plan_vbox.add_child(sep)

	var plan_items: Array = plan.get("plan", [])
	if plan_items.is_empty():
		_study_plan_vbox.add_child(_create_label("📚 Недостаточно данных для формирования плана. Пройдите ещё несколько викторин!", 14, Color(0.6, 0.65, 0.8)))
		return

	var idx := 1
	for item in plan_items:
		if item is Dictionary:
			var topic_str: String = str(item.get("topic", "Тема %d" % idx))
			var desc_str: String = str(item.get("description", ""))
			var exercise_str: String = str(item.get("exercise", ""))

			_study_plan_vbox.add_child(_create_label("📖 %d. %s" % [idx, topic_str], 16, _accent_color))

			if desc_str != "":
				var d_lbl := _create_label("   📝 %s" % desc_str, 13, Color(0.7, 0.8, 0.9))
				d_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
				_study_plan_vbox.add_child(d_lbl)

			if exercise_str != "":
				var e_lbl := _create_label("   🎯 Задание: %s" % exercise_str, 13, Color(0.9, 0.8, 0.5))
				e_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
				_study_plan_vbox.add_child(e_lbl)

			var item_sep := HSeparator.new()
			item_sep.add_theme_color_override("separator", Color(0.15, 0.2, 0.35))
			_study_plan_vbox.add_child(item_sep)
			idx += 1


# ==============================================================================
# Финальные результаты викторины
# ==============================================================================

func _show_quiz_final_results(final_data: Dictionary) -> void:
	# Очищаем панель результатов
	for child in _quiz_results_vbox.get_children():
		child.queue_free()

	_quiz_results_vbox.add_child(_create_label("🏆 Результаты викторины", 20, _accent_color))

	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", _accent_color.darkened(0.5))
	_quiz_results_vbox.add_child(sep)

	# Таблица результатов
	var sorted_players: Array = []
	for peer_id in final_data:
		var data: Dictionary = final_data[peer_id]
		sorted_players.append({"peer_id": peer_id, "data": data})

	sorted_players.sort_custom(func(a, b):
		return a["data"].get("total_score", 0) > b["data"].get("total_score", 0)
	)

	var place := 1
	for entry in sorted_players:
		var data: Dictionary = entry["data"]
		var nick: String = data.get("nickname", "Студент")
		var total: int = data.get("total_score", 0)
		var max_possible: int = data.get("max_possible", 50)
		var medal := "🥇" if place == 1 else ("🥈" if place == 2 else "🥉" if place == 3 else "  ")
		var pct: float = (float(total) / float(max_possible) * 100.0) if max_possible > 0 else 0.0

		var color := Color(0.2, 1.0, 0.4) if pct >= 80 else (Color(1.0, 0.8, 0.0) if pct >= 50 else Color(1.0, 0.3, 0.3))
		_quiz_results_vbox.add_child(_create_label(
			"%s %d. %s — %d/%d баллов (%.0f%%)" % [medal, place, nick, total, max_possible, pct],
			16, color
		))
		place += 1

	var sep2 := HSeparator.new()
	sep2.add_theme_color_override("separator", _accent_color.darkened(0.5))
	_quiz_results_vbox.add_child(sep2)

	# Кнопки
	var btn_hbox := HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 10)

	var export_btn := _create_styled_button("📥 Экспорт результатов", Color(0.4, 0.8, 0.4))
	export_btn.pressed.connect(_show_export_dialog)
	btn_hbox.add_child(export_btn)

	var plan_btn := _create_styled_button("🧠 План изучения", Color(0.8, 0.6, 1.0))
	plan_btn.pressed.connect(func():
		_quiz_results_panel.visible = false
		_on_study_plan_pressed()
	)
	btn_hbox.add_child(plan_btn)

	_quiz_results_vbox.add_child(btn_hbox)

	_quiz_results_panel.visible = true


# ==============================================================================
# Аналитика преподавателя
# ==============================================================================

func _on_analytics_pressed() -> void:
	_lobby_panel.visible = false
	_analytics_panel.visible = true
	_populate_analytics()


func _populate_analytics() -> void:
	for child in _analytics_vbox.get_children():
		child.queue_free()

	# Проверяем, что мы хост
	if not multiplayer.is_server():
		_analytics_vbox.add_child(_create_label("⚠️ Аналитика доступна только преподавателю (хосту)", 16, Color(1.0, 0.7, 0.3)))
		return

	# Общая статистика из локальной истории (хоста)
	_analytics_vbox.add_child(_create_label("📈 Аналитика преподавателя", 20, _accent_color))

	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", _accent_color.darkened(0.5))
	_analytics_vbox.add_child(sep)

	# Средняя успеваемость
	var avg := StudentHistory.get_average_score()
	var avg_color := Color(0.2, 1.0, 0.4) if avg >= 7.0 else (Color(1.0, 0.8, 0.0) if avg >= 4.0 else Color(1.0, 0.3, 0.3))
	_analytics_vbox.add_child(_create_label("📊 Средний балл: %.1f / 10" % avg, 18, avg_color))

	_analytics_vbox.add_child(_create_label("📋 Всего ответов: %d" % StudentHistory.get_history().size(), 14, Color(0.6, 0.65, 0.8)))

	var sep2 := HSeparator.new()
	sep2.add_theme_color_override("separator", _accent_color.darkened(0.5))
	_analytics_vbox.add_child(sep2)

	# Слабые темы группы
	var weak_topics := StudentHistory.get_weak_topics(5)
	if not weak_topics.is_empty():
		_analytics_vbox.add_child(_create_label("⚠️ Слабые темы:", 16, Color(1.0, 0.7, 0.3)))
		for t in weak_topics:
			var bar := ""
			var filled := int(t["avg_score"])
			for _i in range(filled):
				bar += "█"
			for _i in range(10 - filled):
				bar += "░"
			_analytics_vbox.add_child(_create_label(
				"  %s %s — ср. балл: %.1f (%d ответов)" % [bar, t["topic"], t["avg_score"], t["count"]],
				13, Color(1.0, 0.8, 0.5)
			))

		var sep3 := HSeparator.new()
		sep3.add_theme_color_override("separator", _accent_color.darkened(0.5))
		_analytics_vbox.add_child(sep3)

	# Слабые зоны
	var weak_zones := StudentHistory.get_weak_zones(5)
	if not weak_zones.is_empty():
		_analytics_vbox.add_child(_create_label("🔍 Частые ошибки:", 16, Color(1.0, 0.6, 0.4)))
		for zone in weak_zones:
			_analytics_vbox.add_child(_create_label(
				"  • %s (встречается %d раз)" % [zone["zone"], zone["count"]],
				13, Color(1.0, 0.7, 0.5)
			))

		var sep4 := HSeparator.new()
		sep4.add_theme_color_override("separator", _accent_color.darkened(0.5))
		_analytics_vbox.add_child(sep4)

	# Темы для повторения
	var review := StudentHistory.get_topics_to_review(5)
	if not review.is_empty():
		_analytics_vbox.add_child(_create_label("📚 Рекомендуется повторить:", 16, Color(0.8, 0.6, 1.0)))
		for r in review:
			_analytics_vbox.add_child(_create_label(
				"  • %s (рекомендовано %d раз)" % [r["topic"], r["count"]],
				13, Color(0.7, 0.6, 0.9)
			))

		var sep5 := HSeparator.new()
		sep5.add_theme_color_override("separator", _accent_color.darkened(0.5))
		_analytics_vbox.add_child(sep5)

	# Динамика результатов
	var dynamics := StudentHistory.get_results_dynamics()
	if not dynamics.is_empty():
		_analytics_vbox.add_child(_create_label("📈 Динамика результатов:", 16, _accent_color))
		for d in dynamics:
			var bar := ""
			var filled := int(d["avg_score"])
			for _i in range(filled):
				bar += "█"
			for _i in range(10 - filled):
				bar += "░"

			var trend_color := Color(0.2, 1.0, 0.4) if d["avg_score"] >= 7.0 else (Color(1.0, 0.8, 0.0) if d["avg_score"] >= 4.0 else Color(1.0, 0.3, 0.3))
			_analytics_vbox.add_child(_create_label(
				"  %s: %s %.1f/10 (%d ответов)" % [d["date"], bar, d["avg_score"], d["count"]],
				12, trend_color
			))

		var sep6 := HSeparator.new()
		sep6.add_theme_color_override("separator", _accent_color.darkened(0.5))
		_analytics_vbox.add_child(sep6)

	# Таблица студентов (подключённых)
	if NetworkManager.players.size() > 0:
		_analytics_vbox.add_child(_create_label("🧑‍🎓 Студенты в лобби:", 16, _accent_color))
		for peer_id in NetworkManager.players:
			var info: Dictionary = NetworkManager.players[peer_id]
			var nick: String = info.get("nickname", "Студент")
			var color: Color = info.get("color", Color.WHITE)
			var height: float = info.get("height", 0.0)
			_analytics_vbox.add_child(_create_label(
				"  • %s — %.0f баллов" % [nick, height],
				14, color
			))

	# Кнопка экспорта
	var export_btn := _create_styled_button("📥 Экспорт аналитики", Color(0.4, 0.8, 0.4))
	export_btn.pressed.connect(_show_export_dialog)
	_analytics_vbox.add_child(export_btn)


# ==============================================================================
# Утилиты
# ==============================================================================

func _get_gemini_api() -> Node:
	if _gemini_api != null:
		return _gemini_api
	# Ищем GeminiAPI через GameManager
	var gm := get_node_or_null("/root/GameManager")
	if gm:
		_gemini_api = gm.get_node_or_null("GeminiAPI")
	return _gemini_api


# ==============================================================================
# Диалог экспорта файла
# ==============================================================================

func _create_export_dialog() -> void:
	_export_dialog = FileDialog.new()
	_export_dialog.name = "ExportDialog"
	_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_export_dialog.title = "📥 Сохранить отчёт"
	_export_dialog.filters = PackedStringArray(["*.txt ; Текстовый файл"])
	_export_dialog.min_size = Vector2i(600, 400)
	_export_dialog.file_selected.connect(_on_export_file_selected)
	add_child(_export_dialog)


func _show_export_dialog(mode: ExportMode = ExportMode.HISTORY) -> void:
	_export_mode = mode
	var datetime := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	if mode == ExportMode.STUDY_PLAN:
		_export_dialog.current_file = "study_plan_%s.txt" % datetime
	else:
		_export_dialog.current_file = "report_%s.txt" % datetime
		
	var desktop := OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	if desktop != "":
		_export_dialog.current_dir = desktop
	_export_dialog.popup_centered()


func _on_export_file_selected(path: String) -> void:
	var saved_path := ""
	if _export_mode == ExportMode.STUDY_PLAN:
		saved_path = StudentHistory.export_study_plan_to_text(_current_study_plan, path)
	else:
		saved_path = StudentHistory.export_to_text(path)
		
	if saved_path != "":
		print("[Экспорт] ✅ Файл сохранён: %s" % saved_path)
		_validation_label.text = "✅ Сохранён в: %s" % saved_path
		_validation_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
