extends CanvasLayer

const SLOTS       = 9
const STACK_MAX   = 64

var inventario: Array = []
var slot_activo: int  = 0

var hotbar_panel: Panel
var slot_nodes:   Array = []
var iconos: Dictionary = {}

signal slot_cambiado(slot: int)

func _ready() -> void:
	for i in range(SLOTS):
		inventario.append({"tipo": "", "cantidad": 0, "icono": null})
	_cargar_iconos()
	_construir_hotbar()
	_actualizar_hotbar()

func _cargar_iconos() -> void:
	var rutas = {
		"madera": "res://textures/tree.png",
		"piedra": "res://textures/rock.png",
		"tierra": "res://textures/dirt.png",
		"cesped": "res://textures/grass_top.png",
	}
	for tipo in rutas:
		if ResourceLoader.exists(rutas[tipo]):
			iconos[tipo] = load(rutas[tipo])

func _construir_hotbar() -> void:
	var slot_size = 64
	var padding   = 6
	var bar_w     = SLOTS * (slot_size + padding) + padding
	var bar_h     = slot_size + padding * 2

	hotbar_panel = Panel.new()
	hotbar_panel.name = "Hotbar"
	hotbar_panel.size = Vector2(bar_w, bar_h)

	# Centrado abajo sin estirar
	hotbar_panel.anchor_left   = 0.5
	hotbar_panel.anchor_right  = 0.5
	hotbar_panel.anchor_top    = 1.0
	hotbar_panel.anchor_bottom = 1.0
	hotbar_panel.offset_left   = -bar_w / 2.0
	hotbar_panel.offset_right  =  bar_w / 2.0
	hotbar_panel.offset_top    = -bar_h - 8
	hotbar_panel.offset_bottom = -8

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color                   = Color(0.1, 0.1, 0.1, 0.75)
	panel_style.corner_radius_top_left     = 6
	panel_style.corner_radius_top_right    = 6
	panel_style.corner_radius_bottom_left  = 6
	panel_style.corner_radius_bottom_right = 6
	panel_style.border_width_top    = 0
	panel_style.border_width_bottom = 0
	panel_style.border_width_left   = 0
	panel_style.border_width_right  = 0
	hotbar_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(hotbar_panel)

	slot_nodes.clear()
	for i in range(SLOTS):
		var slot = _crear_slot(i, slot_size, padding)
		slot_nodes.append(slot)
		hotbar_panel.add_child(slot)

func _crear_slot(i: int, slot_size: int, padding: int) -> Control:
	var slot = Control.new()
	slot.name = "Slot%d" % i
	slot.size = Vector2(slot_size, slot_size)
	slot.position = Vector2(padding + i * (slot_size + padding), padding)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg = Panel.new()
	bg.name = "BG"
	bg.size = Vector2(slot_size, slot_size)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color                   = Color(0.25, 0.25, 0.25, 0.9)
	bg_style.border_color               = Color(0.5, 0.5, 0.5, 1.0)
	bg_style.border_width_top    = 2
	bg_style.border_width_bottom = 2
	bg_style.border_width_left   = 2
	bg_style.border_width_right  = 2
	bg_style.corner_radius_top_left     = 3
	bg_style.corner_radius_top_right    = 3
	bg_style.corner_radius_bottom_left  = 3
	bg_style.corner_radius_bottom_right = 3
	bg.add_theme_stylebox_override("panel", bg_style)
	slot.add_child(bg)

	var icon = TextureRect.new()
	icon.name = "Icon"
	icon.size = Vector2(slot_size - 8, slot_size - 8)
	icon.position = Vector2(4, 4)
	icon.expand_mode  = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(icon)

	var lbl = Label.new()
	lbl.name = "Cantidad"
	lbl.size = Vector2(slot_size, slot_size)
	lbl.position = Vector2(0, 0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(lbl)
	return slot

func _actualizar_hotbar() -> void:
	for i in range(SLOTS):
		var slot  = slot_nodes[i]
		var datos = inventario[i]
		var bg    = slot.get_node("BG")
		var icon  = slot.get_node("Icon")
		var lbl   = slot.get_node("Cantidad")
		var bg_style = StyleBoxFlat.new()
		if i == slot_activo:
			bg_style.bg_color     = Color(0.45, 0.35, 0.1, 0.95)
			bg_style.border_color = Color(1.0, 0.85, 0.2, 1.0)
		else:
			bg_style.bg_color     = Color(0.25, 0.25, 0.25, 0.9)
			bg_style.border_color = Color(0.5, 0.5, 0.5, 1.0)
		bg_style.border_width_top    = 2
		bg_style.border_width_bottom = 2
		bg_style.border_width_left   = 2
		bg_style.border_width_right  = 2
		bg_style.corner_radius_top_left     = 3
		bg_style.corner_radius_top_right    = 3
		bg_style.corner_radius_bottom_left  = 3
		bg_style.corner_radius_bottom_right = 3
		bg.add_theme_stylebox_override("panel", bg_style)
		if datos["tipo"] != "":
			icon.texture = iconos.get(datos["tipo"], null)
			icon.visible  = icon.texture != null
			lbl.text      = str(datos["cantidad"]) if datos["cantidad"] > 1 else ""
		else:
			icon.texture = null
			icon.visible  = false
			lbl.text      = ""

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			slot_activo = (slot_activo - 1 + SLOTS) % SLOTS
			_actualizar_hotbar()
			emit_signal("slot_cambiado", slot_activo)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			slot_activo = (slot_activo + 1) % SLOTS
			_actualizar_hotbar()
			emit_signal("slot_cambiado", slot_activo)
	if event is InputEventKey and event.pressed:
		for k in range(9):
			if event.keycode == KEY_1 + k:
				slot_activo = k
				_actualizar_hotbar()
				emit_signal("slot_cambiado", slot_activo)

func agregar_item(tipo: String) -> bool:
	for i in range(SLOTS):
		if inventario[i]["tipo"] == tipo and inventario[i]["cantidad"] < STACK_MAX:
			inventario[i]["cantidad"] += 1
			_actualizar_hotbar()
			return true
	for i in range(SLOTS):
		if inventario[i]["tipo"] == "":
			inventario[i]["tipo"]     = tipo
			inventario[i]["cantidad"] = 1
			inventario[i]["icono"]    = iconos.get(tipo, null)
			_actualizar_hotbar()
			return true
	return false

func quitar_item_activo() -> String:
	var d = inventario[slot_activo]
	if d["tipo"] == "":
		return ""
	var tipo = d["tipo"]
	d["cantidad"] -= 1
	if d["cantidad"] <= 0:
		d["tipo"]     = ""
		d["cantidad"] = 0
		d["icono"]    = null
	_actualizar_hotbar()
	return tipo

func item_activo() -> String:
	return inventario[slot_activo]["tipo"]
