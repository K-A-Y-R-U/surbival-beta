extends Node3D

@onready var player = get_node("../Player")

var rotation_target: float = 0.0
var is_rotating: bool = false
const ROTATION_SPEED: float = 8.0

func _process(delta: float) -> void:
	# Seguir al jugador
	global_position = player.global_position
	
	# Rotar con Q y E
	if not is_rotating:
		if Input.is_key_pressed(KEY_Q):
			rotation_target += 90.0
			is_rotating = true
		elif Input.is_key_pressed(KEY_E):
			rotation_target -= 90.0
			is_rotating = true
	
	# Animación suave de rotación
	var current_deg = rad_to_deg(rotation.y)
	var diff = wrapf(rotation_target - current_deg, -180.0, 180.0)
	
	if abs(diff) < 0.5:
		rotation.y = deg_to_rad(rotation_target)
		is_rotating = false
	else:
		rotation.y += deg_to_rad(diff * ROTATION_SPEED * delta)
