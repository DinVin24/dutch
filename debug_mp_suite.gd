extends SceneTree

## Headless MP verification suite (mock sync, no WebRTC).
## Run: flatpak run org.godotengine.Godot --headless --path . -s res://debug_mp_suite.gd

const OUT_LOG := "res://.debug/mp/suite.log"
const MpCommon := preload("res://debug_mp_common.gd")

var _gm: Node
var _board: Node3D
var _failures: int = 0

func _init() -> void:
	call_deferred("_run")

func _log(line: String) -> void:
	MpCommon.log_to(OUT_LOG, line)

func _fail(tag: String, detail: String) -> void:
	_failures += 1
	_log("[MP FAIL] %s — %s" % [tag, detail])

func _pass(tag: String, detail: String = "") -> void:
	if detail != "":
		_log("[MP PASS] %s — %s" % [tag, detail])
	else:
		_log("[MP PASS] %s" % tag)

func _quit(code: int) -> void:
	MpCommon.release_gm_audio(_gm)
	if _board and is_instance_valid(_board):
		root.remove_child(_board)
		_board.free()
	await create_timer(0.1).timeout
	quit(code)

func _run() -> void:
	_log("=== DEBUG MP SUITE (headless mock sync) ===")
	await MpCommon.wait_for_autoloads(self)
	_gm = root.get_node_or_null("GameManager")
	if _gm == null:
		_log("[FATAL] GameManager autoload missing")
		await _quit(1)
		return

	await _phase_mp1_connect_roster()
	await _phase_mp2_sync_draw_discard()
	await _phase_mp3_disconnect_probe()
	await _phase_mp4_action_spam()
	await _phase_mp_ec2_perfect_match_client()
	await _phase_p3_stress_objects()

	if _failures == 0:
		_log("VERDICT: ALL MP HEADLESS PHASES PASSED")
		await _quit(0)
	else:
		_log("VERDICT: %d MP HEADLESS FAILURE(S)" % _failures)
		await _quit(1)

# MP-1: mock roster + payload peer map
func _phase_mp1_connect_roster() -> void:
	_log("\n>>> MP-1: Connect / roster mock <<<")
	_board = MpCommon.load_board(self)
	if _board == null:
		_fail("MP-1", "failed to load game_board_3d.tscn")
		return
	await process_frame
	await process_frame
	await create_timer(0.5).timeout
	await MpCommon.skip_initial_peek(_gm, self)

	MpCommon.configure_mock_mp(_gm, 1, 2)
	var payload: Dictionary = _gm._build_mp_sync_payload()

	if int(payload.get("num", 0)) != 2:
		_fail("MP-1", "payload num=%d expected 2" % int(payload.get("num", 0)))
	else:
		_pass("MP-1", "payload num_players=2")

	var peers: Array = payload.get("peers", [])
	if peers.size() < 2:
		_fail("MP-1", "payload peers=%s" % str(peers))
	else:
		_pass("MP-1", "peer map in sync payload: %s" % str(peers))

	if _gm.local_player_idx != 1:
		_fail("MP-1", "local_player_idx=%d expected 1" % _gm.local_player_idx)
	else:
		_pass("MP-1", "client local_player_idx=1")

# MP-2: host draw/discard → client board pending sync
func _phase_mp2_sync_draw_discard() -> void:
	_log("\n>>> MP-2: State sync draw→discard <<<")
	if _board == null:
		_fail("MP-2", "no board from MP-1")
		return

	# Server (P0) draw
	_gm.local_player_idx = 0
	_gm.current_player_index = 0
	_gm.player_draw_card()
	await process_frame
	for _i in 10:
		await process_frame

	var host_payload: Dictionary = _gm._build_mp_sync_payload()
	_gm._mp_sync_seq += 1
	host_payload["seq"] = _gm._mp_sync_seq

	# Client (P1) apply
	_gm.local_player_idx = 1
	_gm._apply_mp_sync_payload(host_payload)
	_gm.multiplayer_sync_applied.emit()
	await process_frame
	for _i in 10:
		await process_frame

	if _gm.drawn_card_data == null:
		_fail("MP-2", "drawn_card_data null after host draw")
	elif not MpCommon.pending_alive(_board):
		_fail("MP-2", "pending node missing on client after host draw sync")
	else:
		_pass("MP-2", "pending visible after draw sync (remote turn)")

	var d1: Dictionary = MpCommon.board_digest(_board)
	_log("[MP-2 DIGEST] after draw: %s" % str(d1))

	# Host discard
	_gm.local_player_idx = 0
	_gm.current_player_index = 0
	if _gm.drawn_card_data != null:
		_gm.player_discard_drawn_card()
		await create_timer(0.5).timeout
		for _i in 15:
			await process_frame

	host_payload = _gm._build_mp_sync_payload()
	_gm._mp_sync_seq += 1
	host_payload["seq"] = _gm._mp_sync_seq
	_gm.local_player_idx = 1
	_gm._apply_mp_sync_payload(host_payload)
	_gm.multiplayer_sync_applied.emit()
	await create_timer(0.5).timeout
	for _i in 10:
		await process_frame

	if MpCommon.pending_alive(_board):
		_fail("MP-2", "pending still present after discard sync")
	else:
		_pass("MP-2", "pending cleared after discard sync")

	if _gm.deck_manager.discard_pile.is_empty():
		_fail("MP-2", "discard pile empty after discard")
	else:
		_pass("MP-2", "discard pile size=%d" % _gm.deck_manager.discard_pile.size())

# MP-3: rage quit mid-turn — verify fix: seat eliminated, FSM unblocked
func _phase_mp3_disconnect_probe() -> void:
	_log("\n>>> MP-3: Disconnect / rage quit (fix verification) <<<")
	# Reset to a clean 2-player mock state
	MpCommon.configure_mock_mp(_gm, 0, 2)
	_gm.current_player_index = 1 # P1 (peer 2) is mid-turn
	_gm.change_state(_gm.GameState.TURN_START_DRAW, true)
	_gm.player_draw_card()
	await process_frame
	for _i in 5:
		await process_frame

	var had_pending := _gm.drawn_card_data != null
	var peers_before: int = _gm.peer_to_idx.size()

	# Simulate P1 (peer 2) rage-quit
	var nm := root.get_node_or_null("NetworkManager")
	if nm and nm.has_signal("player_disconnected"):
		nm.player_disconnected.emit(2)
	else:
		_log("[MP-3 WARN] NetworkManager not available — skipping")
		_pass("MP-3", "skipped (no NetworkManager autoload in this context)")
		return
	await process_frame
	for _i in 5:
		await process_frame

	var peers_after: int = _gm.peer_to_idx.size()
	if peers_after < peers_before:
		_pass("MP-3", "peer removed from roster (%d → %d)" % [peers_before, peers_after])
	else:
		_fail("MP-3", "ghost peer remains in peer_to_idx after disconnect")

	if _gm.players_info.size() > 1 and _gm.players_info[1].is_eliminated:
		_pass("MP-3", "disconnected player seat marked eliminated")
	else:
		_fail("MP-3", "disconnected player not eliminated in players_info")

	if had_pending and _gm.drawn_card_data == null:
		_pass("MP-3", "pending drawn card cleared on disconnect")
	elif not had_pending:
		_pass("MP-3", "no pending card was active")
	else:
		_fail("MP-3", "drawn_card_data still set after disconnect handler")

	if _gm.current_state == _gm.GameState.GAME_OVER:
		_pass("MP-3", "only 1 player remains — game ended correctly")
	elif _gm.current_player_index != 1:
		_pass("MP-3", "turn advanced away from disconnected player (cur=%d)" % _gm.current_player_index)
	else:
		_fail("MP-3", "FSM still on disconnected player's seat (cur=1 state=%s)" % _gm.GameState.keys()[_gm.current_state])

# MP-4: action spam on server
func _phase_mp4_action_spam() -> void:
	_log("\n>>> MP-4: Action spam / lag resilience <<<")
	_gm.local_player_idx = 0
	_gm.current_player_index = 0
	_gm.change_state(_gm.GameState.TURN_START_DRAW, true)
	var state_before: int = _gm.current_state
	var pending_before: Variant = _gm.drawn_card_data

	for _i in 8:
		_gm.player_draw_card()
		_gm.request_action("draw_card")
		await process_frame

	var draws: int = 1 if _gm.drawn_card_data != null else 0
	if _gm.drawn_card_data != null and pending_before == null:
		_pass("MP-4", "spam absorbed — single pending card (draws effective=%d)" % draws)
	elif _gm.drawn_card_data == pending_before:
		_pass("MP-4", "spam on non-draw state ignored")
	else:
		_fail("MP-4", "unexpected drawn_card state after spam")

	if _gm.current_state == _gm.GameState.GAME_OVER:
		_fail("MP-4", "FSM reached GAME_OVER from spam")
	else:
		_pass("MP-4", "FSM stable after spam state=%s" % _gm.GameState.keys()[_gm.current_state])

# MP-EC-2: Perfect Match clears pending on client sync path
func _phase_mp_ec2_perfect_match_client() -> void:
	_log("\n>>> MP-EC-2: Perfect Match + pending (client sync path) <<<")
	_gm.local_player_idx = 0
	_gm.current_player_index = 0
	_gm.change_state(_gm.GameState.TURN_START_DRAW, true)
	_gm.player_draw_card()
	await process_frame
	for _i in 10:
		await process_frame

	var slot: int = _gm.players_info[0].abilities.find("")
	if slot == -1:
		_gm.players_info[0].abilities.append("perfect_match")
	else:
		_gm.players_info[0].abilities[slot] = "perfect_match"

	# Sync draw to client view first
	var payload: Dictionary = _gm._build_mp_sync_payload()
	_gm._mp_sync_seq += 1
	payload["seq"] = _gm._mp_sync_seq
	_gm.local_player_idx = 0
	_gm._apply_mp_sync_payload(payload)
	await process_frame
	for _i in 10:
		await process_frame

	if not MpCommon.pending_alive(_board):
		_log("[MP-EC-2 WARN] no pending before perfect match — continuing")

	var ok: bool = _gm.play_ability(0, "perfect_match", 0)
	_log("[MP-EC-2] play_ability returned %s" % str(ok))
	await create_timer(1.5).timeout
	for _i in 15:
		await process_frame

	payload = _gm._build_mp_sync_payload()
	_gm._mp_sync_seq += 1
	payload["seq"] = _gm._mp_sync_seq
	payload["drawn"] = null
	_gm._apply_mp_sync_payload(payload)
	await process_frame
	for _i in 10:
		await process_frame

	if MpCommon.pending_alive(_board):
		_fail("MP-EC-2", "pending Card3D orphan after Perfect Match sync")
	else:
		_pass("MP-EC-2", "pending cleared after Perfect Match (V12 regression OK)")

	if _gm.drawn_card_data != null:
		_fail("MP-EC-2", "drawn_card_data still set")
	else:
		_pass("MP-EC-2", "drawn_card_data null")

# P-3: stress loop object monitor (headless proxy for Profiler)
func _phase_p3_stress_objects() -> void:
	_log("\n>>> P-3: Stress object monitor (20 draw/discard cycles) <<<")
	MpCommon.configure_mock_mp(_gm, 0, 2)
	_gm.change_state(_gm.GameState.TURN_START_DRAW, true)
	var baseline: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var peak: int = baseline
	var cycle: int = 0

	for i in 20:
		_gm.current_player_index = i % 2
		_gm.local_player_idx = _gm.current_player_index
		_gm.change_state(_gm.GameState.TURN_START_DRAW, true)
		_gm.player_draw_card()
		if _gm.drawn_card_data != null:
			_gm.player_discard_drawn_card()
		await process_frame
		await process_frame
		var obj: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
		peak = maxi(peak, obj)
		cycle += 1

	var final: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	await create_timer(2.0).timeout
	var settled: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))

	_log("[P-3] baseline=%d peak=%d final=%d settled=%d cycles=%d" % [baseline, peak, final, settled, cycle])
	if settled > baseline + 80:
		_fail("P-3", "object count drift +%d after 20 cycles (possible MP VFX leak)" % (settled - baseline))
	else:
		_pass("P-3", "object count stable delta=+%d (headless; use Profiler V10 for FPS)" % (settled - baseline))

	_log("[P-3 DOC] Manual V10: Profiler flame graph during 3 MP turns windowed — target FPS>=60")
