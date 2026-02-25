# ==============================================================================
# LANDiscovery.gd — Автолоад: обнаружение серверов в локальной сети (UDP broadcast)
# ==============================================================================
extends Node

## Сигналы
signal server_found(info: Dictionary)
signal server_lost(ip: String)
signal server_list_updated(servers: Dictionary)

## Порт для broadcast-обнаружения (отличается от игрового порта!)
const DISCOVERY_PORT: int = 9877
const BROADCAST_INTERVAL: float = 2.0
const SERVER_TIMEOUT: float = 6.0
const MAGIC: String = "WORDRACE_LAN_V1"

## Найденные серверы: { "ip:port" : { ip, port, nickname, players, max_players, mode, last_seen } }
var servers: Dictionary = {}

## Режим работы
var _is_broadcasting: bool = false
var _is_listening: bool = false

## Сеть
var _broadcast_timer: Timer
var _cleanup_timer: Timer
var _udp_peer: PacketPeerUDP  # Для клиента — слушаем
var _broadcast_peer: PacketPeerUDP  # Для сервера — отправляем broadcast
var _server_peer: UDPServer  # Сервер для приёма входящих

## Данные для вещания
var _broadcast_data: Dictionary = {}


func _ready() -> void:
	_broadcast_timer = Timer.new()
	_broadcast_timer.name = "BroadcastTimer"
	_broadcast_timer.wait_time = BROADCAST_INTERVAL
	_broadcast_timer.timeout.connect(_on_broadcast_tick)
	add_child(_broadcast_timer)

	_cleanup_timer = Timer.new()
	_cleanup_timer.name = "CleanupTimer"
	_cleanup_timer.wait_time = 1.0
	_cleanup_timer.timeout.connect(_on_cleanup_tick)
	add_child(_cleanup_timer)


# ==============================================================================
# Серверная сторона — вещание (broadcast)
# ==============================================================================

## Начать вещание о сервере
func start_broadcasting(game_port: int, host_nickname: String, question_mode: bool = true, code: String = "") -> void:
	stop()

	_broadcast_data = {
		"magic": MAGIC,
		"port": game_port,
		"nickname": host_nickname,
		"players": 1,
		"max_players": NetworkManager.MAX_PLAYERS,
		"mode": "ai" if question_mode else "normal",
		"room_code": code
	}

	_broadcast_peer = PacketPeerUDP.new()
	_broadcast_peer.set_broadcast_enabled(true)
	_broadcast_peer.set_dest_address("255.255.255.255", DISCOVERY_PORT)

	_is_broadcasting = true
	_broadcast_timer.start()
	_send_broadcast()  # Первая отправка сразу
	print("[LANDiscovery] 📡 Вещание запущено (порт %d)" % game_port)


## Обновить информацию о количестве игроков
func update_player_count(count: int) -> void:
	if _is_broadcasting:
		_broadcast_data["players"] = count


## Отправить broadcast-пакет
func _send_broadcast() -> void:
	if not _is_broadcasting or _broadcast_peer == null:
		return

	# Обновляем количество игроков
	_broadcast_data["players"] = NetworkManager.get_player_count()

	var json := JSON.stringify(_broadcast_data)
	var packet := json.to_utf8_buffer()
	_broadcast_peer.put_packet(packet)


func _on_broadcast_tick() -> void:
	_send_broadcast()


# ==============================================================================
# Клиентская сторона — прослушивание
# ==============================================================================

## Начать слушать broadcast-пакеты
func start_listening() -> void:
	if _is_listening:
		return

	# Используем UDPServer для прослушивания broadcast
	_server_peer = UDPServer.new()
	var err := _server_peer.listen(DISCOVERY_PORT, "0.0.0.0")
	if err != OK:
		# Порт может быть занят (мы сами сервер)
		push_warning("[LANDiscovery] Не удалось слушать порт %d: %s" % [DISCOVERY_PORT, error_string(err)])
		# Пробуем через PacketPeerUDP
		_server_peer = null
		_udp_peer = PacketPeerUDP.new()
		err = _udp_peer.bind(DISCOVERY_PORT, "0.0.0.0")
		if err != OK:
			push_warning("[LANDiscovery] Также не удалось забиндить UDP: %s" % error_string(err))
			_udp_peer = null
			return

	_is_listening = true
	_cleanup_timer.start()
	print("[LANDiscovery] 👂 Слушаю broadcast на порту %d" % DISCOVERY_PORT)


## Остановить всё
func stop() -> void:
	_is_broadcasting = false
	_is_listening = false
	_broadcast_timer.stop()
	_cleanup_timer.stop()

	if _broadcast_peer != null:
		_broadcast_peer.close()
		_broadcast_peer = null

	if _udp_peer != null:
		_udp_peer.close()
		_udp_peer = null

	if _server_peer != null:
		_server_peer.stop()
		_server_peer = null

	servers.clear()
	print("[LANDiscovery] ⏹ Остановлено")


func stop_listening() -> void:
	_is_listening = false
	_cleanup_timer.stop()

	if _udp_peer != null:
		_udp_peer.close()
		_udp_peer = null

	if _server_peer != null:
		_server_peer.stop()
		_server_peer = null

	servers.clear()


## Обработка входящих пакетов (вызывается каждый кадр)
func _process(_delta: float) -> void:
	if not _is_listening:
		return

	# Через UDPServer
	if _server_peer != null:
		_server_peer.poll()
		while _server_peer.is_connection_available():
			var peer := _server_peer.take_connection()
			var packet := peer.get_packet()
			if packet.size() > 0:
				_handle_packet(packet, peer.get_packet_ip())

	# Через PacketPeerUDP (запасной вариант)
	if _udp_peer != null:
		while _udp_peer.get_available_packet_count() > 0:
			var packet := _udp_peer.get_packet()
			var ip := _udp_peer.get_packet_ip()
			if packet.size() > 0:
				_handle_packet(packet, ip)


## Обработка полученного broadcast-пакета
func _handle_packet(packet: PackedByteArray, sender_ip: String) -> void:
	var json_str := packet.get_string_from_utf8()
	var json := JSON.new()
	var err := json.parse(json_str)
	if err != OK:
		return

	var data: Dictionary = json.data
	if not data is Dictionary:
		return

	# Проверяем magic-строку
	if data.get("magic", "") != MAGIC:
		return

	var game_port: int = data.get("port", 9876)
	var key := "%s:%d" % [sender_ip, game_port]

	var server_info := {
		"ip": sender_ip,
		"port": game_port,
		"nickname": data.get("nickname", "Сервер"),
		"players": data.get("players", 1),
		"max_players": data.get("max_players", 5),
		"mode": data.get("mode", "normal"),
		"room_code": data.get("room_code", ""),
		"last_seen": Time.get_ticks_msec()
	}

	var is_new := not servers.has(key)
	servers[key] = server_info

	if is_new:
		server_found.emit(server_info)
		print("[LANDiscovery] 🆕 Найден сервер: %s (%s)" % [server_info["nickname"], key])

	server_list_updated.emit(servers)


## Удаление устаревших серверов
func _on_cleanup_tick() -> void:
	var now := Time.get_ticks_msec()
	var to_remove: Array[String] = []

	for key in servers:
		var info: Dictionary = servers[key]
		var elapsed: float = (now - info.get("last_seen", 0)) / 1000.0
		if elapsed > SERVER_TIMEOUT:
			to_remove.append(key)

	for key in to_remove:
		var info: Dictionary = servers[key]
		var ip: String = info.get("ip", "")
		servers.erase(key)
		server_lost.emit(ip)
		print("[LANDiscovery] ❌ Сервер пропал: %s" % key)

	if to_remove.size() > 0:
		server_list_updated.emit(servers)
