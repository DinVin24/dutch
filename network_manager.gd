extends Node

const DEFAULT_PORT = 8910
const MAX_PLAYERS = 4
const DISCOVERY_PORT = 8911
const DISCOVERY_TIMEOUT_SEC = 4.0
const DISCOVERY_PREFIX = "DUTCH_DISCOVER:"
const DISCOVERY_RESPONSE_PREFIX = "DUTCH_HOST:"

signal player_connected(id: int, info: Dictionary)
signal player_disconnected(id: int)
signal server_disconnected
signal players_updated
signal game_started
signal match_settings_updated

var multiplayer_peer: ENetMultiplayerPeer = null
var room_code: String = ""
var discovery_server: PacketPeerUDP = null
var discovery_client: PacketPeerUDP = null
var pending_join_code: String = ""
var discovery_deadline_ms: int = 0

# Local player info
var local_player_info = {
	"name": "Player",
	"is_host": false
}

# Networked players dictionary: id -> info dictionary
var players = {}

# Host match settings
var match_settings = {
	"no_abilities": false,
	"beers": 3,
	"cards_visibility": 0, # 0: Normal, 1: All Up, 2: All Down
	"fill_bots": false
}

func _ready():
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	set_process(true)

func set_local_player_name(new_name: String):
	local_player_info["name"] = new_name

func host_game():
	_stop_discovery_client()
	multiplayer_peer = ENetMultiplayerPeer.new()
	var error = multiplayer_peer.create_server(DEFAULT_PORT, MAX_PLAYERS)
	if error != OK:
		print("NetworkManager: Failed to create server! Error: ", error)
		return false
	
	multiplayer.multiplayer_peer = multiplayer_peer
	local_player_info["is_host"] = true
	room_code = _generate_room_code(get_local_ip())
	players[1] = local_player_info
	_start_discovery_server()
	players_updated.emit()
	print("NetworkManager: Server started with room code ", room_code)
	return true

func join_game(code: String):
	_stop_discovery_server()
	_stop_discovery_client()
	var raw_code = code.strip_edges()
	if raw_code == "":
		print("NetworkManager: Invalid code!")
		return false

	local_player_info["is_host"] = false
	var ip = _decode_room_code(raw_code)
	if ip == "":
		ip = decode_ip(raw_code)
	if ip != "":
		return _connect_to_host(ip)
	var normalized_code = raw_code.to_upper()
	_start_discovery_client(normalized_code)
	print("NetworkManager: Discovering host for code ", normalized_code)
	return true

func leave_game():
	multiplayer.multiplayer_peer = null
	multiplayer_peer = null
	room_code = ""
	players.clear()
	local_player_info["is_host"] = false
	_stop_discovery_server()
	_stop_discovery_client()

func get_local_ip() -> String:
	var ips = IP.get_local_addresses()
	for ip in ips:
		if _is_preferred_lan_ip(ip):
			return ip
	for ip in ips:
		if not ip.begins_with("127.") and not ":" in ip:
			return ip
	return "127.0.0.1"

func get_room_code() -> String:
	return room_code

func encode_ip(ip: String) -> String:
	# Simple base64 encode and strip padding for a cleaner "code"
	var b64 = Marshalls.utf8_to_base64(ip)
	return b64.replace("=", "")

func decode_ip(code: String) -> String:
	# Re-add padding if necessary
	var padded = code
	while padded.length() % 4 != 0:
		padded += "="
	
	var buffer = Marshalls.base64_to_raw(padded)
	if buffer.size() == 0:
		return ""
	var decoded = buffer.get_string_from_ascii()
	if not _is_ipv4(decoded):
		return ""
	return decoded

func _process(_delta: float):
	_poll_discovery_server()
	_poll_discovery_client()

func _start_discovery_server():
	_stop_discovery_server()
	discovery_server = PacketPeerUDP.new()
	var err = discovery_server.bind(DISCOVERY_PORT, "*")
	if err != OK:
		print("NetworkManager: Discovery server bind failed: ", err)
		discovery_server = null

func _stop_discovery_server():
	if discovery_server != null:
		discovery_server.close()
		discovery_server = null

func _start_discovery_client(code: String):
	pending_join_code = code
	discovery_client = PacketPeerUDP.new()
	discovery_client.set_broadcast_enabled(true)
	var bind_err = discovery_client.bind(0, "*")
	if bind_err != OK:
		print("NetworkManager: Discovery client bind failed: ", bind_err)
		_stop_discovery_client()
		return
	_send_discovery_query("255.255.255.255", code)
	_send_discovery_query("127.0.0.1", code)
	for ip in IP.get_local_addresses():
		if _is_ipv4(ip) and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			var octets = ip.split(".")
			octets[3] = "255"
			_send_discovery_query(".".join(octets), code)
	discovery_deadline_ms = Time.get_ticks_msec() + int(DISCOVERY_TIMEOUT_SEC * 1000.0)

func _stop_discovery_client():
	if discovery_client != null:
		discovery_client.close()
		discovery_client = null
	pending_join_code = ""
	discovery_deadline_ms = 0

func _poll_discovery_server():
	if discovery_server == null:
		return
	while discovery_server.get_available_packet_count() > 0:
		var packet = discovery_server.get_packet()
		var payload = packet.get_string_from_utf8()
		if not payload.begins_with(DISCOVERY_PREFIX):
			continue
		var code = payload.substr(DISCOVERY_PREFIX.length())
		if code != room_code:
			continue
		var requester_ip = discovery_server.get_packet_ip()
		var requester_port = discovery_server.get_packet_port()
		discovery_server.set_dest_address(requester_ip, requester_port)
		var response = "%s%s|%s" % [DISCOVERY_RESPONSE_PREFIX, room_code, get_local_ip()]
		discovery_server.put_packet(response.to_utf8_buffer())

func _poll_discovery_client():
	if discovery_client == null:
		return
	while discovery_client.get_available_packet_count() > 0:
		var packet = discovery_client.get_packet()
		var payload = packet.get_string_from_utf8()
		if not payload.begins_with(DISCOVERY_RESPONSE_PREFIX):
			continue
		var body = payload.substr(DISCOVERY_RESPONSE_PREFIX.length())
		var parts = body.split("|")
		if parts.size() != 2:
			continue
		if parts[0] != pending_join_code:
			continue
		var discovered_ip = parts[1]
		if not _is_ipv4(discovered_ip):
			continue
		_stop_discovery_client()
		_connect_to_host(discovered_ip)
		return
	if discovery_deadline_ms > 0 and Time.get_ticks_msec() > discovery_deadline_ms:
		print("NetworkManager: Lobby discovery timeout for code ", pending_join_code)
		_stop_discovery_client()

func _send_discovery_query(target_ip: String, code: String):
	if discovery_client == null:
		return
	discovery_client.set_dest_address(target_ip, DISCOVERY_PORT)
	var packet = (DISCOVERY_PREFIX + code).to_utf8_buffer()
	discovery_client.put_packet(packet)

func _connect_to_host(ip: String) -> bool:
	multiplayer_peer = ENetMultiplayerPeer.new()
	var error = multiplayer_peer.create_client(ip, DEFAULT_PORT)
	if error != OK:
		print("NetworkManager: Failed to create client! Error: ", error)
		return false
	multiplayer.multiplayer_peer = multiplayer_peer
	local_player_info["is_host"] = false
	print("NetworkManager: Connecting to ", ip)
	return true

func _generate_room_code(ip: String) -> String:
	var chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var prefix = ""
	for i in range(2):
		prefix += chars[rng.randi_range(0, chars.length() - 1)]
	var key = rng.randi_range(10, 99)
	var payload = _encode_ip_payload(ip, key)
	return "%s%02d%s" % [prefix, key, payload]

func _encode_ip_payload(ip: String, key: int) -> String:
	var parts = ip.split(".")
	if parts.size() != 4:
		return ""
	var payload = ""
	for p in parts:
		if not p.is_valid_int():
			return ""
		var value = int(p) ^ key
		payload += "%02X" % value
	return payload

func _decode_room_code(code: String) -> String:
	var normalized = code.strip_edges().to_upper()
	if normalized.length() != 12:
		return ""
	var key_str = normalized.substr(2, 2)
	if not key_str.is_valid_int():
		return ""
	var key = int(key_str)
	var payload = normalized.substr(4, 8)
	var parts: Array[String] = []
	for i in range(0, 8, 2):
		var pair = payload.substr(i, 2)
		var value = pair.hex_to_int() ^ key
		if value < 0 or value > 255:
			return ""
		parts.append(str(value))
	var decoded = ".".join(parts)
	if not _is_ipv4(decoded):
		return ""
	return decoded

func _is_ipv4(value: String) -> bool:
	var parts = value.split(".")
	if parts.size() != 4:
		return false
	for p in parts:
		if p == "" or not p.is_valid_int():
			return false
		var n = int(p)
		if n < 0 or n > 255:
			return false
	return true

func _is_preferred_lan_ip(ip: String) -> bool:
	if ":" in ip or ip.begins_with("127.") or ip.begins_with("169.254."):
		return false
	return ip.begins_with("10.") or ip.begins_with("192.168.") or ip.begins_with("172.")

# --- Callbacks ---

func _on_player_connected(id: int):
	print("NetworkManager: Player ", id, " connected.")
	# Host sends its own info to the new player (host is always peer 1)
	_register_player.rpc_id(id, local_player_info, 1)
	# Host also tells the new player about all already-connected players
	for existing_id in players:
		if existing_id != 1: # host already sent above
			_register_player.rpc_id(id, players[existing_id], existing_id)
	# Host syncs current match settings to the new player
	sync_match_settings.rpc_id(id, match_settings)

func _on_player_disconnected(id: int):
	print("NetworkManager: Player ", id, " disconnected.")
	players.erase(id)
	player_disconnected.emit(id)
	players_updated.emit()

func _on_connected_ok():
	print("NetworkManager: Successfully connected to server.")
	var id = multiplayer.get_unique_id()
	players[id] = local_player_info
	# Send our info to the host so it can register us (no explicit_id needed — host uses sender_id)
	_register_player.rpc_id(1, local_player_info, id)
	players_updated.emit()

func _on_connected_fail():
	print("NetworkManager: Failed to connect to server.")
	multiplayer.multiplayer_peer = null

func _on_server_disconnected():
	print("NetworkManager: Server disconnected.")
	players.clear()
	multiplayer.multiplayer_peer = null
	server_disconnected.emit()

# --- RPCs ---

@rpc("any_peer", "call_local", "reliable")
func _register_player(info: Dictionary, explicit_id: int = -1):
	var sender_id: int
	if explicit_id != -1:
		sender_id = explicit_id
	else:
		sender_id = multiplayer.get_remote_sender_id()
		if sender_id == 0:
			sender_id = multiplayer.get_unique_id()
	players[sender_id] = info
	player_connected.emit(sender_id, info)
	players_updated.emit()
	print("NetworkManager: Registered player ", sender_id, " (", info["name"], ")")
@rpc("any_peer", "call_local", "reliable")
func sync_match_settings(settings: Dictionary):
	# Only accept settings from the host (peer id 1)
	var sender = multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	match_settings = settings
	match_settings_updated.emit()
	print("NetworkManager: Match settings synced.")

@rpc("authority", "call_local", "reliable")
func start_match(total_players: int, deck_seed: int):
	print("NetworkManager: Starting match (players=", total_players, ", seed=", deck_seed, ")")
	GameManager.pending_mp_player_count = clampi(total_players, 2, 4)
	GameManager.pending_match_seed = deck_seed
	game_started.emit()
