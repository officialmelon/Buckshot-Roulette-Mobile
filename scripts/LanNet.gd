class_name LanNet extends Node
# LAN connection for two players (stage 1: connect only, no gameplay sync yet).
# The host is reached with a short room code that is simply its IPv4 address
# plus a checksum, so no UDP broadcast (and no special iOS entitlement) is needed.

const PORT := 24680
const PROTOCOL := 1
const JOIN_TIMEOUT := 10.0
const CODE_CHARS := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const CODE_LENGTH := 7

signal connected
signal failed(reason : String)
signal peer_left
signal ping_changed(ms : int)

enum State { IDLE, HOSTING, JOINING, CONNECTED }
var state : State = State.IDLE
var is_host := false

var _join_time := 0.0
var _ping_time := 0.0

func _ready():
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _exit_tree():
	Close()

func _process(delta):
	if (state == State.JOINING):
		_join_time += delta
		if (_join_time >= JOIN_TIMEOUT):
			_Fail("NO ANSWER FROM HOST")
	elif (state == State.CONNECTED && !is_host):
		_ping_time += delta
		if (_ping_time >= 1.0):
			_ping_time = 0.0
			_Ping.rpc_id(1, Time.get_ticks_msec())

func Host() -> bool:
	Close()
	var peer = ENetMultiplayerPeer.new()
	if (peer.create_server(PORT, 1) != OK): return false
	multiplayer.multiplayer_peer = peer
	is_host = true
	state = State.HOSTING
	return true

func Join(ip : String) -> bool:
	Close()
	var peer = ENetMultiplayerPeer.new()
	if (peer.create_client(ip, PORT) != OK): return false
	multiplayer.multiplayer_peer = peer
	is_host = false
	_join_time = 0.0
	state = State.JOINING
	return true

func Close():
	state = State.IDLE
	if (!is_inside_tree()): return
	var peer = multiplayer.multiplayer_peer
	if (peer is ENetMultiplayerPeer):
		peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

func _Fail(reason : String):
	Close()
	failed.emit(reason)

func _on_peer_connected(id : int):
	# The client introduces itself, the host checks that both builds match.
	if (!is_host): _Hello.rpc_id(1, PROTOCOL)

func _on_peer_disconnected(id : int):
	if (is_host && state == State.CONNECTED):
		state = State.HOSTING
		peer_left.emit()

func _on_connection_failed():
	if (state == State.JOINING): _Fail("CONNECTION FAILED")

func _on_server_disconnected():
	if (state == State.CONNECTED):
		Close()
		peer_left.emit()
	elif (state == State.JOINING):
		_Fail("ROOM CLOSED OR FULL")

@rpc("any_peer", "call_remote", "reliable")
func _Hello(version : int):
	if (!is_host): return
	var id = multiplayer.get_remote_sender_id()
	if (version != PROTOCOL):
		_Rejected.rpc_id(id)
		return
	state = State.CONNECTED
	_Welcome.rpc_id(id)
	connected.emit()

@rpc("authority", "call_remote", "reliable")
func _Welcome():
	state = State.CONNECTED
	_ping_time = 1.0
	connected.emit()

@rpc("authority", "call_remote", "reliable")
func _Rejected():
	_Fail("DIFFERENT GAME VERSION")

@rpc("any_peer", "call_remote", "unreliable")
func _Ping(sent : int):
	if (is_host): _Pong.rpc_id(multiplayer.get_remote_sender_id(), sent)

@rpc("authority", "call_remote", "unreliable")
func _Pong(sent : int):
	var ms = Time.get_ticks_msec() - sent
	ping_changed.emit(ms)
	_PingResult.rpc_id(1, ms)

@rpc("any_peer", "call_remote", "unreliable")
func _PingResult(ms : int):
	if (is_host): ping_changed.emit(ms)

#ADDRESSES AND ROOM CODES

static func IsPrivateIPv4(ip : String) -> bool:
	if (!ip.is_valid_ip_address() || ip.contains(":")): return false
	var p = ip.split(".")
	var a = int(p[0])
	var b = int(p[1])
	return a == 10 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b <= 31)

# Wi-Fi first, then hotspot, then anything else private (never cellular if avoidable).
static func LocalIP() -> String:
	var best := ""
	var best_rank := 99
	for iface in IP.get_local_interfaces():
		var iname : String = (str(iface.get("name", "")) + " " + str(iface.get("friendly", ""))).to_lower()
		var rank := 3
		if (iname.begins_with("en0") || iname.begins_with("wlan") || iname.contains("wi-fi")): rank = 0
		elif (iname.begins_with("bridge") || iname.begins_with("ap") || iname.begins_with("swlan")): rank = 1
		elif (iname.begins_with("en") || iname.begins_with("eth")): rank = 2
		elif (iname.begins_with("pdp") || iname.begins_with("rmnet") || iname.begins_with("ccmni") || iname.begins_with("utun") || iname.begins_with("tun") || iname.begins_with("docker")): rank = 8
		for address in iface.get("addresses", []):
			if (IsPrivateIPv4(address) && rank < best_rank):
				best = address
				best_rank = rank
	return best

static func EncodeIP(ip : String) -> String:
	var value := 0
	var sum := 0
	for part in ip.split("."):
		value = (value << 8) | int(part)
		sum += int(part)
	value = (value << 3) | (sum % 8)
	var code := ""
	for i in range(CODE_LENGTH):
		code = CODE_CHARS[value & 31] + code
		value >>= 5
	return code

# Returns "" when the code is not valid.
static func DecodeIP(code : String) -> String:
	if (code.length() != CODE_LENGTH): return ""
	var value := 0
	for c in code.to_upper():
		var index = CODE_CHARS.find(c)
		if (index < 0): return ""
		value = (value << 5) | index
	var check := value & 7
	value >>= 3
	if (value > 0xFFFFFFFF): return ""
	var parts := []
	var sum := 0
	for shift in [24, 16, 8, 0]:
		var part : int = (value >> shift) & 255
		parts.append(str(part))
		sum += part
	if (sum % 8 != check): return ""
	return ".".join(parts)
