extends Node3D

const CHUNK_SIZE      = 8
const RENDER_DISTANCE = 3
const TILE_SIZE       = 2.0
const HEIGHT_SCALE    = 3.0
const BLOCK_H         = 1.5

var chunks       = {}   # Vector2i -> Node3D (el chunk_node)
var alturas      = {}   # Vector2i (tile_x, tile_z) -> int altura modificada
var recolectados = {}   # Vector2i (tile_x, tile_z) -> true  (objeto ya fue cortado)
var player_chunk = Vector2i(999, 999)

var mat_top:   StandardMaterial3D
var mat_side:  StandardMaterial3D
var mat_dirt:  StandardMaterial3D
var mat_rock:  StandardMaterial3D

var noise: FastNoiseLite

# ── Cursores ─────────────────────────────────────────────────────────
var cursor_axe:  Texture2D
var cursor_pick: Texture2D
var hovered_resource: Node3D = null

# Para highlight del bloque de suelo hover
var hovered_tile_pos:  Vector3 = Vector3.INF
var hovered_place_pos: Vector3 = Vector3.INF   # dónde se colocaría un bloque (clic derecho)
var tile_highlight:    MeshInstance3D = null
var place_highlight:   MeshInstance3D = null

@onready var player: CharacterBody3D = get_node("Player")
var camera: Camera3D = null

# ── HUD / Inventario ─────────────────────────────────────────────────
var hud: CanvasLayer = null

func _ready() -> void:
	mat_top  = _mat(load("res://textures/grass_top.png"))
	mat_side = _mat(load("res://textures/grass_side.png"))
	if ResourceLoader.exists("res://textures/dirt.png"):
		mat_dirt = _mat(load("res://textures/dirt.png"))
	else:
		mat_dirt = mat_side
	if ResourceLoader.exists("res://textures/rock.png"):
		mat_rock = _mat_from_color(Color(0.5, 0.5, 0.5))
	else:
		mat_rock = mat_dirt

	camera = _find_camera(get_tree().root)

	if ResourceLoader.exists("res://textures/cursor_axe.png"):
		cursor_axe  = load("res://textures/cursor_axe.png")
	if ResourceLoader.exists("res://textures/cursor_pick.png"):
		cursor_pick = load("res://textures/cursor_pick.png")

	_crear_tile_highlight()
	_crear_place_highlight()

	# Cargar HUD
	if ResourceLoader.exists("res://HUD.tscn"):
		var hud_scene = load("res://HUD.tscn")
		hud = hud_scene.instantiate()
		add_child(hud)

	noise = FastNoiseLite.new()
	noise.seed               = randi()
	noise.noise_type         = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency          = 0.055
	noise.fractal_octaves    = 4
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain       = 0.5

	player_chunk = mundo_a_chunk(Vector3.ZERO)
	generar_chunks_cercanos()

	await get_tree().process_frame
	var h0 = altura_en(0.0, 0.0)
	player.global_position = Vector3(0.0, float(h0) * BLOCK_H + BLOCK_H + 1.0, 0.0)

func _find_camera(node: Node) -> Camera3D:
	if node is Camera3D: return node
	for child in node.get_children():
		var r = _find_camera(child)
		if r: return r
	return null

func _crear_tile_highlight() -> void:
	tile_highlight = MeshInstance3D.new()
	var quad = PlaneMesh.new()
	quad.size = Vector2(TILE_SIZE - 0.1, TILE_SIZE - 0.1)
	tile_highlight.mesh = quad
	var mat = StandardMaterial3D.new()
	mat.albedo_color  = Color(1.0, 0.9, 0.2, 0.45)
	mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = false
	tile_highlight.material_override = mat
	tile_highlight.visible = false
	add_child(tile_highlight)

func _crear_place_highlight() -> void:
	# Highlight azul semitransparente para indicar dónde se colocará un bloque
	place_highlight = MeshInstance3D.new()
	var quad = PlaneMesh.new()
	quad.size = Vector2(TILE_SIZE - 0.1, TILE_SIZE - 0.1)
	place_highlight.mesh = quad
	var mat = StandardMaterial3D.new()
	mat.albedo_color  = Color(0.2, 0.6, 1.0, 0.45)
	mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = false
	place_highlight.material_override = mat
	place_highlight.visible = false
	add_child(place_highlight)

func _process(_delta: float) -> void:
	var pc = mundo_a_chunk(player.global_position)
	if pc != player_chunk:
		player_chunk = pc
		generar_chunks_cercanos()
	if camera:
		_actualizar_cursor()

# ── CURSOR Y HOVER ────────────────────────────────────────────────────
func _actualizar_cursor() -> void:
	var mouse_pos  = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_end    = ray_origin + camera.project_ray_normal(mouse_pos) * 200.0

	var space  = get_world_3d().direct_space_state
	var params = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	params.collide_with_areas = false
	var result = space.intersect_ray(params)

	# Resetear highlights
	if hovered_resource != null and is_instance_valid(hovered_resource):
		_set_highlight(hovered_resource, false)
		hovered_resource = null

	tile_highlight.visible  = false
	place_highlight.visible = false
	hovered_tile_pos  = Vector3.INF
	hovered_place_pos = Vector3.INF

	if result.is_empty():
		Input.set_custom_mouse_cursor(null)
		return

	var collider = result["collider"]
	var body = collider if collider is StaticBody3D else collider.get_parent()
	if body == null:
		Input.set_custom_mouse_cursor(null)
		return

	var tipo = body.get_meta("tipo", "")

	match tipo:
		"arbol":
			if cursor_axe:
				Input.set_custom_mouse_cursor(cursor_axe, Input.CURSOR_ARROW, Vector2(4, 28))
			hovered_resource = body
			_set_highlight(body, true)

		"roca":
			if cursor_pick:
				Input.set_custom_mouse_cursor(cursor_pick, Input.CURSOR_ARROW, Vector2(2, 8))
			hovered_resource = body
			_set_highlight(body, true)

		_:
			var hit_pos = result["position"]
			var tx = int(floor(hit_pos.x / TILE_SIZE + 0.5))
			var tz = int(floor(hit_pos.z / TILE_SIZE + 0.5))
			var h  = altura_en(float(tx) * TILE_SIZE, float(tz) * TILE_SIZE)

			var tiene_bloque_activo = hud != null and hud.item_activo() in ["tierra", "cesped", "piedra", "madera"]

			if h > 0:
				if cursor_pick:
					Input.set_custom_mouse_cursor(cursor_pick, Input.CURSOR_ARROW, Vector2(2, 8))
				var top_y = float(h) * BLOCK_H + BLOCK_H + 0.02
				tile_highlight.global_position = Vector3(float(tx) * TILE_SIZE, top_y, float(tz) * TILE_SIZE)
				tile_highlight.visible = true
				hovered_tile_pos = Vector3(float(tx) * TILE_SIZE, 0, float(tz) * TILE_SIZE)

			# Highlight de colocación (encima del tile apuntado)
			if tiene_bloque_activo:
				var place_y = float(h + 1) * BLOCK_H + BLOCK_H + 0.02
				place_highlight.global_position = Vector3(float(tx) * TILE_SIZE, place_y, float(tz) * TILE_SIZE)
				place_highlight.visible = true
				hovered_place_pos = Vector3(float(tx) * TILE_SIZE, 0, float(tz) * TILE_SIZE)
			else:
				if h <= 0:
					Input.set_custom_mouse_cursor(null)

func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return

	# ── Clic izquierdo: recolectar o picar ───────────────────────────
	if event.button_index == MOUSE_BUTTON_LEFT:
		if hovered_resource != null and is_instance_valid(hovered_resource):
			_recolectar(hovered_resource)
			hovered_resource = null
			Input.set_custom_mouse_cursor(null)
			return
		if hovered_tile_pos != Vector3.INF:
			_picar_bloque(hovered_tile_pos.x, hovered_tile_pos.z)

	# ── Clic derecho: colocar bloque ─────────────────────────────────
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if hud == null:
			return
		var tipo_activo = hud.item_activo()
		if tipo_activo == "":
			return
		if hovered_place_pos != Vector3.INF:
			_colocar_bloque(hovered_place_pos.x, hovered_place_pos.z, tipo_activo)

# ── PICAR BLOQUE ─────────────────────────────────────────────────────
func _picar_bloque(wx: float, wz: float) -> void:
	var tile_key = Vector2i(int(round(wx / TILE_SIZE)), int(round(wz / TILE_SIZE)))
	var h_actual = altura_en(wx, wz)
	if h_actual <= 0:
		return

	alturas[tile_key] = h_actual - 1

	# Agregar tierra al inventario
	if hud != null:
		hud.agregar_item("tierra")

	_regenerar_chunk_y_vecinos(wx, wz)
	tile_highlight.visible  = false
	place_highlight.visible = false
	hovered_tile_pos  = Vector3.INF
	hovered_place_pos = Vector3.INF
	print("Picado bloque en (", wx, ",", wz, ") nueva altura: ", h_actual - 1)

# ── COLOCAR BLOQUE ───────────────────────────────────────────────────
func _colocar_bloque(wx: float, wz: float, _tipo: String) -> void:
	var tile_key = Vector2i(int(round(wx / TILE_SIZE)), int(round(wz / TILE_SIZE)))
	var h_actual = altura_en(wx, wz)

	# Consumir ítem del inventario
	if hud != null:
		hud.quitar_item_activo()

	alturas[tile_key] = h_actual + 1

	# Si el tile estaba en recolectados, quitarlo para que pueda tener objetos de nuevo
	if recolectados.has(tile_key):
		recolectados.erase(tile_key)

	_regenerar_chunk_y_vecinos(wx, wz)
	tile_highlight.visible  = false
	place_highlight.visible = false
	hovered_tile_pos  = Vector3.INF
	hovered_place_pos = Vector3.INF
	print("Colocado bloque en (", wx, ",", wz, ") nueva altura: ", h_actual + 1)

func _regenerar_chunk_y_vecinos(wx: float, wz: float) -> void:
	var cx = int(floor(wx / (CHUNK_SIZE * TILE_SIZE)))
	var cz = int(floor(wz / (CHUNK_SIZE * TILE_SIZE)))
	_regenerar_chunk(cx, cz)
	var tile_x_in_chunk = int(floor(wx / TILE_SIZE)) - cx * CHUNK_SIZE
	var tile_z_in_chunk = int(floor(wz / TILE_SIZE)) - cz * CHUNK_SIZE
	if tile_x_in_chunk == 0:            _regenerar_chunk(cx - 1, cz)
	if tile_x_in_chunk == CHUNK_SIZE-1: _regenerar_chunk(cx + 1, cz)
	if tile_z_in_chunk == 0:            _regenerar_chunk(cx, cz - 1)
	if tile_z_in_chunk == CHUNK_SIZE-1: _regenerar_chunk(cx, cz + 1)

func _regenerar_chunk(cx: int, cz: int) -> void:
	var key = Vector2i(cx, cz)
	if not chunks.has(key):
		return
	var old = chunks[key]
	if is_instance_valid(old):
		old.queue_free()
	chunks.erase(key)
	chunks[key] = true
	generar_chunk(cx, cz)

func _recolectar(body: Node3D) -> void:
	var tipo = body.get_meta("tipo", "")
	var pos  = body.global_position
	var tile_key = Vector2i(int(round(pos.x / TILE_SIZE)), int(round(pos.z / TILE_SIZE)))
	recolectados[tile_key] = true

	# Agregar al inventario según tipo
	if hud != null:
		match tipo:
			"arbol": hud.agregar_item("madera")
			"roca":  hud.agregar_item("piedra")

	var tween = create_tween()
	tween.tween_property(body, "scale", Vector3(0.01, 0.01, 0.01), 0.25)
	tween.tween_callback(body.queue_free)
	print("Recolectado: ", tipo)

func _set_highlight(body: Node3D, on: bool) -> void:
	for child in body.get_children():
		if child is Sprite3D:
			child.modulate = Color(1.4, 1.4, 0.6) if on else Color.WHITE

# ── HELPERS ───────────────────────────────────────────────────────────
func mundo_a_chunk(pos: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(pos.x / (CHUNK_SIZE * TILE_SIZE))),
		int(floor(pos.z / (CHUNK_SIZE * TILE_SIZE)))
	)

func altura_en(wx: float, wz: float) -> int:
	var tile_key = Vector2i(int(round(wx / TILE_SIZE)), int(round(wz / TILE_SIZE)))
	if alturas.has(tile_key):
		return alturas[tile_key]
	var n = noise.get_noise_2d(wx, wz)
	return max(0, int(floor((n * 0.5 + 0.5) * HEIGHT_SCALE)))

func _mat(tex: Texture2D) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color   = Color.WHITE
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.transparency   = BaseMaterial3D.TRANSPARENCY_DISABLED
	m.cull_mode      = BaseMaterial3D.CULL_DISABLED
	m.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func _mat_from_color(col: Color) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

# ── CHUNKS ────────────────────────────────────────────────────────────
func generar_chunks_cercanos() -> void:
	for cx in range(player_chunk.x - RENDER_DISTANCE, player_chunk.x + RENDER_DISTANCE + 1):
		for cz in range(player_chunk.y - RENDER_DISTANCE, player_chunk.y + RENDER_DISTANCE + 1):
			var key = Vector2i(cx, cz)
			if not chunks.has(key):
				chunks[key] = true
				generar_chunk(cx, cz)

func generar_chunk(cx: int, cz: int) -> void:
	var chunk_node = Node3D.new()
	chunk_node.name = "Chunk_%d_%d" % [cx, cz]

	var body = StaticBody3D.new()
	body.name = "TerrainBody"
	chunk_node.add_child(body)

	var st_top  = SurfaceTool.new()
	var st_side = SurfaceTool.new()
	st_top.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_side.begin(Mesh.PRIMITIVE_TRIANGLES)
	var side_verts = 0

	for x in range(CHUNK_SIZE):
		for z in range(CHUNK_SIZE):
			var wx = (cx * CHUNK_SIZE + x) * TILE_SIZE
			var wz = (cz * CHUNK_SIZE + z) * TILE_SIZE
			var h  = altura_en(wx, wz)

			var col   = CollisionShape3D.new()
			var shape = BoxShape3D.new()
			shape.size   = Vector3(TILE_SIZE, float(h + 1) * BLOCK_H, TILE_SIZE)
			col.shape    = shape
			col.position = Vector3(wx, float(h + 1) * BLOCK_H * 0.5, wz)
			body.add_child(col)

			var h_n = altura_en(wx,             wz - TILE_SIZE)
			var h_s = altura_en(wx,             wz + TILE_SIZE)
			var h_e = altura_en(wx + TILE_SIZE, wz)
			var h_o = altura_en(wx - TILE_SIZE, wz)

			for y in range(h + 1):
				var by = float(y) * BLOCK_H
				if y == h:
					_face_top(wx, by, wz, st_top)
				if y == 0:
					_face_bottom(wx, by, wz, st_side)
					side_verts += 1
				if h_n <= y:
					_face_side(wx, by, wz, 0, st_side); side_verts += 1
				if h_s <= y:
					_face_side(wx, by, wz, 1, st_side); side_verts += 1
				if h_e <= y:
					_face_side(wx, by, wz, 2, st_side); side_verts += 1
				if h_o <= y:
					_face_side(wx, by, wz, 3, st_side); side_verts += 1

			var tile_x = cx * CHUNK_SIZE + x
			var tile_z = cz * CHUNK_SIZE + z
			var tile_key_spawn = Vector2i(int(round(wx / TILE_SIZE)), int(round(wz / TILE_SIZE)))
			var fue_picado = alturas.has(tile_key_spawn)
			if h > 0 and not fue_picado and not recolectados.has(tile_key_spawn):
				var r = fmod(abs(sin(float(tile_x) * 127.1 + float(tile_z) * 311.7 + float(noise.seed))) * 43758.5453, 1.0)
				var sy = float(h) * BLOCK_H + BLOCK_H * 0.5 + 0.05
				if   r < 0.06: _arbol(   Vector3(wx, sy, wz), chunk_node)
				elif r < 0.10: _roca(    Vector3(wx, sy, wz), chunk_node)
				elif r < 0.12: _arbusto( Vector3(wx, sy, wz), chunk_node)

	st_top.generate_normals()
	st_top.set_material(mat_top)
	var mi_top = MeshInstance3D.new()
	mi_top.mesh = st_top.commit()
	chunk_node.add_child(mi_top)

	if side_verts > 0:
		st_side.generate_normals()
		st_side.set_material(mat_side)
		var mi_side = MeshInstance3D.new()
		mi_side.mesh = st_side.commit()
		chunk_node.add_child(mi_side)

	chunks[Vector2i(cx, cz)] = chunk_node
	add_child.call_deferred(chunk_node)

# ── CARAS ─────────────────────────────────────────────────────────────
func _face_top(wx: float, by: float, wz: float, st: SurfaceTool) -> void:
	var hw = TILE_SIZE * 0.5
	var y  = by + BLOCK_H
	st.set_normal(Vector3(0, 1, 0))
	st.set_uv(Vector2(0,0)); st.add_vertex(Vector3(wx-hw, y, wz-hw))
	st.set_uv(Vector2(1,0)); st.add_vertex(Vector3(wx+hw, y, wz-hw))
	st.set_uv(Vector2(1,1)); st.add_vertex(Vector3(wx+hw, y, wz+hw))
	st.set_uv(Vector2(0,0)); st.add_vertex(Vector3(wx-hw, y, wz-hw))
	st.set_uv(Vector2(1,1)); st.add_vertex(Vector3(wx+hw, y, wz+hw))
	st.set_uv(Vector2(0,1)); st.add_vertex(Vector3(wx-hw, y, wz+hw))

func _face_bottom(wx: float, by: float, wz: float, st: SurfaceTool) -> void:
	var hw = TILE_SIZE * 0.5
	var y  = by
	st.set_normal(Vector3(0, -1, 0))
	st.set_uv(Vector2(0,0)); st.add_vertex(Vector3(wx-hw, y, wz-hw))
	st.set_uv(Vector2(0,1)); st.add_vertex(Vector3(wx-hw, y, wz+hw))
	st.set_uv(Vector2(1,1)); st.add_vertex(Vector3(wx+hw, y, wz+hw))
	st.set_uv(Vector2(0,0)); st.add_vertex(Vector3(wx-hw, y, wz-hw))
	st.set_uv(Vector2(1,1)); st.add_vertex(Vector3(wx+hw, y, wz+hw))
	st.set_uv(Vector2(1,0)); st.add_vertex(Vector3(wx+hw, y, wz-hw))

func _face_side(wx: float, by: float, wz: float, dir: int, st: SurfaceTool) -> void:
	var hw = TILE_SIZE * 0.5
	var yb = by
	var yt = by + BLOCK_H
	match dir:
		0:
			st.set_normal(Vector3(0, 0, -1))
			st.set_uv(Vector2(0,0)); st.add_vertex(Vector3(wx-hw, yt, wz-hw))
			st.set_uv(Vector2(1,0)); st.add_vertex(Vector3(wx+hw, yt, wz-hw))
			st.set_uv(Vector2(1,1)); st.add_vertex(Vector3(wx+hw, yb, wz-hw))
			st.set_uv(Vector2(0,0)); st.add_vertex(Vector3(wx-hw, yt, wz-hw))
			st.set_uv(Vector2(1,1)); st.add_vertex(Vector3(wx+hw, yb, wz-hw))
			st.set_uv(Vector2(0,1)); st.add_vertex(Vector3(wx-hw, yb, wz-hw))
		1:
			st.set_normal(Vector3(0, 0, 1))
			st.set_uv(Vector2(0,0)); st.add_vertex(Vector3(wx+hw, yt, wz+hw))
			st.set_uv(Vector2(1,0)); st.add_vertex(Vector3(wx-hw, yt, wz+hw))
			st.set_uv(Vector2(1,1)); st.add_vertex(Vector3(wx-hw, yb, wz+hw))
			st.set_uv(Vector2(0,0)); st.add_vertex(Vector3(wx+hw, yt, wz+hw))
			st.set_uv(Vector2(1,1)); st.add_vertex(Vector3(wx-hw, yb, wz+hw))
			st.set_uv(Vector2(0,1)); st.add_vertex(Vector3(wx+hw, yb, wz+hw))
		2:
			st.set_normal(Vector3(1, 0, 0))
			st.set_uv(Vector2(0,0)); st.add_vertex(Vector3(wx+hw, yt, wz+hw))
			st.set_uv(Vector2(1,0)); st.add_vertex(Vector3(wx+hw, yt, wz-hw))
			st.set_uv(Vector2(1,1)); st.add_vertex(Vector3(wx+hw, yb, wz-hw))
			st.set_uv(Vector2(0,0)); st.add_vertex(Vector3(wx+hw, yt, wz+hw))
			st.set_uv(Vector2(1,1)); st.add_vertex(Vector3(wx+hw, yb, wz-hw))
			st.set_uv(Vector2(0,1)); st.add_vertex(Vector3(wx+hw, yb, wz+hw))
		3:
			st.set_normal(Vector3(-1, 0, 0))
			st.set_uv(Vector2(0,0)); st.add_vertex(Vector3(wx-hw, yt, wz-hw))
			st.set_uv(Vector2(1,0)); st.add_vertex(Vector3(wx-hw, yt, wz+hw))
			st.set_uv(Vector2(1,1)); st.add_vertex(Vector3(wx-hw, yb, wz+hw))
			st.set_uv(Vector2(0,0)); st.add_vertex(Vector3(wx-hw, yt, wz-hw))
			st.set_uv(Vector2(1,1)); st.add_vertex(Vector3(wx-hw, yb, wz+hw))
			st.set_uv(Vector2(0,1)); st.add_vertex(Vector3(wx-hw, yb, wz-hw))

# ── OBJETOS ───────────────────────────────────────────────────────────
func _arbol(pos: Vector3, parent: Node3D) -> void:
	var n = StaticBody3D.new()
	n.set_meta("tipo", "arbol")
	var c = CollisionShape3D.new()
	var s = CylinderShape3D.new()
	s.radius = 0.7; s.height = 5.0
	c.shape = s; c.position.y = 2.5; n.add_child(c)
	var sp = Sprite3D.new()
	sp.texture        = load("res://textures/tree.png")
	sp.pixel_size     = 0.10
	sp.billboard      = BaseMaterial3D.BILLBOARD_ENABLED
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.cast_shadow    = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	sp.position.y     = 3.5
	n.add_child(sp); n.position = pos; parent.add_child(n)

func _roca(pos: Vector3, parent: Node3D) -> void:
	var n = StaticBody3D.new()
	n.set_meta("tipo", "roca")
	var c = CollisionShape3D.new()
	var s = SphereShape3D.new()
	s.radius = 0.5; c.shape = s; c.position.y = 0.3; n.add_child(c)
	var sp = Sprite3D.new()
	sp.texture        = load("res://textures/rock.png")
	sp.pixel_size     = 0.04
	sp.billboard      = BaseMaterial3D.BILLBOARD_ENABLED
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.cast_shadow    = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	sp.position.y     = 1.0
	n.add_child(sp); n.position = pos; parent.add_child(n)

func _arbusto(pos: Vector3, parent: Node3D) -> void:
	var n = StaticBody3D.new()
	var c = CollisionShape3D.new()
	var s = SphereShape3D.new()
	s.radius = 0.4; c.shape = s; c.position.y = 0.4; n.add_child(c)
	var mi = MeshInstance3D.new()
	var ms = SphereMesh.new()
	var sz = 0.5 + randf() * 0.3
	ms.radius = sz; ms.height = sz * 1.1; mi.mesh = ms
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.18 + randf()*0.08, 0.52 + randf()*0.15, 0.08)
	mi.material_override = mat; mi.position.y = sz * 0.5
	n.add_child(mi); n.position = pos; parent.add_child(n)
