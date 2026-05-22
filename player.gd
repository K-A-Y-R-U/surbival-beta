extends CharacterBody3D

@export var speed: float = 5.0
@export var jump_force: float = 9.0   # era 7.0 — necesita 8.9 para saltar 1 bloque (BLOCK_H=1.5)
const GRAVITY: float = 20.0

@onready var cam_pivot = get_node("../Node3D")

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	if is_on_floor() and Input.is_action_just_pressed("ui_accept"):
		velocity.y = jump_force

	var dir = Vector3.ZERO
	if Input.is_key_pressed(KEY_W): dir.z -= 1
	if Input.is_key_pressed(KEY_S): dir.z += 1
	if Input.is_key_pressed(KEY_A): dir.x -= 1
	if Input.is_key_pressed(KEY_D): dir.x += 1

	if dir != Vector3.ZERO:
		dir = dir.normalized()
		dir = dir.rotated(Vector3.UP, cam_pivot.rotation.y)

	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	move_and_slide()
