extends Node

const MAX_PLAYERS = 4
const SIGNALING_SERVER_URL = "wss://signal.maestriisigma.ro"

signal player_connected(id: int, info: Dictionary)
signal player_disconnected(id: int)
signal server_disconnected
signal players_updated
signal game_started
signal match_settings_updated
signal host_lan_ip_updated(ip: String)
signal lobby_error(message: String)
signal play_again_votes_updated(voted_count: int, total_humans: int)

var play_again_votes: Array = []
var multiplayer_peer: WebRTCMultiplayerPeer = null
var rtc_connections: Dictionary = {} # id -> WebRTCPeerConnection

var ws: WebSocketPeer = null
var room_code: String = ""
var is_connecting: bool = false

# Multiplayer logging. Keep on by default for easier debugging.
const MP_LOG_ENABLED := true

func _mp_local_peer_id() -> int:
	if multiplayer != null and multiplayer.multiplayer_peer != null:
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

func mp_log(category: String, message: String, fields: Dictionary = {}) -> void:
	_mp_log(category, message, fields)

var local_player_info = {
	"name": "Player",
	"is_host": false
}

var players = {}

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

func _connect_ws() -> bool:
	ws = WebSocketPeer.new()
	var err = ws.connect_to_url(SIGNALING_SERVER_URL)
	if err != OK:
		_emit_lobby_error("Could not connect to signaling server.")
		return false
	return true

func host_game() -> bool:
	_mp_log("host_game", "start")
	if not _connect_ws(): return false
	local_player_info["is_host"] = true
	is_connecting = true
	return true

func join_game(code: String) -> bool:
	var raw_code = code.strip_edges().to_upper()
	if raw_code == "": return false
	_mp_log("join_game", "start", {"code": raw_code})
	if not _connect_ws(): return false
	room_code = raw_code
	SettingsManager.set_last_room_code(raw_code)
	local_player_info["is_host"] = false
	is_connecting = true
	return true

func leave_game():
	_mp_log("leave_game", "start", {
		"had_peer": multiplayer.multiplayer_peer != null,
		"was_host": _mp_is_host()
	})
	if ws != null:
		ws.close()
		ws = null
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	multiplayer_peer = null
	room_code = ""
	players.clear()
	rtc_connections.clear()
	local_player_info["is_host"] = false
	is_connecting = false
	_mp_log("leave_game", "done", {})

func get_room_code() -> String:
	return room_code

func get_detected_host_lan_ip() -> String:
	return "Internet"

func _emit_lobby_error(message: String) -> void:
	if message.strip_edges() == "":
		return
	lobby_error.emit(message)

func _process(_delta: float):
	if ws != null:
		ws.poll()
		var state = ws.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			if is_connecting:
				is_connecting = false
				if local_player_info["is_host"]:
					ws.send_text(JSON.stringify({"type": "host"}))
				else:
					ws.send_text(JSON.stringify({"type": "join", "room": room_code}))
			while ws != null and ws.get_available_packet_count() > 0:
				var msg = ws.get_packet().get_string_from_utf8()
				_handle_signaling_message(msg)
		elif state == WebSocketPeer.STATE_CLOSED:
			var code = ws.get_close_code()
			var reason = ws.get_close_reason()
			_mp_log("ws", "closed", {"code": code, "reason": reason})
			ws = null
			if room_code != "" and multiplayer.multiplayer_peer == null:
				_emit_lobby_error("Lost connection to signaling server.")
				leave_game()

func _handle_signaling_message(msg: String):
	var data = JSON.parse_string(msg)
	if data == null: return
	var type = data.get("type", "")
	
	if type == "room_created":
		room_code = data["room"]
		SettingsManager.set_last_room_code(room_code)
		host_lan_ip_updated.emit("Internet")
		_mp_log("signaling", "room_created", {"room": room_code})
		_initialize_webrtc_host()
	
	elif type == "joined":
		var my_id = int(data["id"])
		var peers = data.get("peers", [])
		_mp_log("signaling", "joined", {"id": my_id, "peers": peers})
		_initialize_webrtc_client(my_id, peers)
		
	elif type == "peer_connected":
		var peer_id = int(data["id"])
		_mp_log("signaling", "peer_connected", {"peer_id": peer_id})
		_create_peer_connection(peer_id)
		
	elif type == "peer_disconnected":
		var peer_id = int(data["id"])
		if rtc_connections.has(peer_id):
			rtc_connections.erase(peer_id)
		
	elif type == "offer":
		var peer_id = int(data["from"])
		if rtc_connections.has(peer_id):
			rtc_connections[peer_id].set_remote_description("offer", data["sdp"])
			
	elif type == "answer":
		var peer_id = int(data["from"])
		if rtc_connections.has(peer_id):
			rtc_connections[peer_id].set_remote_description("answer", data["sdp"])
			
	elif type == "candidate":
		var peer_id = int(data["from"])
		if rtc_connections.has(peer_id):
			rtc_connections[peer_id].add_ice_candidate(data["mid"], data["index"], data["candidate"])
			
	elif type == "error":
		_emit_lobby_error(data.get("message", "Unknown error"))
		leave_game()

func _initialize_webrtc_host():
	multiplayer_peer = WebRTCMultiplayerPeer.new()
	var err = multiplayer_peer.create_server()
	if err != OK:
		_emit_lobby_error("Failed to create WebRTC host.")
		return
	multiplayer.multiplayer_peer = multiplayer_peer
	players[1] = local_player_info
	players_updated.emit()

func _initialize_webrtc_client(my_id: int, existing_peers: Array):
	multiplayer_peer = WebRTCMultiplayerPeer.new()
	var err = multiplayer_peer.create_client(my_id)
	if err != OK:
		_emit_lobby_error("Failed to create WebRTC client.")
		return
	multiplayer.multiplayer_peer = multiplayer_peer
	# Create peer connections for all existing peers
	for peer_id in existing_peers:
		_create_peer_connection(int(peer_id))

func _create_peer_connection(peer_id: int):
	var peer = WebRTCPeerConnection.new()
	peer.initialize({
		"iceServers": [ {"urls": ["stun:stun.l.google.com:19302"]}]
	})
	peer.session_description_created.connect(self._on_session_description_created.bind(peer_id))
	peer.ice_candidate_created.connect(self._on_ice_candidate_created.bind(peer_id))
	
	rtc_connections[peer_id] = peer
	multiplayer_peer.add_peer(peer, peer_id)
	
	var my_id = _mp_local_peer_id()
	if my_id == -1: my_id = 1 if local_player_info["is_host"] else 0
	
	if my_id > peer_id:
		peer.create_offer()

func _on_session_description_created(type: String, sdp: String, peer_id: int):
	var peer = rtc_connections.get(peer_id)
	if peer:
		peer.set_local_description(type, sdp)
		ws.send_text(JSON.stringify({
			"type": type,
			"to": peer_id,
			"sdp": sdp
		}))

func _on_ice_candidate_created(media: String, index: int, name: String, peer_id: int):
	ws.send_text(JSON.stringify({
		"type": "candidate",
		"to": peer_id,
		"mid": media,
		"index": index,
		"candidate": name
	}))

# --- Callbacks ---

func _on_player_connected(id: int):
	_mp_log("peer_connected", "peer connected", {"id": id})
	if _mp_is_host():
		_register_player.rpc_id(id, local_player_info, 1)
		for existing_id in players:
			if existing_id != 1:
				_register_player.rpc_id(id, players[existing_id], existing_id)
		sync_match_settings.rpc_id(id, match_settings)

func _on_player_disconnected(id: int):
	_mp_log("peer_disconnected", "peer disconnected", {"id": id})
	if rtc_connections.has(id):
		rtc_connections.erase(id)
	player_disconnected.emit(id)
	players_updated.emit()

func _on_connected_ok():
	_mp_log("connected_ok", "connected to server", {})
	var id = multiplayer.get_unique_id()
	players[id] = local_player_info
	_register_player.rpc_id(1, local_player_info, id)
	players_updated.emit()

func _on_connected_fail():
	_mp_log("connected_fail", "failed to connect", {})
	_emit_lobby_error("WebRTC Connection failed. Check internet.")
	leave_game()

func _on_server_disconnected():
	_mp_log("server_disconnected", "server disconnected", {})
	players.clear()
	rtc_connections.clear()
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
		"name": info.get("name", "")
	})

@rpc("any_peer", "call_local", "reliable")
func sync_match_settings(settings: Dictionary):
	var sender = multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		_mp_log("rpc.sync_match_settings", "rejected non-host sender", {"sender_id": sender})
		return
	match_settings = settings
	match_settings_updated.emit()

@rpc("authority", "call_local", "reliable")
func start_match(total_players: int, deck_seed: int):
	var sender := multiplayer.get_remote_sender_id()
	_mp_log("rpc.start_match", "starting match", {"sender_id": sender, "total_players": total_players, "seed": deck_seed})
	GameManager.pending_mp_player_count = clampi(total_players, 2, 4)
	GameManager.pending_match_seed = deck_seed
	play_again_votes.clear()
	game_started.emit()

@rpc("any_peer", "call_local", "reliable")
func vote_play_again() -> void:
	if not multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	
	if not play_again_votes.has(sender_id):
		play_again_votes.append(sender_id)
		_mp_log("vote_play_again", "peer voted", {"peer": sender_id, "votes": play_again_votes})
		
		# Check how many humans are in the game
		var human_count := 0
		for p in GameManager.players_info:
			if not p.get("is_bot", false):
				human_count += 1
		
		# Notify all clients about the updated vote count
		update_play_again_status.rpc(play_again_votes.size(), human_count)
		
		if play_again_votes.size() >= human_count:
			play_again_votes.clear()
			var total := GameManager.num_players
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			start_match.rpc(total, rng.randi())

@rpc("authority", "call_local", "reliable")
func update_play_again_status(voted_count: int, total_humans: int) -> void:
	play_again_votes_updated.emit(voted_count, total_humans)
