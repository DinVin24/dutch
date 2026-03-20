extends Node3D

func _ready():
	# Wait multiple frames to ensure everything is ready
	for i in range(5):
		await get_tree().process_frame
	
	print("[PersonAnimator] Checking for animations in: ", name)
	
	var all_anim_players = find_children("*", "AnimationPlayer", true)
	if all_anim_players.size() == 0:
		# Try looking for AnimationTree as backup
		all_anim_players = find_children("*", "AnimationTree", true)
		
	if all_anim_players.size() > 0:
		for ap in all_anim_players:
			if ap is AnimationPlayer:
				var anim_list = ap.get_animation_list()
				print("[PersonAnimator] Found AnimationPlayer: ", ap.name, " with anims: ", anim_list)
				if anim_list.size() > 0:
					var anim_name = anim_list[0]
					var anim = ap.get_animation(anim_name)
					if anim:
						anim.loop_mode = Animation.LOOP_LINEAR
						ap.play(anim_name)
						print("[PersonAnimator] Started looping animation: ", anim_name)
			elif ap is AnimationTree:
				ap.active = true
				print("[PersonAnimator] Activated AnimationTree: ", ap.name)
	else:
		# List all children names for debugging
		var child_names = []
		for child in get_children():
			child_names.append(child.name)
		print("[PersonAnimator] ERROR: No animation nodes found. Children: ", child_names)
		
		# Proactively search all descendants
		var all_nodes = []
		_recursive_list_nodes(self, all_nodes)
		print("[PersonAnimator] Total descendant nodes: ", all_nodes.size())

func _recursive_list_nodes(node, list):
	for child in node.get_children():
		list.append(child.name + " (" + child.get_class() + ")")
		_recursive_list_nodes(child, list)
