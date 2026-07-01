extends SceneTree

const GUN_ANIMATION_CATALOG := preload(
	"res://CombatCore/DuelUI/GunAnimationCatalog.gd"
)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var holder := Node.new()
	root.add_child(holder)

	var duel_scene := load("res://CombatCore/MainDuelScene.tscn") as PackedScene
	if not duel_scene:
		_fail("Could not load the combat scene.")
		return
	var arena = duel_scene.instantiate()
	holder.add_child(arena)
	await process_frame

	if arena.get_node_or_null("DebugUI") != null:
		_fail("The retired combat DebugUI still exists.")
		return

	var player_definition := load(
		"res://BiologicalCore/player_def.tres"
	) as EntityDefinition
	var enemy_definition := load(
		"res://BiologicalCore/scavenger_def.tres"
	) as EntityDefinition
	var player: HumanoidCore = arena._fabricate_humanoid(
		"HUD_Player",
		player_definition,
		false
	)
	player.stance_points = 0
	player._evaluate_stance_state()
	player.is_escaping = true
	arena.setup_duel(
		player,
		{
			"entity_id": "hud_smoke_enemy",
			"definition": enemy_definition.to_state(),
			"runtime": {},
		}
	)
	await process_frame

	if (
		player.current_stance != GameEnums.StanceState.PLANTED
		or player.stance_points != int(GameEnums.SCALE_MAX)
		or player.is_escaping
	):
		_fail("Encounter setup did not clear tactical state from prior combat.")
		return

	var snapshot: Dictionary = arena.command_adapter.get_snapshot()
	var lane_slots: Array = snapshot.get("lane_slots", [])
	if lane_slots.size() != 12:
		_fail("Combat snapshot did not expose exactly twelve lane slots.")
		return
	if (
		lane_slots[2].get("background_label", "") != "PLAINS"
		or lane_slots[2].get("ground_asset", "").is_empty()
		or not str(lane_slots[2].get("terrain_modifiers", [])).contains(
			"0 movement"
		)
	):
		_fail("The plains combat tile did not expose neutral terrain metadata.")
		return
	if (
		lane_slots[5].get("background", "") != "MUD"
		or not str(lane_slots[5].get("surface_asset", "")).contains(
			"Earth Patch"
		)
		or not str(lane_slots[5].get("terrain_modifiers", [])).contains(
			"walk trip"
		)
	):
		_fail("The mud combat tile did not expose hazard terrain metadata.")
		return
	if (
		lane_slots[4].get("object_name", "") != "Supply Crates"
		or lane_slots[4].get("object_asset", "").is_empty()
		or not str(lane_slots[4].get("object_interactions", [])).contains(
			"TAKE COVER"
		)
	):
		_fail("The combat tile object did not expose cover interaction metadata.")
		return
	if (
		lane_slots[0].get("surface_label", "") != "DIRT ROAD"
		or not str(lane_slots[0].get("object_interactions", [])).contains(
			"RETREAT"
		)
	):
		_fail("The escape road tile did not expose retreat metadata.")
		return
	if not _slot_has_side(lane_slots[2], "player"):
		_fail("Neutral deployment did not project the player in slot 2.")
		return
	if not _slot_has_side(lane_slots[9], "enemy"):
		_fail("Neutral deployment did not project the enemy in slot 9.")
		return

	var hud_snapshot: Dictionary = arena.lane_hud.get_snapshot()
	if hud_snapshot.get("lane_slots", []).size() != 12:
		_fail("CombatLaneHUD did not receive the twelve-slot snapshot.")
		return
	var hud_player: Dictionary = hud_snapshot.get("player", {})
	if (
		hud_player.get("weapon_id", "") != "service_pistol"
		or str(hud_player.get("weapon_sprite_path", "")).is_empty()
		or hud_player.get("weapon_state", "") != "READY"
		or (hud_player.get("active_weapon", {}) as Dictionary).is_empty()
	):
		_fail("The combat snapshot did not expose the active weapon card data.")
		return
	for descriptor in hud_snapshot.get("actions", []):
		if str((descriptor as Dictionary).get("group", "")).is_empty():
			_fail("A legal combat action did not expose an action group.")
			return
	var movement_descriptor := _find_action(
		hud_snapshot,
		GameEnums.ActionType.MOVE_FORWARD
	)
	if movement_descriptor.get("group", "") != "movement":
		_fail("MOVE_FORWARD was not grouped under the movement command type.")
		return
	var viewport_size: Vector2 = arena.lane_hud.get_viewport_rect().size
	var camera_zoom_before: float = arena.lane_hud.get_camera_zoom_value()
	var wheel_event := InputEventMouseButton.new()
	wheel_event.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_event.pressed = true
	arena.lane_hud._unhandled_input(wheel_event)
	await process_frame
	if not is_equal_approx(arena.lane_hud.get_camera_zoom_value(), camera_zoom_before):
		_fail("Combat camera wheel zoom was not ignored.")
		return
	var camera := arena.lane_hud._combat_camera as Camera2D
	var stage_bounds: Rect2 = arena.lane_hud._lane_view.get_stage_bounds_global()
	var half_view: Vector2 = viewport_size / arena.lane_hud.get_camera_zoom_value() * 0.5
	var camera_rect := Rect2(camera.global_position - half_view, half_view * 2.0)
	if not stage_bounds.grow(1.0).encloses(camera_rect):
		_fail("Combat camera exposed area outside the combat stage.")
		return
	arena.lane_hud.show_presentation_event({
		"type": "shot",
		"side": "player",
		"attacker_side": "player",
		"target_side": "enemy",
		"origin_lane": 2,
		"target_lane": 9,
		"result": "clean_miss",
	})
	await create_timer(0.12).timeout
	if not arena.lane_hud.has_projectile_vfx():
		_fail("Miss shot did not create a projectile trail.")
		return
	var bullet: Sprite2D = (
		arena.lane_hud._projectile_root.get_node_or_null("BulletSprite")
		as Sprite2D
	)
	if bullet == null or bullet.scale.x > 3.0 or bullet.scale.y > 2.0:
		_fail("The bullet sprite is still scaled like heavy artillery.")
		return
	var trail: Line2D = (
		arena.lane_hud._projectile_root.get_node_or_null("BulletTrail")
		as Line2D
	)
	if trail == null or trail.width > 2.0:
		_fail("The projectile trace is still too thick.")
		return
	if (
		trail.points.size() >= 2
		and trail.points[0].distance_to(trail.points[1])
			> CombatLaneHUD.PROJECTILE_TRACE_LENGTH + 18.0
	):
		_fail("The projectile trace still spans too much of the lane.")
		return
	await create_timer(0.85).timeout
	if arena.lane_hud.get_last_shot_event().get("result", "") != "clean_miss":
		_fail("Miss shot did not preserve its presentation result.")
		return
	var enemy_token: HumanoidTokenView = arena.lane_hud._lane_view._enemy_token
	var combat_sfx_events: Array[String] = []
	var bus = root.get_node_or_null("GameEventBus")
	if bus and bus.has_signal("scene_audio_requested"):
		bus.scene_audio_requested.connect(
			func(scene_id: String, _context: Dictionary) -> void:
				if scene_id.begins_with("combat_"):
					combat_sfx_events.append(scene_id)
		)
	enemy_token.play_animation("Idle2")
	arena.lane_hud.show_presentation_event({
		"type": "shot",
		"side": "player",
		"attacker_side": "player",
		"target_side": "enemy",
		"origin_lane": 2,
		"target_lane": 9,
		"result": "hit",
		"limb_index": GameEnums.LimbRegion.UPPER_TORSO,
	})
	await create_timer(CombatLaneHUD.PROJECTILE_DURATION_SECONDS * 0.5).timeout
	if enemy_token.get_animation() == "TakeDamage":
		_fail("The target damage animation started before bullet impact.")
		return
	if combat_sfx_events.has("combat_damage_sfx"):
		_fail("The target hurt sound fired before projectile impact.")
		return
	if not await _wait_for_animation(enemy_token, "TakeDamage", 45):
		_fail("The target damage animation did not wait for bullet impact.")
		return
	if not combat_sfx_events.has("combat_damage_sfx"):
		_fail("The target hurt sound did not fire at projectile impact.")
		return
	await create_timer(0.65).timeout
	if not arena.lane_hud.has_blood_vfx():
		_fail("Hit shot did not create blood VFX.")
		return
	if arena.lane_hud.has_projectile_vfx():
		_fail("Projectile trail lingered after blood VFX started.")
		return
	await create_timer(2.0).timeout
	enemy_token.play_animation("Idle2")
	arena.lane_hud.show_presentation_event({
		"type": "shot",
		"side": "player",
		"attacker_side": "player",
		"target_side": "enemy",
		"origin_lane": 2,
		"target_lane": 9,
		"result": "hit",
		"limb_index": GameEnums.LimbRegion.HEAD,
		"was_killed": true,
	})
	if not await _wait_for_animation(enemy_token, "Die", 45):
		_fail("Final shot did not drive the victim death animation.")
		return
	if enemy_token.get("_animation_speed_scale") >= 0.75:
		_fail("Final blow death animation was not slowed down.")
		return
	if not arena.lane_hud._fatal_thud_player.playing:
		_fail("Final blow did not trigger the fatal body-fall thud.")
		return
	if not await _wait_for_hud_queue(arena.lane_hud):
		_fail("Final blow presentation did not finish before the next HUD probe.")
		return
	if not arena.lane_hud._final_blow_complete_sides.has("enemy"):
		_fail("Final blow was not marked complete after the corpse fall.")
		return
	if arena.lane_hud._action_rect.position.y < viewport_size.y * 0.54:
		_fail("The combat command deck was not anchored to the bottom screen.")
		return
	if arena.lane_hud._action_rect.size.y > 250.0:
		_fail("The combat command deck is still too tall for the bottom strip.")
		return
	if (
		arena.lane_hud._selected_action_group != "movement"
		or arena.lane_hud._group_buttons.size() < 1
	):
		_fail("The out-of-range command deck did not default to movement.")
		return
	var enemy_opening_lane: int = arena.lane_manager._find_entity_lane(
		arena.enemy_core
	)
	arena.lane_manager.lane_slots[enemy_opening_lane].exit_slot(arena.enemy_core)
	arena.lane_manager.force_spawn_entity(arena.enemy_core, 8)
	arena.command_adapter.refresh_snapshot()
	await process_frame
	hud_snapshot = arena.lane_hud.get_snapshot()
	var shoot_descriptor := _find_action(
		hud_snapshot,
		GameEnums.ActionType.SHOOT
	)
	if shoot_descriptor.get("group", "") != "firearm":
		_fail("SHOOT was not grouped under the firearm command type.")
		return
	var aimed_descriptor := _find_action(
		hud_snapshot,
		GameEnums.ActionType.AIMED_SHOT
	)
	if aimed_descriptor.get("target_limbs", []).size() != 7:
		_fail("AIMED SHOT did not expose all visible Limb Region choices.")
		return
	if arena.lane_hud._selected_action_group != "firearm":
		_fail("The in-range command deck did not default to firearm actions.")
		return
	if not GUN_ANIMATION_CATALOG.has_weapon("service_pistol"):
		_fail("The gun animation catalog did not map the service pistol.")
		return
	if GUN_ANIMATION_CATALOG.texture("service_pistol", "shoot") == null:
		_fail("The service pistol did not load its Guns_Animation shot sprite.")
		return
	var aimed_root_button: CombatActionButton = null
	for button in arena.lane_hud._action_buttons:
		var payload: Dictionary = button.get_payload()
		var descriptor: Dictionary = payload.get("descriptor", {})
		if descriptor.get("action", -1) == GameEnums.ActionType.AIMED_SHOT:
			_fail("The firearm root still exposes per-limb AIMED SHOT spam.")
			return
		if (
			payload.get("mode", "") == "submenu"
			and payload.get("menu", "") == "aim"
		):
			aimed_root_button = button
	if aimed_root_button == null:
		_fail("The firearm group did not expose an AIM submenu.")
		return
	aimed_root_button.activate()
	await process_frame
	if arena.lane_hud._command_menu_path != ["aim"]:
		_fail("The AIM submenu did not open from the firearm root.")
		return
	var aimed_choice_count := 0
	for button in arena.lane_hud._action_buttons:
		var payload: Dictionary = button.get_payload()
		var descriptor: Dictionary = payload.get("descriptor", {})
		if descriptor.get("action", -1) == GameEnums.ActionType.AIMED_SHOT:
			aimed_choice_count += 1
			if payload.get("target_limbs", []).size() != 1:
				_fail("An AIM submenu choice was not bound to one limb.")
				return
	if aimed_choice_count != 7:
		_fail("The AIM submenu did not expose seven limb choices.")
		return
	if (
		arena.lane_hud._weapon_sprite.texture == null
		or not arena.lane_hud._weapon_sprite.region_enabled
		or arena.lane_hud._weapon_animation_frame_count <= 1
		or arena.lane_hud._weapon_sprite.region_rect.size.x
			>= arena.lane_hud._weapon_sprite.texture.get_width()
		or not str(arena.lane_hud._weapon_sprite.texture.resource_path).contains(
			"Asset/Guns_Animation"
		)
		or not arena.lane_hud._weapon_state_label.text.contains("READY")
		or not arena.lane_hud._weapon_detail_label.text.contains("AMMO 08/08")
	):
		_fail("The bottom weapon card did not render firearm state.")
		return
	if (
		not hud_snapshot.get("player", {}).has("ranged_weapon")
		or not hud_snapshot.get("player", {}).has("melee_weapon")
		or not hud_snapshot.get("enemy", {}).has("ranged_weapon")
		or not hud_snapshot.get("enemy", {}).has("melee_weapon")
	):
		_fail("Combat snapshots did not expose per-side ranged/melee weapons.")
		return
	if (
		not arena.lane_hud._player_top_label.visible
		or not arena.lane_hud._enemy_top_label.visible
		or not arena.lane_hud._player_top_label.text.contains("YOU")
		or not arena.lane_hud._enemy_top_label.text.contains("HOSTILE")
		or not arena.lane_hud._player_top_label.text.contains("AP")
		or not arena.lane_hud._player_top_label.text.contains("BLOOD")
		or not arena.lane_hud._player_top_label.text.contains("STANCE")
	):
		_fail("The top combat HUD did not render essential side summaries.")
		return
	if (
		arena.lane_hud._player_top_rect.size.y > 160.0
		or arena.lane_hud._enemy_top_rect.size.y > 160.0
	):
		_fail("The top combat HUD panels are too tall and can overlap the lane view.")
		return
	if (
		(arena.lane_hud._player_ranged_card.get("name") as Label).text.is_empty()
		or (arena.lane_hud._player_melee_card.get("name") as Label).text.is_empty()
		or (arena.lane_hud._enemy_ranged_card.get("name") as Label).text.is_empty()
		or (arena.lane_hud._enemy_melee_card.get("name") as Label).text.is_empty()
	):
		_fail("The top combat HUD did not render all weapon boxes.")
		return
	if arena.lane_hud._player_ranged_card.has("frame"):
		_fail("The top weapon boxes still render retired holder frame sprites.")
		return
	if arena.lane_hud._equipment_hover_box == null:
		_fail("The health section did not prepare an equipment hover card.")
		return
	var equipment_hover_text: String = arena.lane_hud._equipment_hover_text(
		hud_snapshot.get("player", {}),
		"YOU"
	)
	if (
		not equipment_hover_text.contains("YOU EQUIPMENT")
		or not equipment_hover_text.contains("RANGED")
		or not equipment_hover_text.contains("MELEE")
	):
		_fail("The health equipment hover card did not expose weapon sections.")
		return
	if (
		arena.lane_hud._command_context_rule == null
		or arena.lane_hud._command_context_rule.texture == null
		or not (arena.lane_hud._command_context_rule.texture is AtlasTexture)
	):
		_fail("The combat log did not render an official B&W divider element.")
		return
	var full_blood_fill_height: float = arena.lane_hud._player_portrait_plate.polygon[2].y
	var player_condition_atlas_path := ""
	if (
		arena.lane_hud._player_condition_sprite.texture != null
		and arena.lane_hud._player_condition_sprite.texture is AtlasTexture
	):
		player_condition_atlas_path = (
			arena.lane_hud._player_condition_sprite.texture as AtlasTexture
		).atlas.resource_path
	if (
		arena.lane_hud._player_condition_sprite.texture == null
		or arena.lane_hud._player_condition_sprite.region_enabled
		or not player_condition_atlas_path.contains(
			"B&W_UI_ByAndrox_FREE/HUD/counters_transparent.png"
		)
	):
		_fail("The player health section did not render a B&W condition icon.")
		return
	var player_body_row: Dictionary = arena.lane_hud._player_status_rows[0]
	var player_meter_frame := player_body_row.get("meter_frame") as Sprite2D
	var player_meter_atlas_path := ""
	if (
		player_meter_frame != null
		and player_meter_frame.texture != null
		and player_meter_frame.texture is AtlasTexture
	):
		player_meter_atlas_path = (player_meter_frame.texture as AtlasTexture).atlas.resource_path
	if (
		player_meter_frame == null
		or player_meter_frame.texture == null
		or not player_meter_atlas_path.contains("charge_bars")
	):
		_fail("The body health rows did not use the official segmented meter frame.")
		return
	if CombatLaneHUD.CONDITION_ANIMATION_FPS > 5.0:
		_fail("The Condition token animation is too fast for readable HUD use.")
		return
	if CombatLaneHUD.CONDITION_ANIMATION_FPS != 0.0:
		_fail("The Condition monitor should hold a stable frame during combat HUD display.")
		return
	var player_condition_data: Dictionary = arena.lane_hud.get_snapshot().get("player", {})
	arena.lane_hud._condition_animation_time = 0.01
	arena.lane_hud._apply_condition_frame(
		arena.lane_hud._player_condition_sprite,
		player_condition_data
	)
	var steady_condition_texture = arena.lane_hud._player_condition_sprite.texture
	var steady_condition_region = arena.lane_hud._player_condition_sprite.region_rect
	arena.lane_hud._condition_animation_time = 0.10
	arena.lane_hud._apply_condition_frame(
		arena.lane_hud._player_condition_sprite,
		player_condition_data
	)
	if (
		arena.lane_hud._player_condition_sprite.texture != steady_condition_texture
		or arena.lane_hud._player_condition_sprite.region_rect != steady_condition_region
	):
		_fail("The Condition token did not hold a readable frame between animation steps.")
		return
	if (
		arena.lane_hud._enemy_condition_sprite.texture == null
		or arena.lane_hud._enemy_condition_sprite.region_enabled
	):
		_fail("The enemy health section did not render a stable condition icon.")
		return
	player.body.blood_level = GameEnums.SCALE_MAX * 0.5
	arena.command_adapter.refresh_snapshot()
	await process_frame
	var half_blood_fill_height = arena.lane_hud._player_portrait_plate.polygon[2].y
	if half_blood_fill_height >= full_blood_fill_height:
		_fail("The player portrait blood backdrop did not track Blood level.")
		return
	player.body.blood_level = 2.0
	arena.command_adapter.refresh_snapshot()
	await process_frame
	if arena.lane_hud._player_condition_state.get("condition", "") != "danger":
		_fail("Critical Blood did not switch the Condition token to Danger.")
		return
	player.body.blood_level = GameEnums.SCALE_MAX
	arena.command_adapter.refresh_snapshot()
	await process_frame
	arena.lane_manager.lane_slots[8].exit_slot(arena.enemy_core)
	arena.lane_manager.force_spawn_entity(arena.enemy_core, enemy_opening_lane)
	arena.command_adapter.refresh_snapshot()
	await process_frame
	hud_snapshot = arena.lane_hud.get_snapshot()
	if (
		hud_snapshot.get("player", {}).get("appearance", {}).get(
			"signature",
			""
		).is_empty()
		or not arena.lane_hud._lane_view._player_token.visible
		or not arena.lane_hud._lane_view._enemy_token.visible
	):
		_fail("CombatLaneHUD did not project layered humanoid tokens.")
		return
	var visual_slots: Array = arena.lane_hud._lane_view._slot_nodes
	if visual_slots[2]._ground_sprite.texture == null:
		_fail("The duel grid did not load the plains ground texture.")
		return
	if visual_slots[5]._surface_sprite.texture == null:
		_fail("The duel grid did not load the mud surface texture.")
		return
	if visual_slots[4]._object_sprite.texture == null:
		_fail("The duel grid did not load the cover object texture.")
		return
	var shared_anchor_distance: float = visual_slots[5].get_actor_anchor(
		"player",
		true
	).distance_to(visual_slots[5].get_actor_anchor("enemy", true))
	if shared_anchor_distance < 48.0:
		_fail("Shared-lane token anchors are too close together.")
		return
	if (
		arena.lane_hud._lane_view._player_token.get_direction_row()
		!= HumanoidVisualCatalog.DIRECTION_RIGHT
		or arena.lane_hud._lane_view._enemy_token.get_direction_row()
		!= HumanoidVisualCatalog.DIRECTION_LEFT
	):
		_fail("Combat tokens did not face each other.")
		return
	for token in [
		arena.lane_hud._lane_view._player_token,
		arena.lane_hud._lane_view._enemy_token,
	]:
		if token._layer_sprites.is_empty():
			_fail("A combat token rendered without any sprite layers.")
			return
		for layer_sprite in token._layer_sprites:
			if layer_sprite.texture == null:
				_fail("A combat token layer did not load its texture.")
				return
	var required_animations := [
		"Idle", "Idle2", "Idle3", "Walk", "Run", "RunBackwards",
		"CrouchIdle", "CrouchRun", "Attack1", "Attack2", "Attack3",
		"Attack4", "StrafeLeft", "StrafeRight", "TakeDamage",
		"Taunt", "Die",
	]
	for animation in required_animations:
		if not HumanoidVisualCatalog.supports_animation(animation):
			_fail("The runtime catalog omitted " + animation + ".")
			return
	for discarded_animation in [
		"RunAttack",
		"RunBackwardsAttack",
		"StrafeLeftAttack",
		"StrafeRightAttack",
	]:
		if HumanoidVisualCatalog.supports_animation(discarded_animation):
			_fail("An unused moving-attack sheet entered the runtime contract.")
			return
	if hud_snapshot.get("player", {}).get("limbs", []).size() != 7:
		_fail("CombatLaneHUD did not receive all seven Limb Regions.")
		return
	if (
		arena.lane_hud._player_actor_hud.visible
		or arena.lane_hud._enemy_actor_hud.visible
	):
		_fail("The retired floating actor panels are still visible in duel layout.")
		return
	if (
		arena.lane_hud._player_status_rows.size() != 7
		or arena.lane_hud._enemy_status_rows.size() != 7
	):
		_fail("The bottom duel body panels did not create seven limb bars.")
		return
	if not arena.lane_hud._player_status_label.text.contains("YOU"):
		_fail("The player body panel did not render the player status title.")
		return
	if not arena.lane_hud._enemy_status_label.text.contains("HOSTILE"):
		_fail("The enemy body panel did not render the hostile status title.")
		return
	if (
		not arena.lane_hud._player_portrait_model.visible
		or not arena.lane_hud._enemy_portrait_model.visible
	):
		_fail("The duel portrait panels did not render inventory paperdolls.")
		return

	if not arena.lane_hud._player_label.text.contains("CORE HD"):
		_fail("CombatLaneHUD did not render the limb structure readout.")
		return
	if not arena.lane_hud._player_label.text.contains("08/08 R06"):
		_fail("CombatLaneHUD did not render firearm rounds and range.")
		return
	if not arena.lane_hud._player_label.text.contains("08/08 R06"):
		_fail("CombatLaneHUD did not render firearm rounds and range.")
		return
	if arena.lane_hud.is_showing_melee_lock():
		_fail("The lane HUD entered lock mode before combatants shared a slot.")
		return
	var player_token: HumanoidTokenView = (
		arena.lane_hud._lane_view._player_token
	)
	if player_token.get_animation() != "Idle2":
		_fail("A combat-ready token did not use the aggressive idle.")
		return
	player.body.limb_hp[GameEnums.LimbRegion.LEFT_LEG] = 0.0
	player.body.limb_hp[GameEnums.LimbRegion.RIGHT_LEG] = 0.0
	arena.command_adapter.refresh_snapshot()
	await process_frame
	var player_rows: Array = arena.lane_hud._player_status_rows
	var left_leg_fill := player_rows[5].get("fill") as Polygon2D
	var right_leg_fill := player_rows[6].get("fill") as Polygon2D
	var leg_wound := arena.lane_hud._player_portrait_model._decal_wound_nodes[
		"LEFT_LEG"
	] as TextureRect
	if (
		left_leg_fill == null
		or right_leg_fill == null
		or leg_wound == null
		or not leg_wound.visible
		or left_leg_fill.polygon[1].x > 3.0
		or right_leg_fill.polygon[1].x > 3.0
	):
		_fail("Disabled legs did not collapse bars and show paperdoll wounds.")
		return
	if (
		not arena.command_adapter.get_snapshot().get(
			"player",
			{}
		).get("both_legs_broken", false)
		or player_token.get_animation() != "CrouchIdle"
	):
		_fail("Two disabled legs did not force the crouched token pose.")
		return
	player.body.limb_hp[GameEnums.LimbRegion.LEFT_LEG] = (
		player.body.get_limb_max(GameEnums.LimbRegion.LEFT_LEG)
	)
	player.body.limb_hp[GameEnums.LimbRegion.RIGHT_LEG] = (
		player.body.get_limb_max(GameEnums.LimbRegion.RIGHT_LEG)
	)
	arena.command_adapter.refresh_snapshot()
	arena.lane_hud.show_presentation_event({
		"side": "player",
		"type": "action",
		"action": GameEnums.ActionType.SHOOT,
	})
	if not await _wait_for_animation(player_token, "Attack1"):
		_fail("SHOOT did not use Attack1.")
		return
	arena.lane_hud.show_presentation_event({
		"side": "player",
		"type": "action",
		"action": GameEnums.ActionType.GRAPPLE,
	})
	if not await _wait_for_animation(player_token, "Attack2"):
		_fail(
			"GRAPPLE did not use Attack2; got "
			+ player_token.get_animation()
			+ "."
		)
		return
	arena.lane_hud.show_presentation_event({
		"side": "player",
		"type": "action",
		"action": GameEnums.ActionType.STRIKE,
	})
	if not await _wait_for_animation(player_token, "Attack3"):
		_fail("The first STRIKE did not use the right swing.")
		return
	arena.lane_hud.show_presentation_event({
		"side": "player",
		"type": "action",
		"action": GameEnums.ActionType.STRIKE,
	})
	if not await _wait_for_animation(player_token, "Attack4"):
		_fail("The second STRIKE did not alternate to the left swing.")
		return
	arena.lane_hud.show_presentation_event({
		"side": "player",
		"type": "action",
		"action": GameEnums.ActionType.TAKE_COVER,
	})
	if not await _wait_for_animation(player_token, "StrafeRight"):
		_fail("TAKE COVER did not use a retained Strafe animation.")
		return
	arena.lane_hud.show_presentation_event({
		"side": "player",
		"type": "damage",
	})
	if not await _wait_for_animation(player_token, "TakeDamage"):
		_fail("Combat damage did not use TakeDamage.")
		return
	await create_timer(0.7).timeout
	player_token.play_animation("Idle2")
	var starting_token_position: Vector2 = player_token.position
	if not arena.lane_manager.move_entity(player, 2, 3):
		_fail("Combat lane movement setup could not move the player.")
		return
	await process_frame
	await create_timer(0.16).timeout
	if (
		player_token.get_animation() != "Run"
		or player_token.get_frame_index() < 1
		or player_token.position.is_equal_approx(starting_token_position)
	):
		_fail("Forward combat movement did not visibly use Run.")
		return
	await create_timer(
		CombatLaneView.LANE_MOVE_DURATION_SECONDS + 0.1
	).timeout
	if player_token.get_animation() != "Taunt":
		_fail("Firearm movement did not transition through the aiming pose.")
		return
	await create_timer(1.3).timeout
	if player_token.get_animation() != "Idle2":
		_fail("Firearm aiming did not return to the aggressive idle.")
		return
	if not arena.lane_manager.move_entity(player, 3, 2):
		_fail("Combat lane movement setup could not restore the player.")
		return
	await create_timer(0.16).timeout
	if player_token.get_animation() != "RunBackwards":
		_fail("Retreating combat movement did not use RunBackwards.")
		return
	await create_timer(
		CombatLaneView.LANE_MOVE_DURATION_SECONDS + 0.1
	).timeout
	if player_token.get_animation() != "Taunt":
		_fail("Retreating with a firearm did not reacquire aim.")
		return
	await create_timer(1.3).timeout

	player.stance_points = 4
	player._evaluate_stance_state()
	var turn_probe := CombatTurnManager.new()
	holder.add_child(turn_probe)
	turn_probe.combatants = [player]
	turn_probe.active_entity_index = 0
	var turn_events: Array = []
	var bleed_events: Array = []
	turn_probe.turn_started.connect(
		func(entity: HumanoidCore) -> void:
			turn_events.append(entity)
	)
	turn_probe.combat_bleed_tick.connect(
		func(entity: HumanoidCore, event: Dictionary) -> void:
			if entity == player:
				bleed_events.append(event)
	)
	player.body.blood_level = GameEnums.SCALE_MAX
	player.body.limb_trauma[GameEnums.LimbRegion.LEFT_ARM] = (
		GameEnums.TraumaType.BLEEDING
	)
	turn_probe._start_turn()
	if (
		turn_events.size() != 1
		or turn_events[0] != player
		or turn_probe.current_ap_pool != player.current_max_ap
		or player.current_stance != GameEnums.StanceState.STUMBLING
		or player.stance_points != 6
	):
		_fail("STUMBLING did not receive a normal AP turn with passive recovery.")
		return
	if (
		bleed_events.size() != 1
		or bleed_events[0].get("active_bleeds", 0) != 1
		or player.body.blood_level >= GameEnums.SCALE_MAX
	):
		_fail("Combat turn start did not process active bleeding.")
		return
	player.body.limb_trauma[GameEnums.LimbRegion.LEFT_ARM] = (
		GameEnums.TraumaType.NONE
	)
	player.body.blood_level = GameEnums.SCALE_MAX
	arena.command_adapter.refresh_snapshot()
	snapshot = arena.command_adapter.get_snapshot()
	if snapshot.get("actions", []).is_empty():
		_fail("A STUMBLING player received no legal combat actions.")
		return
	if player_token.get_animation() != "CrouchIdle":
		_fail("Stance 0-6 did not use CrouchIdle.")
		return
	if not arena.lane_manager.move_entity(player, 2, 3):
		_fail("Could not move the Stumbling token for animation coverage.")
		return
	await create_timer(0.16).timeout
	if player_token.get_animation() != "CrouchRun":
		_fail("A moving Stumbling token did not use CrouchRun.")
		return
	await create_timer(
		CombatLaneView.LANE_MOVE_DURATION_SECONDS + 0.05
	).timeout
	if player_token.get_animation() != "CrouchIdle":
		_fail("Impaired movement did not return to CrouchIdle.")
		return
	if not arena.lane_manager.move_entity(player, 3, 2):
		_fail("Could not restore the Stumbling token lane.")
		return
	await create_timer(
		CombatLaneView.LANE_MOVE_DURATION_SECONDS + 0.05
	).timeout
	turn_probe.halt_loop()
	turn_probe.queue_free()

	player.reset_stance()
	player.apply_stance_damage(GameEnums.SCALE_MAX)
	if (
		player.current_stance != GameEnums.StanceState.STUMBLING
		or player.stance_points != 1
	):
		_fail("Ordinary stance damage directly FELLED a combatant.")
		return

	arena.resolution_engine.execute_break(arena.enemy_core, player)
	if player.current_stance != GameEnums.StanceState.FELLED:
		_fail("BREAK could not finish a combatant who was already STUMBLING.")
		return

	var ai_get_up_probe := CombatAIEvaluator.new()
	ai_get_up_probe.ai_core = player
	var ai_get_up_action: int = ai_get_up_probe._evaluate_tactics()
	ai_get_up_probe.free()
	if ai_get_up_action != GameEnums.ActionType.GET_UP:
		_fail("AI did not prioritize GET UP while FELLED.")
		return

	arena.command_adapter.refresh_snapshot()
	snapshot = arena.command_adapter.get_snapshot()
	var felled_actions: Array = snapshot.get("actions", [])
	if arena.lane_hud._lane_view._player_token.get_animation() != "CrouchIdle":
		_fail("A FELLED combatant did not switch to the crouched token pose.")
		return
	if (
		felled_actions.size() != 1
		or not _snapshot_has_action(snapshot, GameEnums.ActionType.GET_UP)
		or snapshot.get("can_pass", true)
	):
		_fail("A FELLED player was not restricted to GET UP.")
		return

	var get_up_probe := CombatTurnManager.new()
	holder.add_child(get_up_probe)
	get_up_probe.combatants = [player]
	get_up_probe.active_entity_index = 0
	var get_up_turn_events: Array = []
	get_up_probe.turn_started.connect(
		func(entity: HumanoidCore) -> void:
			get_up_turn_events.append(entity)
	)
	get_up_probe._start_turn()
	if (
		get_up_turn_events.size() != 1
		or get_up_probe.current_ap_pool != player.current_max_ap
		or player.current_stance != GameEnums.StanceState.FELLED
	):
		_fail("A FELLED combatant did not receive an actionable GET UP turn.")
		return
	if not get_up_probe.request_action(player, GameEnums.ActionType.GET_UP):
		_fail("The turn manager rejected GET UP for a FELLED combatant.")
		return
	if not arena.resolution_engine.execute_get_up(player):
		_fail("GET UP did not restore the FELLED combatant.")
		return
	if (
		player.current_stance != GameEnums.StanceState.STUMBLING
		or player.stance_points != CombatRules.FELLED_RECOVERY_POINTS
		or not player.has_stance_recovery_guard
	):
		_fail("GET UP restored an invalid stance state.")
		return
	get_up_probe.halt_loop()
	get_up_probe.queue_free()

	player.expire_stance_recovery_guard()
	player.try_fell()
	player.begin_felled_recovery(CombatRules.FELLED_RECOVERY_POINTS)
	for _hit in range(4):
		player.apply_stance_damage(GameEnums.SCALE_MAX)
	if (
		player.current_stance != GameEnums.StanceState.STUMBLING
		or player.stance_points != 1
		or not player.has_stance_recovery_guard
	):
		_fail("Repeated pressure bypassed the post-Felled Recovery Guard.")
		return
	if player.try_fell():
		_fail("A forced knockdown bypassed the post-Felled Recovery Guard.")
		return
	arena.command_adapter.refresh_snapshot()
	snapshot = arena.command_adapter.get_snapshot()
	if not snapshot.get("player", {}).get(
		"stance_recovery_guard",
		false
	):
		_fail("The combat snapshot did not expose the Recovery Guard.")
		return
	player.recover_stance(CombatRules.STUMBLING_TURN_RECOVERY)
	player.expire_stance_recovery_guard()
	player.apply_stance_damage(GameEnums.SCALE_MAX)
	if (
		player.current_stance != GameEnums.StanceState.STUMBLING
		or player.stance_points != 1
	):
		_fail("Ordinary pressure bypassed the Stumbling floor.")
		return
	player.apply_stance_damage(GameEnums.SCALE_MAX, true)
	if player.current_stance != GameEnums.StanceState.FELLED:
		_fail("An explicit takedown could not reach FELLED.")
		return
	player.reset_stance()
	player.stance_points = 4
	player._evaluate_stance_state()
	arena.resolution_engine.execute_take_cover(player)
	if player.stance_points != 6:
		_fail("TAKE COVER did not brace and recover Stance.")
		return
	player.reset_stance()

	var enemy_lane: int = arena.lane_manager._find_entity_lane(arena.enemy_core)
	arena.lane_manager.remove_entity(player)
	arena.lane_manager.force_spawn_entity(player, enemy_lane)
	arena.lane_hud._apply_snapshot(arena.command_adapter.get_snapshot())
	await process_frame

	if not arena.lane_hud.is_showing_melee_lock():
		var adapter_lock_slot: Dictionary = (
			arena.command_adapter.get_snapshot().get("lane_slots", [])[enemy_lane]
		)
		_fail(
			"The lane HUD did not switch to the melee-lock overlay. "
			+ "Adapter lock="
			+ str(adapter_lock_slot.get("is_melee_locked", false))
			+ " occupants="
			+ str(adapter_lock_slot.get("occupants", []).size())
			+ "."
		)
		return
	var lock_snapshot: Dictionary = arena.lane_hud.get_snapshot()
	var lock_slot: Dictionary = lock_snapshot.get("lane_slots", [])[enemy_lane]
	if (
		not lock_slot.get("is_melee_locked", false)
		or lock_slot.get("occupants", []).size() != 2
	):
		_fail("The melee-lock projection did not preserve shared occupancy.")
		return
	var lock_player: Dictionary = lock_snapshot.get("player", {})
	var lock_melee_weapon: Dictionary = lock_player.get("melee_weapon", {})
	var expected_lock_weapon_name := (
		str(lock_melee_weapon.get("display_name", "MELEE")).to_upper()
		if not lock_melee_weapon.is_empty()
		else "UNARMED"
	)
	if arena.lane_hud._weapon_name_label.text != expected_lock_weapon_name:
		_fail("Melee Lock did not switch the active weapon card to the melee slot.")
		return
	if (
		not lock_melee_weapon.is_empty()
		and arena.lane_hud._weapon_sprite.visible
		and arena.lane_hud._weapon_sprite.region_enabled
	):
		_fail("Melee Lock rendered the melee weapon as an animated sprite sheet.")
		return

	snapshot = arena.command_adapter.get_snapshot()
	var strike_descriptor := _find_action(
		snapshot,
		GameEnums.ActionType.STRIKE
	)
	if strike_descriptor.is_empty():
		_fail("STRIKE was unavailable in a valid Melee Lock.")
		return
	if not strike_descriptor.get("target_limbs", []).is_empty():
		_fail("STRIKE still exposed manual limb targeting.")
		return
	if not _snapshot_has_action(snapshot, GameEnums.ActionType.PULL_FOLLOW):
		_fail("PULL was unavailable in a valid Melee Lock.")
		return
	if not _snapshot_has_action(snapshot, GameEnums.ActionType.PUSH_STAY):
		_fail("PUSH was unavailable in a valid Melee Lock.")
		return
	if _snapshot_has_action(snapshot, GameEnums.ActionType.PUSH_FOLLOW):
		_fail("Deprecated PUSH / FOLLOW appeared in legal Melee Lock actions.")
		return
	if _snapshot_has_action(snapshot, GameEnums.ActionType.PULL_STAY):
		_fail("Deprecated PULL / STAY appeared in legal Melee Lock actions.")
		return
	if _snapshot_has_action(snapshot, GameEnums.ActionType.DISENGAGE):
		_fail("Deprecated BREAK AWAY appeared in legal Melee Lock actions.")
		return
	var deprecated_ap_before: int = arena.turn_manager.current_ap_pool
	for deprecated_action in [
		GameEnums.ActionType.PUSH_FOLLOW,
		GameEnums.ActionType.PULL_STAY,
		GameEnums.ActionType.DISENGAGE,
	]:
		if arena.turn_manager.request_action(player, deprecated_action):
			_fail("Deprecated lock action was accepted by the turn manager.")
			return
		if arena.turn_manager.current_ap_pool != deprecated_ap_before:
			_fail("Rejected deprecated lock action still consumed AP.")
			return
	arena.lane_hud._selected_action_group = "melee"
	arena.lane_hud._action_group_locked_by_user = true
	arena.lane_hud._command_menu_path.clear()
	arena.lane_hud._render_actions()
	var push_root_button := _find_menu_button(arena.lane_hud, "push")
	if push_root_button != null:
		_fail("The melee group still exposes the removed PUSH submenu.")
		return
	var push_button := _find_action_button(
		arena.lane_hud,
		GameEnums.ActionType.PUSH_STAY
	)
	if push_button == null:
		_fail("The melee group did not expose direct PUSH.")
		return
	var pull_button := _find_action_button(
		arena.lane_hud,
		GameEnums.ActionType.PULL_FOLLOW
	)
	if pull_button == null:
		_fail("The melee group did not expose direct PULL.")
		return

	for _sample in range(120):
		var hit_region: GameEnums.LimbRegion = (
			arena.resolution_engine.roll_melee_target()
		)
		if hit_region == GameEnums.LimbRegion.HEAD:
			_fail("Random melee targeting selected the Head.")
			return

	player.definition.brawn = 6
	player.definition.finesse = 6
	arena.enemy_core.definition.brawn = 6
	arena.enemy_core.definition.finesse = 6
	player.reset_stance()
	arena.enemy_core.reset_stance()
	var losing_grapple: bool = arena.resolution_engine.execute_grapple(
		player,
		arena.enemy_core,
		1,
		12
	)
	if losing_grapple:
		_fail("A clearly losing opposed Grapple check succeeded.")
		return
	if arena.enemy_core.current_stance == GameEnums.StanceState.FELLED:
		_fail("A failed Grapple felled the defender.")
		return

	player.reset_stance()
	arena.enemy_core.reset_stance()
	var winning_grapple: bool = arena.resolution_engine.execute_grapple(
		player,
		arena.enemy_core,
		12,
		1
	)
	if not winning_grapple:
		_fail("A clearly winning opposed Grapple check failed.")
		return
	if (
		arena.enemy_core.current_stance != GameEnums.StanceState.FELLED
		or player.current_stance == GameEnums.StanceState.FELLED
	):
		_fail("Grapple success did not fell only the defender.")
		return

	arena.command_adapter.refresh_snapshot()
	snapshot = arena.command_adapter.get_snapshot()
	if _snapshot_has_action(snapshot, GameEnums.ActionType.EXECUTE):
		_fail("The disabled EXECUTE action appeared after a Grapple.")
		return
	var ap_before: int = arena.turn_manager.current_ap_pool
	if arena.turn_manager.request_action(player, GameEnums.ActionType.EXECUTE):
		_fail("The turn manager accepted disabled EXECUTE.")
		return
	if arena.turn_manager.current_ap_pool != ap_before:
		_fail("Rejected EXECUTE still consumed AP.")
		return

	player.reset_stance()
	arena.enemy_core.reset_stance()
	var pull_succeeded: bool = (
		arena.resolution_engine.execute_leverage_check(
			player,
			arena.enemy_core,
			false,
			12,
			1
		)
	)
	if not pull_succeeded:
		_fail("The deterministic Pull leverage check failed.")
		return
	arena.lane_manager.resolve_displacement(
		player,
		arena.enemy_core,
		-1,
		true,
		"PULL"
	)
	if (
		arena.lane_manager._find_entity_lane(player) != enemy_lane - 1
		or arena.lane_manager._find_entity_lane(arena.enemy_core)
		!= enemy_lane - 1
	):
		_fail("PULL did not move both locked combatants rearward.")
		return

	arena.turn_manager.halt_loop()
	holder.queue_free()
	await process_frame
	print(
		"[TEST PASS] Combat HUD, Stance recovery safeguards, melee targeting, "
		+ "Grapple, Execute gating, and Pull obey the demo rules."
	)
	quit(0)

func _slot_has_side(slot: Dictionary, side: String) -> bool:
	for occupant in slot.get("occupants", []):
		if occupant.get("side", "") == side:
			return true
	return false

func _wait_for_animation(
	token: HumanoidTokenView,
	animation: String,
	frame_limit: int = 90
) -> bool:
	for _frame in range(frame_limit):
		if token.get_animation() == animation:
			return true
		await process_frame
	return token.get_animation() == animation

func _wait_for_hud_queue(hud: CombatLaneHUD, frame_limit: int = 240) -> bool:
	for _frame in range(frame_limit):
		if not hud._is_processing_queue and hud._presentation_queue.is_empty():
			return true
		await process_frame
	return not hud._is_processing_queue and hud._presentation_queue.is_empty()

func _snapshot_has_action(snapshot: Dictionary, action: int) -> bool:
	return not _find_action(snapshot, action).is_empty()

func _find_action(snapshot: Dictionary, action: int) -> Dictionary:
	for descriptor in snapshot.get("actions", []):
		if descriptor.get("action", -1) == action:
			return descriptor
	return {}

func _find_menu_button(hud: CombatLaneHUD, menu: String) -> CombatActionButton:
	for button in hud._action_buttons:
		var payload: Dictionary = button.get_payload()
		if (
			payload.get("mode", "") == "submenu"
			and payload.get("menu", "") == menu
		):
			return button
	return null

func _find_action_button(hud: CombatLaneHUD, action: int) -> CombatActionButton:
	for button in hud._action_buttons:
		var payload: Dictionary = button.get_payload()
		var descriptor: Dictionary = payload.get("descriptor", {})
		if int(descriptor.get("action", -1)) == action:
			return button
	return null

func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
