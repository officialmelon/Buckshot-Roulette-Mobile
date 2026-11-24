class_name LanLobby extends Control
# LAN lobby: create / join / waiting room. Built in code, using the game's own
# shells, fonts and sounds, so menu.tscn does not need to change.

signal closed

const FONT_PAPER = preload("res://fonts/fake receipt.otf")
const FONT_LED = preload("res://fonts/DOTMATRI.TTF")
const SHELL = preload("res://instances/shell.tscn")

const SND_HOVER = preload("res://audio/button_hover.ogg")
const SND_PRESS = preload("res://audio/button press3.ogg")
const SND_LOAD = preload("res://audio/load single shell.ogg")
const SND_BEEP = preload("res://audio/health counter beep2.wav")
const SND_ERROR = preload("res://audio/health counter error1.ogg")
const SND_ENTER = preload("res://audio/kick door enter lobby.ogg")
const SND_HEART = preload("res://audio/heartbeat effect.ogg")

const WHITE = Color(0.88, 0.87, 0.84)
const DIM = Color(0.5, 0.49, 0.47)
const RED = Color(0.78, 0.13, 0.11)
const GREEN = Color(0.35, 0.95, 0.45)
const SHELL_COUNT := 6

var net : LanNet
var page : Control
var screen := "choose"

# join entry
var using_ip := false
var entry := ""
var entry_label : Label
var entry_status : Label
var connect_button : Button

# waiting room
var shells : Array[Node3D] = []
var shell_pivot : Node3D
var shells_loaded := 0
var load_timer := 0.0
var status_label : Label
var slot_labels : Array[Label] = []
var ping_label : Label
var dots_time := 0.0

func _ready():
	name = "LanLobby"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var shade = ColorRect.new()
	shade.color = Color(0.015, 0.008, 0.008, 0.86)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	net = LanNet.new()
	net.name = "net"
	add_child(net)
	net.connected.connect(_on_connected)
	net.failed.connect(_on_failed)
	net.peer_left.connect(_on_peer_left)
	net.ping_changed.connect(_on_ping)

	visible = false

func Open():
	visible = true
	ShowChoose()

func Leave():
	net.Close()
	_Clear()
	visible = false
	closed.emit()

func Back():
	_Sound(SND_PRESS)
	if (screen == "choose"): Leave()
	else:
		net.Close()
		ShowChoose()

func _input(event):
	if (!visible): return
	if (event.is_action_pressed("ui_cancel") || event.is_action_pressed("exit game")):
		get_viewport().set_input_as_handled()
		Back()

func _notification(what):
	# Android back button
	if (what == NOTIFICATION_WM_GO_BACK_REQUEST && visible): Back()

func _process(delta):
	if (!visible): return
	if (shell_pivot != null):
		for s in shells: s.rotate_y(delta * 0.9)
	if (screen == "waiting" || screen == "connecting"):
		dots_time += delta
		var dots = ".".repeat(int(dots_time * 2.0) % 4)
		if (status_label != null):
			var base = "WAITING FOR OPPONENT" if screen == "waiting" else "KNOCKING ON THE DOOR"
			status_label.text = base + dots
		# shells slide in one at a time, then the rack is emptied and refilled
		load_timer += delta
		if (load_timer >= 0.8):
			load_timer = 0.0
			if (shells_loaded >= SHELL_COUNT): _SetLoaded(0)
			else:
				_SetLoaded(shells_loaded + 1)
				_Sound(SND_LOAD, -14.0)

#SCREENS

func ShowChoose():
	_NewPage("choose")
	_Text("LOCAL NETWORK", FONT_PAPER, 40, WHITE, 34)
	_Text("two players  -  one shotgun  -  same wi-fi", FONT_PAPER, 18, DIM, 86)
	var host = _Button("CREATE ROOM", Rect2(165, 170, 300, 190), 30, _StartHost)
	var join = _Button("JOIN ROOM", Rect2(495, 170, 300, 190), 30, func(): ShowJoin())
	_Caption(host, "you get a room code")
	_Caption(join, "enter your friend's code")
	_Text("both phones must be on the same wi-fi or hotspot", FONT_PAPER, 16, DIM, 392)
	_Button("BACK", Rect2(380, 456, 200, 48), 22, Back)
	_Focus(host)

func _StartHost():
	if (!net.Host()):
		ShowError("COULD NOT OPEN A ROOM", "close other copies of the game and try again")
		return
	ShowWaiting()

func ShowWaiting():
	_NewPage("waiting")
	var ip = LanNet.LocalIP()
	_Text("ROOM OPEN", FONT_PAPER, 28, WHITE, 16)
	_Panel(Rect2(250, 58, 460, 122), GREEN)
	if (ip == ""):
		_Text("NO WI-FI", FONT_LED, 52, RED, 76)
		_Text("join wi-fi or a hotspot, then reopen", FONT_PAPER, 14, DIM, 146)
	else:
		var code = LanNet.EncodeIP(ip)
		_Text("ROOM CODE", FONT_PAPER, 14, DIM, 66)
		_Text(code.substr(0, 4) + "-" + code.substr(4), FONT_LED, 56, GREEN, 84)
		_Text("or by address:  " + ip, FONT_PAPER, 16, WHITE, 150)
	_BuildRack(Rect2(180, 190, 600, 130))
	status_label = _Text("WAITING FOR OPPONENT", FONT_PAPER, 20, WHITE, 326)
	_BuildSlots("YOU  (HOST)", "EMPTY CHAIR", false)
	_Button("CLOSE ROOM", Rect2(380, 470, 200, 46), 20, Back)

func ShowJoin():
	_NewPage("join")
	entry = ""
	_Text("JOIN ROOM", FONT_PAPER, 28, WHITE, 14)
	_Panel(Rect2(230, 56, 500, 80), GREEN)
	entry_label = _Text("", FONT_LED, 46, GREEN, 68)
	entry_status = _Text("", FONT_PAPER, 15, DIM, 142)

	var keys := []
	var columns := 8
	var key_size := Vector2(76, 50)
	if (using_ip):
		keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "<"]
		columns = 3
		key_size = Vector2(100, 56)
	else:
		for c in LanNet.CODE_CHARS: keys.append(c)
	var gap := 6
	var left = (960 - (columns * key_size.x + (columns - 1) * gap)) / 2.0
	var first : Button = null
	for i in range(keys.size()):
		var at = Vector2(left + (i % columns) * (key_size.x + gap), 170 + int(i / columns) * (key_size.y + gap))
		var key = _Button(keys[i], Rect2(at, key_size), 28, _Type.bind(keys[i]), FONT_LED)
		if (first == null): first = key

	_Button("BACK", Rect2(60, 456, 170, 52), 20, Back)
	_Button("USE CODE" if using_ip else "USE IP", Rect2(250, 456, 190, 52), 20, _SwitchMode)
	if (!using_ip): _Button("DELETE", Rect2(460, 456, 190, 52), 20, _Type.bind("<"))
	else: _Button("CLEAR", Rect2(460, 456, 190, 52), 20, _ClearEntry)
	connect_button = _Button("CONNECT", Rect2(670, 456, 230, 52), 24, _Connect)
	_RefreshEntry()
	_Focus(first)

func _SwitchMode():
	using_ip = !using_ip
	ShowJoin()

func _ClearEntry():
	entry = ""
	_RefreshEntry()

func _Type(key : String):
	if (key == "<"): entry = entry.substr(0, max(0, entry.length() - 1))
	elif (entry.length() < (15 if using_ip else LanNet.CODE_LENGTH)): entry += key
	_RefreshEntry()

func _TargetIP() -> String:
	if (using_ip):
		if (entry.split(".").size() == 4 && entry.is_valid_ip_address()): return entry
		return ""
	return LanNet.DecodeIP(entry)

func _RefreshEntry():
	if (using_ip):
		entry_label.text = entry if entry != "" else "---.---.-.-"
		entry_status.text = "type the host's ip address"
	else:
		var padded = entry + "-".repeat(LanNet.CODE_LENGTH - entry.length())
		entry_label.text = padded.substr(0, 4) + " " + padded.substr(4)
		entry_status.text = "type the 7 character room code"
		if (entry.length() == LanNet.CODE_LENGTH && _TargetIP() == ""):
			entry_status.text = "wrong code - check it again"
	connect_button.disabled = _TargetIP() == ""

func _Connect():
	var ip = _TargetIP()
	if (ip == ""): return
	if (!net.Join(ip)):
		ShowError("CONNECTION FAILED", "check that you are on the same wi-fi")
		return
	ShowConnecting(ip)

func ShowConnecting(ip : String):
	_NewPage("connecting")
	_Text("CONNECTING", FONT_PAPER, 30, WHITE, 60)
	_Text(ip, FONT_LED, 36, GREEN, 116)
	_BuildRack(Rect2(180, 185, 600, 140))
	status_label = _Text("KNOCKING ON THE DOOR", FONT_PAPER, 20, WHITE, 350)
	_Focus(_Button("CANCEL", Rect2(380, 456, 200, 48), 22, Back))

func ShowConnected():
	_NewPage("connected")
	_Text("CONNECTED", FONT_LED, 58, GREEN, 40)
	_Text("both players are at the table", FONT_PAPER, 18, DIM, 112)
	_BuildRack(Rect2(180, 165, 600, 140))
	_SetLoaded(SHELL_COUNT)
	if (net.is_host): _BuildSlots("YOU  (HOST)", "OPPONENT", true)
	else: _BuildSlots("HOST", "YOU", true)
	ping_label = _Text("PING --", FONT_LED, 22, WHITE, 420)
	_Text("the versus match arrives in the next update", FONT_PAPER, 14, DIM, 446)
	_Focus(_Button("LEAVE", Rect2(380, 474, 200, 44), 20, Back))

func ShowError(title : String, hint : String):
	_NewPage("error")
	_Sound(SND_ERROR)
	_Panel(Rect2(180, 150, 600, 170), RED)
	_Text(title, FONT_LED, 34, RED, 184)
	_Text(hint, FONT_PAPER, 16, WHITE, 262)
	_Focus(_Button("OK", Rect2(380, 380, 200, 52), 24, func(): ShowChoose()))

#NETWORK EVENTS

func _on_connected():
	_Sound(SND_ENTER)
	_Sound(SND_HEART, -6.0)
	Input.vibrate_handheld(120)
	ShowConnected()

func _on_failed(reason : String):
	ShowError(reason, "same wi-fi?  room still open?  local network allowed?")

func _on_peer_left():
	if (net.is_host):
		_Sound(SND_ERROR)
		ShowWaiting()
		status_label = null
		_Text("opponent left the table", FONT_PAPER, 14, RED, 352)
	else:
		ShowError("HOST LEFT", "the room was closed")

func _on_ping(ms : int):
	if (screen == "connected" && ping_label != null): ping_label.text = "PING " + str(ms) + " MS"

#BUILDING BLOCKS

func _NewPage(what : String):
	_Clear()
	screen = what
	page = Control.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page)

func _Clear():
	if (page != null): page.queue_free()
	page = null
	shell_pivot = null
	status_label = null
	ping_label = null
	entry_label = null
	shells.clear()
	slot_labels.clear()
	shells_loaded = 0
	load_timer = 0.0
	dots_time = 0.0

func _Text(text : String, font : Font, font_size : int, color : Color, y : float, x : float = 0, width : float = 960) -> Label:
	var label = Label.new()
	label.text = text
	label.position = Vector2(x, y)
	label.size = Vector2(width, font_size + 10)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(label)
	return label

func _Box(border : Color, fill : Color, width : int = 2) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	return box

func _Panel(rect : Rect2, color : Color) -> Panel:
	var panel = Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _Box(Color(color, 0.55), Color(0, 0, 0, 0.82)))
	page.add_child(panel)
	return panel

func _Button(text : String, rect : Rect2, font_size : int, action : Callable, font : Font = FONT_PAPER) -> Button:
	var button = Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", RED)
	button.add_theme_color_override("font_disabled_color", Color(DIM, 0.4))
	button.add_theme_stylebox_override("normal", _Box(Color(WHITE, 0.25), Color(0, 0, 0, 0.7)))
	button.add_theme_stylebox_override("hover", _Box(WHITE, Color(0.16, 0.04, 0.03, 0.9)))
	button.add_theme_stylebox_override("pressed", _Box(RED, Color(0.25, 0.03, 0.02, 0.95)))
	button.add_theme_stylebox_override("disabled", _Box(Color(WHITE, 0.1), Color(0, 0, 0, 0.5)))
	button.add_theme_stylebox_override("focus", _Box(WHITE, Color(0, 0, 0, 0)))
	button.mouse_entered.connect(func(): if (!button.disabled): _Sound(SND_HOVER, -8.0))
	button.pressed.connect(func():
		_Sound(SND_PRESS, -6.0)
		action.call())
	page.add_child(button)
	return button

func _Caption(button : Button, text : String):
	_Text(text, FONT_PAPER, 14, DIM, button.position.y + button.size.y - 34, button.position.x, button.size.x)

func _Focus(button : Button):
	# only for gamepads; touch screens should not show a highlighted button
	if (button != null && !Input.get_connected_joypads().is_empty()): button.grab_focus()

func _BuildSlots(left : String, right : String, ready_right : bool):
	var names = [left, right]
	var ready = [true, ready_right]
	for i in range(2):
		var x = 180 + i * 320
		_Panel(Rect2(x, 360, 280, 56), GREEN if ready[i] else DIM)
		slot_labels.append(_Text(names[i], FONT_PAPER, 17, WHITE if ready[i] else DIM, 366, x, 280))
		_Text("SIGNED IN" if ready[i] else "- - -", FONT_LED, 17, GREEN if ready[i] else DIM, 390, x, 280)
	_Text("VS", FONT_LED, 26, RED, 374)

# The game's real 3D shells, in their own little viewport.
func _BuildRack(rect : Rect2):
	var holder = SubViewportContainer.new()
	holder.position = rect.position
	holder.size = rect.size
	holder.stretch = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(holder)

	var view = SubViewport.new()
	view.own_world_3d = true
	view.transparent_bg = true
	view.msaa_3d = Viewport.MSAA_2X
	holder.add_child(view)

	var camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = 2.0
	camera.position = Vector3(0, 0.1, 5)
	view.add_child(camera)

	for side in [-1, 1]:
		var light = DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-25, 45 * side, 0)
		light.light_energy = 1.4 if side < 0 else 0.7
		light.light_color = Color(1, 0.92, 0.82) if side < 0 else Color(1, 0.35, 0.3)
		view.add_child(light)

	shell_pivot = Node3D.new()
	view.add_child(shell_pivot)

	# which shells are live is only decoration, shuffled every time
	var lives = [true, true, true, false, false, false]
	lives.shuffle()
	for i in range(SHELL_COUNT):
		var spin = Node3D.new()
		spin.position = Vector3((i - (SHELL_COUNT - 1) / 2.0) * 0.95, 0, 0)
		spin.rotation_degrees = Vector3(12, i * 40, 0)
		shell_pivot.add_child(spin)
		var shell = SHELL.instantiate()
		shell.transform = Transform3D(Basis.IDENTITY, Vector3(0, -0.1, 0))
		spin.add_child(shell)
		var branch = shell.get_node("shell branch") as ShellClass
		branch.isLive = lives[i]
		branch.ApplyStatus()
		shells.append(spin)
	_SetLoaded(0)

func _SetLoaded(count : int):
	shells_loaded = count
	for i in range(shells.size()):
		shells[i].visible = i < count

func _Sound(stream : AudioStream, volume : float = 0.0):
	var player = AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
