extends Node

const DEFAULT_PORT = 8910
const MAX_CLIENTS = 4

var peer: ENetMultiplayerPeer = null

signal player_connected(id: int)
signal player_disconnected(id: int)
signal connected_to_server
signal connection_failed
signal server_disconnected
signal lobby_roster_updated

# peer_id -> {"name": String, "is_ready": bool}
var players : Dictionary = {} 

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host_game() -> Error:
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(DEFAULT_PORT, MAX_CLIENTS)
	if error != OK:
		return error
		
	multiplayer.multiplayer_peer = peer
	
	# Register host locally
	players[1] = {"name": "Host", "is_ready": true}
	lobby_roster_updated.emit()
	return OK

func join_game(address: String) -> Error:
	peer = ENetMultiplayerPeer.new()
	if address.is_empty():
		address = "127.0.0.1" # Default to localhost
	var error = peer.create_client(address, DEFAULT_PORT)
	if error != OK:
		return error
		
	multiplayer.multiplayer_peer = peer
	return OK

func stop_network() -> void:
	if peer:
		peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()
	lobby_roster_updated.emit()

func _on_peer_connected(id: int) -> void:
	print("NetworkManager: Player connected ", id)

func _on_peer_disconnected(id: int) -> void:
	print("NetworkManager: Player disconnected ", id)
	if players.has(id):
		players.erase(id)
		player_disconnected.emit(id)
		lobby_roster_updated.emit()

func _on_connected_to_server() -> void:
	print("NetworkManager: Connected to server successfully.")
	# When connected, tell the server our info
	var my_name = "Player_" + str(multiplayer.get_unique_id())
	rpc_id(1, "register_player", my_name)
	connected_to_server.emit()
	
func _on_connection_failed() -> void:
	print("NetworkManager: Failed to connect to server.")
	multiplayer.multiplayer_peer = null
	connection_failed.emit()

func _on_server_disconnected() -> void:
	print("NetworkManager: Server disconnected.")
	multiplayer.multiplayer_peer = null
	players.clear()
	server_disconnected.emit()

@rpc("any_peer", "call_remote", "reliable")
func register_player(player_name: String) -> void:
	var id = multiplayer.get_remote_sender_id()
	players[id] = {"name": player_name, "is_ready": false}
	
	if multiplayer.is_server():
		# Sync the updated roster back to all clients
		sync_players.rpc(players)
		lobby_roster_updated.emit()

@rpc("authority", "call_local", "reliable")
func sync_players(server_players: Dictionary) -> void:
	players = server_players
	lobby_roster_updated.emit()
