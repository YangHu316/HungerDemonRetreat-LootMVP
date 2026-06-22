extends Control

func _draw() -> void:
	draw_arc(Vector2(0, -8), 16, 0, TAU, 32, Color.WHITE, 4.0)
	draw_line(Vector2(11, 8), Vector2(20, 16), Color.WHITE, 4.0)
