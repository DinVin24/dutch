extends Node

const DEFAULT_PORT = 1234
const DEFAULT_TEST_PORT = 1234
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
signal host_lan_ip_updated(ip: String)
signal lobby_error(message: String)

var multiplayer_peer: ENetMultiplayerPeer = null
var room_code: String = ""
var discovery_server: PacketPeerUDP = null
var discovery_client: PacketPeerUDP = null
var pending_join_code: String = ""
var discovery_deadline_ms: int = 0
var detected_host_lan_ip: String = "127.0.0.1"
var _last_connect_target_ip: String = ""
var _last_connect_target_port: int = DEFAULT_PORT
var _last_connect_started_ms: int = 0

# Multiplayer logging. Keep on by default for easier debugging.
const MP_LOG_ENABLED := true

func _mp_local_peer_id() -> int:
	# 1 is host on the server side; clients are assigned unique ids after connect.
	if multiplayer != null:
		var pid := multiplayer.get_unique_id()
		if pid != 0:
			return pid
	return -1

func _mp_is_host() -> bool:
	return bool(local_player_info.get("is_host", false))

func _mp_log(category: String, message: String, fields: Dictionary = {}) -> void:
	if not MP_LOG_ENABLED:
		return
	var ts := Time.get_datetime_string_from_system(true)
	var base := {
		"peer": _mp_local_peer_id(),
		"is_host": _mp_is_host(),
		"players": players.size(),
		"room": room_code
	}
	for k in fields.keys():
		base[k] = fields[k]
	print("[MP %s] %s | %s | %s" % [ts, category, message, str(base)])

# Public wrapper for UI callers.
func mp_log(category: String, message: String, fields: Dictionary = {}) -> void:
	_mp_log(category, message, fields)

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
	_mp_log("lifecycle", "ready", {
		"has_peer": multiplayer.multiplayer_peer != null
	})

func set_local_player_name(new_name: String):
	local_player_info["name"] = new_name

func host_game(port: int = DEFAULT_PORT):
	_stop_discovery_client()
	_mp_log("host_game", "start", {"port": port})
	multiplayer_peer = ENetMultiplayerPeer.new()
	# Explicitly request bind on all interfaces for LAN accessibility.
	if multiplayer_peer.has_method("set_bind_ip"):
		multiplayer_peer.set_bind_ip("0.0.0.0")
		_mp_log("host_game", "bind_ip forced", {"bind_ip": "0.0.0.0"})
	else:
		_mp_log("host_game", "bind_ip api missing; using default bind", {})
	# ENet server sockets use UDP and bind on all interfaces by default in Godot.
	# For LAN tests on Windows, allow inbound UDP on this port in Windows Firewall.
	var error = multiplayer_peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		if error == ERR_ALREADY_IN_USE:
			_mp_log("host_game", "fail: already in use", {"port": port, "error": error, "error_str": _describe_error(error)})
			_emit_lobby_error("Host failed: UDP %d already in use. Close other host instances or pick another port." % port)
		else:
			_mp_log("host_game", "fail: create_server", {"port": port, "error": error, "error_str": _describe_error(error)})
			_emit_lobby_error("Host failed on UDP %d (%s)." % [port, _describe_error(error)])
		return false
	
	multiplayer.multiplayer_peer = multiplayer_peer
	local_player_info["is_host"] = true
	detected_host_lan_ip = get_local_ip()
	host_lan_ip_updated.emit(detected_host_lan_ip)
	room_code = _generate_room_code(detected_host_lan_ip)
	players[1] = local_player_info
	_start_discovery_server()
	players_updated.emit()
	_mp_log("host_game", "started", {
		"port": port,
		"host_ip": detected_host_lan_ip,
		"local_ips": ", ".join(_collect_lan_ipv4_addresses())
	})
	return true

func join_game(code: String, port: int = DEFAULT_PORT):
	_stop_discovery_server()
	_stop_discovery_client()
	var raw_code = code.strip_edges()
	if raw_code == "":
		_mp_log("join_game", "invalid: empty code", {})
		return false
	_mp_log("join_game", "start", {"code": raw_code, "port": port})

	local_player_info["is_host"] = false
	if _is_ipv4(raw_code):
		return _connect_to_host(raw_code, port)
	var ip = _decode_room_code(raw_code)
	if ip == "":
		ip = decode_ip(raw_code)
	if ip != "":
		return _connect_to_host(ip, port)
	var normalized_code = raw_code.to_upper()
	_start_discovery_client(normalized_code)
	_mp_log("discovery", "start", {"code": normalized_code, "timeout_sec": DISCOVERY_TIMEOUT_SEC, "port": DISCOVERY_PORT})
	return true

func leave_game():
	_mp_log("leave_game", "start", {
		"had_peer": multiplayer.multiplayer_peer != null,
		"was_host": _mp_is_host()
	})
	multiplayer.multiplayer_peer = null
	multiplayer_peer = null
	room_code = ""
	players.clear()
	local_player_info["is_host"] = false
	_stop_discovery_server()
	_stop_discovery_client()
	_mp_log("leave_game", "done", {})

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

func get_detected_host_lan_ip() -> String:
	return detected_host_lan_ip

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
		_mp_log("discovery_server", "bind failed", {"port": DISCOVERY_PORT, "error": err, "error_str": _describe_error(err)})
		discovery_server = null
	else:
		_mp_log("discovery_server", "bound", {"port": DISCOVERY_PORT})

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
		_mp_log("discovery_client", "bind failed", {"error": bind_err, "error_str": _describe_error(bind_err)})
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
	_mp_log("discovery_client", "bound+queried", {"code": code})

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
		_mp_log("discovery_server", "responded", {"to_ip": requester_ip, "to_port": requester_port, "code": code})

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
		_mp_log("discovery_client", "response", {"code": pending_join_code, "discovered_ip": discovered_ip})
		_stop_discovery_client()
		_connect_to_host(discovered_ip)
		return
	if discovery_deadline_ms > 0 and Time.get_ticks_msec() > discovery_deadline_ms:
		_mp_log("discovery_client", "timeout", {"code": pending_join_code, "timeout_sec": DISCOVERY_TIMEOUT_SEC})
		_emit_lobby_error("Host discovery timed out for code %s. Check both PCs are on the same LAN and allow UDP %d." % [pending_join_code, DISCOVERY_PORT])
		_stop_discovery_client()

func _send_discovery_query(target_ip: String, code: String):
	if discovery_client == null:
		return
	discovery_client.set_dest_address(target_ip, DISCOVERY_PORT)
	var packet = (DISCOVERY_PREFIX + code).to_utf8_buffer()
	discovery_client.put_packet(packet)

func connect_to_host_direct(ip: String = "127.0.0.1", port: int = DEFAULT_PORT) -> bool:
	_stop_discovery_server()
	_stop_discovery_client()
	local_player_info["is_host"] = false
	return _connect_to_host(ip, port)

func host_test_game() -> bool:
	return host_game(DEFAULT_TEST_PORT)

func join_test_game(ip: String = "127.0.0.1") -> bool:
	return connect_to_host_direct(ip, DEFAULT_TEST_PORT)

func _emit_lobby_error(message: String) -> void:
	if message.strip_edges() == "":
		return
	lobby_error.emit(message)

func _connect_to_host(ip: String, port: int = DEFAULT_PORT) -> bool:
	multiplayer_peer = ENetMultiplayerPeer.new()
	_last_connect_target_ip = ip
	_last_connect_target_port = port
	_last_connect_started_ms = Time.get_ticks_msec()
	_mp_log("connect", "start", {"ip": ip, "port": port})
	var error = multiplayer_peer.create_client(ip, port)
	if error != OK:
		_mp_log("connect", "fail: create_client", {"ip": ip, "port": port, "error": error, "error_str": _describe_error(error)})
		_emit_lobby_error("Client create failed for %s:%d (%s)." % [ip, port, _describe_error(error)])
		return false
	multiplayer.multiplayer_peer = multiplayer_peer
	local_player_info["is_host"] = false
	# Client side is UDP ENet as well; open outbound UDP 1234 in restrictive environments.
	_mp_log("connect", "created client peer", {"ip": ip, "port": port})
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

func _collect_lan_ipv4_addresses() -> PackedStringArray:
	var ips: PackedStringArray = []
	for ip in IP.get_local_addresses():
		if _is_ipv4(ip) and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			ips.append(ip)
	if ips.is_empty():
		ips.append("127.0.0.1")
	return ips

func _describe_error(error_code: int) -> String:
	var readable = error_string(error_code)
	if readable == "":
		return "Unknown error"
	return readable

func _classify_connect_failure(elapsed_ms: int) -> Dictionary:
	if _last_connect_target_ip.begins_with("127."):
		return {
			"label": "loopback-mismatch",
			"cause": "Client targeted localhost; that only works when both peers run on the same PC.",
			"next_checks": "Use the host LAN IPv4 from host logs/UI and retry."
		}
	if elapsed_ms > 0 and elapsed_ms < 1500:
		return {
			"label": "refused-or-unreachable-fast-fail",
			"cause": "Fast failure usually means wrong IP/port, no host listener, or immediate block by firewall/router.",
			"next_checks": "Confirm host is running, verify target IP:port, and allow UDP port in firewall."
		}
	return {
		"label": "timeout-or-blocked",
		"cause": "No response before timeout; packets are likely dropped or not routed.",
		"next_checks": "Check firewall rules (Private/Public), ping host, verify same subnet, and disable AP/client isolation."
	}

# --- Callbacks ---

func _on_player_connected(id: int):
	_mp_log("peer_connected", "peer connected", {"id": id})
	# Host sends its own info to the new player (host is always peer 1)
	_mp_log("rpc", "send register_player (host->new)", {"to": id, "explicit_id": 1})
	_register_player.rpc_id(id, local_player_info, 1)
	# Host also tells the new player about all already-connected players
	for existing_id in players:
		if existing_id != 1: # host already sent above
			_mp_log("rpc", "send register_player (existing->new)", {"to": id, "explicit_id": existing_id})
			_register_player.rpc_id(id, players[existing_id], existing_id)
	# Host syncs current match settings to the new player
	_mp_log("rpc", "send sync_match_settings (host->new)", {"to": id, "settings": match_settings})
	sync_match_settings.rpc_id(id, match_settings)

func _on_player_disconnected(id: int):
	_mp_log("peer_disconnected", "peer disconnected", {"id": id})
	players.erase(id)
	player_disconnected.emit(id)
	players_updated.emit()

func _on_connected_ok():
	_mp_log("connected_ok", "connected to server", {"target_ip": _last_connect_target_ip, "target_port": _last_connect_target_port})
	var id = multiplayer.get_unique_id()
	players[id] = local_player_info
	# Send our info to the host so it can register us (no explicit_id needed — host uses sender_id)
	_mp_log("rpc", "send register_player (client->host)", {"to": 1, "explicit_id": id, "name": local_player_info.get("name", "")})
	_register_player.rpc_id(1, local_player_info, id)
	players_updated.emit()

func _on_connected_fail():
	var elapsed_ms = 0
	if _last_connect_started_ms > 0:
		elapsed_ms = Time.get_ticks_msec() - _last_connect_started_ms
	var fail_profile = _classify_connect_failure(elapsed_ms)
	var addresses = ", ".join(_collect_lan_ipv4_addresses())
	_mp_log("connected_fail", "failed to connect", {
		"target_ip": _last_connect_target_ip,
		"target_port": _last_connect_target_port,
		"local_ips": addresses,
		"elapsed_ms": elapsed_ms,
		"profile": fail_profile["label"],
		"cause": fail_profile["cause"],
		"next": fail_profile["next_checks"]
	})
	_emit_lobby_error("Connect failed. %s %s" % [fail_profile["cause"], fail_profile["next_checks"]])
	if multiplayer_peer != null and multiplayer_peer.has_method("get_connection_status"):
		_mp_log("connected_fail", "connection status", {"status": str(multiplayer_peer.get_connection_status())})
	_last_connect_started_ms = 0
	multiplayer.multiplayer_peer = null

func _on_server_disconnected():
	_mp_log("server_disconnected", "server disconnected", {})
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
	_mp_log("rpc.register_player", "registered player", {
		"sender_id": sender_id,
		"name": info.get("name", ""),
		"info": info
	})
@rpc("any_peer", "call_local", "reliable")
func sync_match_settings(settings: Dictionary):
	# Only accept settings from the host (peer id 1)
	var sender = multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		_mp_log("rpc.sync_match_settings", "rejected non-host sender", {"sender_id": sender})
		return
	var prev := match_settings.duplicate(true)
	match_settings = settings
	match_settings_updated.emit()
	_mp_log("rpc.sync_match_settings", "applied settings", {"sender_id": sender, "prev": prev, "next": match_settings})

@rpc("authority", "call_local", "reliable")
func start_match(total_players: int, deck_seed: int):
	var sender := multiplayer.get_remote_sender_id()
	_mp_log("rpc.start_match", "starting match", {"sender_id": sender, "total_players": total_players, "seed": deck_seed})
	GameManager.pending_mp_player_count = clampi(total_players, 2, 4)
	GameManager.pending_match_seed = deck_seed
	game_started.emit()
