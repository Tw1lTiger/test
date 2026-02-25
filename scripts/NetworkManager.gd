# ==============================================================================
# NetworkManager.gd — Автолоад, управляющий сетевым подключением (ENet)
# ==============================================================================
extends Node

## Сигналы для UI и GameManager
signal player_connected(peer_id: int, info: Dictionary)
signal player_disconnected(peer_id: int)
signal server_created()
signal connection_failed()
signal connection_succeeded()
signal lobby_updated(players: Dictionary)

## Словарь всех игроков: {peer_id: {nickname, color, height, slot}}
var players: Dictionary = {}

## Информация о локальном игроке
var local_player_info: Dictionary = {"nickname": "Игрок", "color": Color.WHITE}

## Код комнаты (генерируется при создании сервера)
var room_code: String = ""

## Порт по умолчанию
const DEFAULT_PORT: int = 9876
const MAX_PLAYERS: int = 30

## Цвета для игроков (неоновая палитра)
const PLAYER_COLORS: Array[Color] = [
	Color(0.0, 1.0, 0.9),   # Бирюзовый
	Color(1.0, 0.2, 0.6),   # Розовый
	Color(0.4, 0.8, 1.0),   # Голубой
	Color(1.0, 0.8, 0.0),   # Жёлтый
	Color(0.6, 0.2, 1.0),   # Фиолетовый
]


func _ready() -> void:
	# Подключаем встроенные сигналы мультиплеера
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ==============================================================================
# Создание и подключение к серверу
# ==============================================================================

## Создать сервер (хост)
func create_server(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		push_error("Не удалось создать сервер: %s" % error_string(error))
		return error

	multiplayer.multiplayer_peer = peer

	# Генерируем код комнаты
	room_code = _generate_room_code()

	# Добавляем хоста как Player 1
	var slot := 0
	local_player_info["color"] = PLAYER_COLORS[slot]
	local_player_info["slot"] = slot
	local_player_info["height"] = 0.0
	players[1] = local_player_info.duplicate()

	server_created.emit()
	lobby_updated.emit(players)

	# Запускаем LAN-вещание (с кодом комнаты)
	LANDiscovery.start_broadcasting(port, local_player_info.get("nickname", "Хост"), GameManager.use_ai_questions, room_code)

	print("[Сервер] Сервер создан на порту %d | Код комнаты: %s" % [port, room_code])
	return OK


## Присоединиться к серверу (клиент)
func join_server(ip: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(ip, port)
	if error != OK:
		push_error("Не удалось подключиться к серверу: %s" % error_string(error))
		return error

	multiplayer.multiplayer_peer = peer
	print("[Клиент] Подключение к %s:%d..." % [ip, port])
	return OK


## Отключиться от сервера
func disconnect_from_server() -> void:
	players.clear()
	room_code = ""
	LANDiscovery.stop()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null


# ==============================================================================
# Обработка сетевых событий
# ==============================================================================

func _on_peer_connected(id: int) -> void:
	print("[Сеть] Пир подключился: %d" % id)
	# Клиент отправляет свою информацию серверу
	if not multiplayer.is_server():
		_register_player.rpc_id(1, local_player_info)


func _on_peer_disconnected(id: int) -> void:
	print("[Сеть] Пир отключился: %d" % id)
	if players.has(id):
		players.erase(id)
		player_disconnected.emit(id)
		if multiplayer.is_server():
			_sync_players.rpc(players)


func _on_connected_to_server() -> void:
	print("[Клиент] Успешно подключился к серверу!")
	connection_succeeded.emit()


func _on_connection_failed() -> void:
	print("[Клиент] Не удалось подключиться к серверу!")
	connection_failed.emit()
	multiplayer.multiplayer_peer = null


func _on_server_disconnected() -> void:
	print("[Клиент] Сервер отключился!")
	players.clear()
	multiplayer.multiplayer_peer = null
	lobby_updated.emit(players)


# ==============================================================================
# RPC — синхронизация игроков
# ==============================================================================

## Клиент отправляет свою информацию серверу
@rpc("any_peer", "reliable")
func _register_player(info: Dictionary) -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	var slot := players.size()
	if slot >= MAX_PLAYERS:
		push_warning("Лобби полное, игрок %d отклонён" % sender_id)
		return

	# Цвет выбирает клиент, либо (если нет) — назначаем по слоту
	if not info.has("color"):
		info["color"] = PLAYER_COLORS[min(slot, PLAYER_COLORS.size() - 1)]
	
	info["slot"] = slot
	info["height"] = 0.0
	players[sender_id] = info
	
	player_connected.emit(sender_id, info)
	print("[Сервер] Зарегистрирован игрок %d: %s (Color: %s)" % [sender_id, info.get("nickname", "?"), info["color"]])

	# Разослать обновлённый список всем
	_sync_players.rpc(players)

	# Обновить количество игроков для LAN-вещания
	LANDiscovery.update_player_count(players.size())


## Клиент запрашивает смену цвета
@rpc("any_peer", "call_local", "reliable")
func request_color_change(color_idx: int) -> void:
	if not multiplayer.is_server():
		return
		
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1 # Если вызвано локально напрямую (на всякий случай)
		
	if not players.has(sender_id):
		return
		
	if color_idx < 0 or color_idx >= PLAYER_COLORS.size():
		return
		
	var new_color := PLAYER_COLORS[color_idx]
	players[sender_id]["color"] = new_color
	
	# Синхронизация
	_sync_players.rpc(players)


## Сервер рассылает полный список игроков
@rpc("authority", "reliable", "call_local")
func _sync_players(all_players: Dictionary) -> void:
	players = all_players
	lobby_updated.emit(players)
	print("[Сеть] Список игроков обновлён: %d чел." % players.size())


## Обновить высоту игрока (вызывается GameManager-ом на сервере)
func update_player_height(peer_id: int, new_height: float) -> void:
	if players.has(peer_id):
		players[peer_id]["height"] = new_height


## Получить количество подключённых игроков
func get_player_count() -> int:
	return players.size()


## Проверить, является ли этот экземпляр сервером
func is_host() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()


## Генерация кода комнаты (6 символов: цифры + буквы)
func _generate_room_code() -> String:
	var chars := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # без 0/O/1/I для удобства
	var code := ""
	for i in range(6):
		code += chars[randi() % chars.length()]
	return code


## Найти сервер по коду комнаты (через LAN Discovery)
func find_server_by_code(code: String) -> Dictionary:
	var upper_code := code.to_upper().strip_edges()
	for key in LANDiscovery.servers:
		var info: Dictionary = LANDiscovery.servers[key]
		if str(info.get("room_code", "")).to_upper() == upper_code:
			return info
	return {}


## Подключиться по коду комнаты
func join_by_code(code: String) -> Error:
	var server := find_server_by_code(code)
	if server.is_empty():
		push_warning("[Сеть] Комната с кодом '%s' не найдена" % code)
		return ERR_DOES_NOT_EXIST
	var ip: String = server.get("ip", "")
	var port: int = server.get("port", DEFAULT_PORT)
	print("[Сеть] Найдена комната '%s' -> %s:%d" % [code, ip, port])
	return join_server(ip, port)
