class_name MenuManager extends Node

@export var savefile : SaveFileManager
@export var cursor : CursorManager
@export var animator_intro : AnimationPlayer
@export var speaker_music : AudioStreamPlayer2D
@export var speaker_start : AudioStreamPlayer2D
@export var buttons : Array[ButtonClass]
@export var buttons_options : Array[ButtonClass]
@export var screens : Array[Control]
@export var parent_main : Control
@export var parent_creds : Control
@export var parent_suboptions : Control
@export var parent_audiovideo : Control
@export var parent_language : Control
@export var parent_controller : Control
@export var parent_rebinding : Control
@export var title : Node3D
@export var waterfalls : Array[AnimationPlayer]
@export var optionmanager : OptionsManager
@export var controller : ControllerManager
@export var mouseblocker : Control
@export var anim_creds : AnimationPlayer

func _ready():
	SetupLan()
	Show("main")
	buttons[0].connect("is_pressed", Start)
	buttons[1].connect("is_pressed", SubOptions)
	buttons[2].connect("is_pressed", Credits)
	buttons[3].connect("is_pressed", Exit)
	buttons[4].connect("is_pressed", ReturnToLastScreen)
	buttons[5].connect("is_pressed", ReturnToLastScreen)
	buttons[6].connect("is_pressed", ReturnToLastScreen)
	buttons[7].connect("is_pressed", Options_AudioVideo)
	buttons[8].connect("is_pressed", Options_Language)
	buttons[9].connect("is_pressed", Options_Controller)
	buttons[10].connect("is_pressed", ReturnToLastScreen)
	buttons[11].connect("is_pressed", ReturnToLastScreen)
	buttons[16].connect("is_pressed", RebindControls)
	buttons[17].connect("is_pressed", ReturnToLastScreen)
	buttons[18].connect("is_pressed", ResetControls)
	
	buttons_options[0].connect("is_pressed", IncreaseVol)
	buttons_options[1].connect("is_pressed", DecreaseVol)
	buttons_options[2].connect("is_pressed", SetFull)
	buttons_options[3].connect("is_pressed", SetWindowed)
	buttons_options[4].connect("is_pressed", ControllerEnable)
	buttons_options[5].connect("is_pressed", ControllerDisable)
	
	Intro()

var failsafed = true
func _input(event):
	if (event.is_action_pressed("ui_cancel") && failsafed):
		if (currentScreen != "main"): ReturnToLastScreen()
	if (event.is_action_pressed("exit game") && failsafed):
		if (currentScreen != "main"): ReturnToLastScreen()

func Intro():
	cursor.SetCursor(false, false)
	await get_tree().create_timer(.5, false).timeout
	speaker_music.play()
	animator_intro.play("splash screen")
	await get_tree().create_timer(9, false).timeout
	mouseblocker.visible = false
	cursor.SetCursor(true, false)
	controller.settingFilter = true
	controller.SetMainControllerState(controller.controller_currently_enabled)
	if (cursor.controller_active): firstFocus_main.grab_focus()
	controller.previousFocus = firstFocus_main
	assigningFocus = true

# The LAN entry is added from code so menu.tscn stays untouched.
var lan_lobby : LanLobby
func SetupLan():
	var screen_main = parent_main
	var start_label : Label = screen_main.get_node("button_start")
	var start_button : Button = screen_main.get_node("true button_start")
	var options_button : Button = screen_main.get_node("true button_options")
	var row = 25.0
	# make room under START
	for what in ["options", "credits", "exit"]:
		screen_main.get_node("button_" + what).position.y += row
		screen_main.get_node("true button_" + what).position.y += row

	var label : Label = start_label.duplicate()
	label.name = "button_lan"
	label.text = "LAN"
	label.position.y += row
	screen_main.add_child(label)

	var button = Button.new()
	button.name = "true button_lan"
	button.modulate.a = 0
	button.position = Vector2(options_button.position.x, start_button.position.y + row)
	button.size = options_button.size
	button.scale = options_button.scale
	screen_main.add_child(button)

	var template : ButtonClass = start_button.get_node("button class_start")
	var logic = ButtonClass.new()
	logic.cursor = template.cursor
	logic.alias = "lan"
	logic.isActive = true
	logic.isDynamic = true
	logic.playing = true
	logic.ui = label
	logic.speaker_press = buttons[1].speaker_press
	logic.speaker_hover = template.speaker_hover
	logic.ui_opacity_active = template.ui_opacity_active
	button.add_child(logic)
	logic.connect("is_pressed", Lan)
	buttons.append(logic)
	if (!controller.buttons.has(logic) && controller.buttons.has(template)): controller.buttons.append(logic)

	start_button.focus_neighbor_bottom = start_button.get_path_to(button)
	options_button.focus_neighbor_top = options_button.get_path_to(button)
	button.focus_neighbor_top = button.get_path_to(start_button)
	button.focus_neighbor_bottom = button.get_path_to(options_button)

	lan_lobby = LanLobby.new()
	parent_main.get_parent().add_child(lan_lobby)
	parent_main.get_parent().move_child(lan_lobby, mouseblocker.get_index())
	lan_lobby.closed.connect(ReturnFromLan)

func Lan():
	ResetButtons()
	Buttons(false)
	parent_main.visible = false
	title.visible = false
	controller.previousFocus = null
	lan_lobby.Open()

func ReturnFromLan():
	Buttons(true)
	Show("main")
	ResetButtons()

func Buttons(state : bool):
	if (!state):
		for i in buttons:
			i.isActive = false
			i.SetFilter("ignore")
	else: 
		for i in buttons:
			i.isActive = true
			i.SetFilter("stop")

@export var firstFocus_main : Control
@export var firstFocus_subOptions : Control
@export var firstFocus_credits : Control
@export var firstFocus_audioVideo : Control
@export var firstFocus_language : Control
@export var firstFocus_controller : Control
@export var firstFocus_rebinding : Control

var assigningFocus = false
var lastScreen = "main"
var currentScreen = "main"
func Show(what : String):
	lastScreen = currentScreen
	currentScreen = what
	var focus
	title.visible = false
	for screen in screens: screen.visible = false
	if (what == "main" or what == "sub options"): title.visible = true
	match(what):
		"main":
			parent_main.visible = true
			focus = firstFocus_main
		"sub options":
			parent_suboptions.visible = true
			focus = firstFocus_subOptions
		"credits":
			parent_creds.visible = true
			focus = firstFocus_credits
			anim_creds.play("RESET")
			anim_creds.play("show credits")
		"audio video":
			parent_audiovideo.visible = true
			focus = firstFocus_audioVideo
		"language":
			parent_language.visible = true
			focus = firstFocus_language
		"controller":
			parent_controller.visible = true
			focus = firstFocus_controller
		"rebind controls":
			parent_rebinding.visible = true
			focus = firstFocus_rebinding
	if (assigningFocus):
		if (cursor.controller_active): focus.grab_focus()
		controller.previousFocus = focus

func ReturnToLastScreen():
	if (currentScreen) == "sub options": lastScreen = "main"
	if (currentScreen) == "rebind controls": lastScreen = "sub options"
	if (currentScreen == "audio video" or currentScreen == "language" or currentScreen == "controller" or currentScreen == "rebind controls"): optionmanager.SaveSettings()
	Show(lastScreen)
	ResetButtons()

func ResetButtons():
	#for b in buttons:
	#	b.ui.modulate.a = 1
	cursor.SetCursorImage("point")

func Start():
	Buttons(false)
	ResetButtons()
	for screen in screens: screen.visible = false
	title.visible = false
	controller.previousFocus = null
	speaker_music.stop()
	animator_intro.play("snap")
	for w in waterfalls: w.pause()
	speaker_start.play()
	cursor.SetCursor(false, false)
	savefile.ClearSave()
	await get_tree().create_timer(4, false).timeout
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func Credits():
	Show("credits")
	ResetButtons()

func Exit():
	Buttons(false)
	ResetButtons()
	speaker_music.stop()
	animator_intro.play("snap2")
	cursor.SetCursor(false, false)
	await get_tree().create_timer(.5, false).timeout
	get_tree().quit()

func ResetControls():
	optionmanager.ResetControls()
	ResetButtons()
func RebindControls():
	Show("rebind controls")
	ResetButtons()
func SubOptions():
	Show("sub options")
	ResetButtons()
func Options_AudioVideo():
	Show("audio video")
	ResetButtons()
func Options_Language():
	Show("language")
	ResetButtons()
func Options_Controller():
	Show("controller")
	ResetButtons()
	pass
func IncreaseVol():
	optionmanager.Adjust("increase")
func DecreaseVol():
	optionmanager.Adjust("decrease")
func SetWindowed():
	optionmanager.Adjust("windowed")
func SetFull():
	optionmanager.Adjust("fullscreen")
func ControllerEnable():
	optionmanager.Adjust("controller enable")
func ControllerDisable():
	optionmanager.Adjust("controller disable")
