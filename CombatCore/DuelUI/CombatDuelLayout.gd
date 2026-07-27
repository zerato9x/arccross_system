extends RefCounted
class_name CombatDuelLayout

var player_top_rect: Rect2 = Rect2()
var enemy_top_rect: Rect2 = Rect2()
var player_bottom_rect: Rect2 = Rect2()
var enemy_bottom_rect: Rect2 = Rect2()
var player_portrait_rect: Rect2 = Rect2()
var enemy_portrait_rect: Rect2 = Rect2()
var player_command_rect: Rect2 = Rect2()
var enemy_status_rect: Rect2 = Rect2()
var action_rect: Rect2 = Rect2()
var weapon_card_rect: Rect2 = Rect2()
var group_tabs_rect: Rect2 = Rect2()
var action_list_rect: Rect2 = Rect2()
var command_context_rect: Rect2 = Rect2()
var top_info_rect: Rect2 = Rect2()

func compute(
	viewport_size: Vector2,
	density: float,
	weapon_card_size: Vector2,
	command_context_size: Vector2,
	action_button_size: Vector2,
	action_button_gap: Vector2,
	group_button_size: Vector2
) -> void:
	var margin := maxf(18.0 * density, viewport_size.x * 0.014)
	var grid_center_y := viewport_size.y * 0.49
	var grid_height := clampf(viewport_size.y * 0.13, 82.0, 116.0)
	var grid_top := grid_center_y - grid_height * 0.5
	# Leave the command deck enough room to keep two real action columns at
	# 1280-wide viewports. The old quarter-screen side panels guaranteed overlap.
	var side_width := minf(500.0 * density, viewport_size.x * 0.22)
	var top_width := minf(390.0 * density, side_width)
	var top_height := clampf(
		viewport_size.y * 0.09,
		126.0 * density,
		152.0 * density
	)
	var bottom_height := clampf(
		viewport_size.y * 0.18,
		190.0 * density,
		236.0 * density
	)
	var bottom_y := viewport_size.y - margin - bottom_height
	var panel_gap := maxf(12.0 * density, viewport_size.x * 0.008)
	var action_width := maxf(
		420.0 * density,
		viewport_size.x - margin * 2.0 - side_width * 2.0 - panel_gap * 2.0
	)

	player_top_rect = Rect2(Vector2(margin, margin), Vector2(top_width, top_height))
	enemy_top_rect = Rect2(
		Vector2(viewport_size.x - margin - top_width, margin),
		Vector2(top_width, top_height)
	)
	player_bottom_rect = Rect2(
		Vector2(margin, bottom_y),
		Vector2(side_width, bottom_height)
	)
	enemy_bottom_rect = Rect2(
		Vector2(viewport_size.x - margin - side_width, bottom_y),
		Vector2(side_width, bottom_height)
	)
	action_rect = Rect2(
		Vector2(player_bottom_rect.end.x + panel_gap, bottom_y),
		Vector2(action_width, bottom_height)
	)

	var portrait_size := Vector2(
		minf(150.0 * density, side_width * 0.32),
		maxf(138.0 * density, bottom_height - 28.0 * density)
	)
	player_portrait_rect = Rect2(
		Vector2(
			player_bottom_rect.position.x + side_width * 0.58,
			player_bottom_rect.position.y + 14.0 * density
		),
		portrait_size
	)
	enemy_portrait_rect = Rect2(
		Vector2(
			enemy_bottom_rect.position.x + side_width * 0.58,
			enemy_bottom_rect.position.y + 14.0 * density
		),
		portrait_size
	)
	player_command_rect = Rect2(
		Vector2(
			player_bottom_rect.position.x
				+ maxf(24.0 * density, side_width * 0.08),
			player_bottom_rect.position.y + 18.0 * density
		),
		Vector2(
			210.0 * density,
			maxf(128.0 * density, bottom_height - 36.0 * density)
		)
	)
	enemy_status_rect = Rect2(
		Vector2(
			enemy_bottom_rect.position.x
				+ maxf(24.0 * density, side_width * 0.08),
			enemy_bottom_rect.position.y + 24.0 * density
		),
		Vector2(
			210.0 * density,
			maxf(124.0 * density, bottom_height - 42.0 * density)
		)
	)
	top_info_rect = Rect2(
		Vector2(
			viewport_size.x * 0.5 - 215.0 * density,
			margin
		),
		Vector2(430.0, 132.0) * density
	)
	var deck_padding := 16.0 * density
	var compact_command_deck := action_width < 900.0 * density
	var context_width := clampf(
		action_width * 0.34,
		300.0 * density,
		command_context_size.x * density
	)
	var weapon_width := minf(
		weapon_card_size.x * density,
		maxf(190.0 * density, action_width * 0.18)
	)
	weapon_card_rect = Rect2(
		action_rect.position + Vector2(deck_padding, 52.0 * density),
		Vector2(
			weapon_width,
			minf(
				weapon_card_size.y * density,
				bottom_height - 68.0 * density
			)
		)
	)
	command_context_rect = (
		Rect2(
			Vector2(
				viewport_size.x * 0.5 - 215.0 * density,
				margin + 146.0 * density
			),
			Vector2(430.0, 118.0) * density
		)
		if compact_command_deck
		else Rect2(
			Vector2(
				action_rect.end.x - deck_padding - context_width,
				action_rect.position.y + 18.0 * density
			),
			Vector2(
				context_width,
				minf(
					command_context_size.y * density,
					bottom_height - 36.0 * density
				)
			)
		)
	)
	var command_x := weapon_card_rect.end.x + 18.0 * density
	var command_width := maxf(
		(action_button_size.x * 2.0 + action_button_gap.x) * density,
		(
			action_rect.end.x - deck_padding - command_x
			if compact_command_deck
			else (
				command_context_rect.position.x
				- command_x
				- 18.0 * density
			)
		)
	)
	group_tabs_rect = Rect2(
		Vector2(command_x, action_rect.position.y + 48.0 * density),
		Vector2(
			command_width,
			(group_button_size.y + 4.0) * density
		)
	)
	action_list_rect = Rect2(
		Vector2(command_x, group_tabs_rect.end.y + 12.0 * density),
		Vector2(
			command_width,
			maxf(
				92.0 * density,
				action_rect.end.y
					- group_tabs_rect.end.y
					- 24.0 * density
			)
		)
	)
