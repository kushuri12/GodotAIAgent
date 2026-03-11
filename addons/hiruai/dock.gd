@tool
extends VBoxContainer
## Godot HiruAI Dock — Full project control.
## Reads, writes, deletes .gd/.tscn files. Animated file cards.
## Auto-read loop: AI reads files first, then edits intelligently.

# ──────────────────── Node References ────────────────────
var kimi: Node
var chat_container: VBoxContainer
var scroll: ScrollContainer
var input_field: TextEdit
var send_btn: Button
var status_label: Label
var toolbox_panel: VBoxContainer
var toolbox_btn: Button

# ──────────────────── Theme Colors (Premium Cursor Theme) ────────────────────
const C_BG_DEEP := Color("#0a0a0f") # Deepest background
const C_BG_SIDEBAR := Color("#0e0e16") # Sidebar / Tab area
const C_BORDER := Color("#1e1e2a") # Subtle borders
const C_ACCENT := Color("#a87ffb") # Soft neon purple
const C_ACCENT_ALT := Color("#00d1ff") # Electric Cyan
const C_TEXT := Color("#e0e0e6") # Main text
const C_TEXT_DIM := Color("#8e8e9c") # Dimmed text
const C_PANEL := Color("#12121e") # Card / Panel color

const C_SAVE := Color("#4ade80") # Success Green
const C_READ := Color("#3b82f6") # Info Blue
const C_DELETE := Color("#f87171") # Warning Red
const C_SYS := Color("#facc15") # System Yellow
const C_BTN_HOVER := Color("#252538")

# Aliases for backward compatibility
const C_BTN := Color("#1a1a2e")
const C_ERR := Color("#f87171")
const C_BG := Color("#0a0a0f")
const C_USER_BG := Color("#1a1a2e")
const C_AI_BG := Color("#0d0d14")
const C_USER := Color("#a5d6a7")
const C_AI := Color("#90caf9")
const C_CREATE := Color("#ab47bc")

# ──────────────────── UI State ────────────────────
var tabs: TabContainer
var chat_tab: VBoxContainer
var agent_tab: VBoxContainer
var project_tab: VBoxContainer
var history_tab: VBoxContainer
var model_status: Button
var _nav_buttons: Array[Button] = []
var _nav_indicator: ColorRect = null
var _nav_hbox: HBoxContainer = null
var _context_files: Array[String] = []
var _token_count_label: Label = null
var _total_tokens := 0
var _conversation_list: Array[Dictionary] = [] # {title, messages, timestamp}
var _current_conversation_title := ""
var _model_quick_btn: Button = null
var _attachments_bar: HBoxContainer = null
var _cmd_popup: PopupPanel = null
var _file_suggestion_popup: PopupPanel = null
var _undo_stack: Array[Dictionary] = [] # [{path, old_content, type}]

# ──────────────────── Agent State ────────────────────
var chat_history: Array = []
var _read_loop_count: int = 0
const MAX_READ_LOOPS := 15

var _pending_saves: Array[Dictionary] = []
var _pending_deletes: Array[String] = []
var _approval_panel: PanelContainer = null
var _tree_sent := false
var _read_files: Array[String] = []
var _self_healing_enabled := false
var _is_game_running_monitored := false

# ──────────────────── Streaming State ────────────────────
var _streaming_bubble: PanelContainer = null
var _streaming_content: RichTextLabel = null
var _streaming_raw_text := ""
var _activity_log: Array[Dictionary] = [] # {icon, text, color, timestamp}
var _activity_panel: PanelContainer = null
var _step_counter := 0
var _last_request_time := 0
var _thinking_duration_sec := 0


func _ready():
	custom_minimum_size = Vector2(120, 400)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	# Root Styling
	var bg = StyleBoxFlat.new()
	bg.bg_color = C_BG_DEEP
	add_theme_stylebox_override("panel", bg)
	
	_build_ui()
	_setup_kimi()
	_add_welcome()


# ══════════════════ KIMI SETUP ══════════════════

func _setup_kimi():
	# Kill existing to prevent signal duplication or memory leaks
	var existing = get_node_or_null("KimiClient")
	if existing: existing.queue_free()
	
	var KimiScript = load("res://addons/hiruai/kimi_client.gd")
	kimi = Node.new()
	kimi.set_script(KimiScript)
	kimi.name = "KimiClient"
	add_child(kimi)
	
	if not kimi.chat_completed.is_connected(_on_ai_response):
		kimi.chat_completed.connect(_on_ai_response)
	if not kimi.chat_error.is_connected(_on_ai_error):
		kimi.chat_error.connect(_on_ai_error)
	# Streaming signals
	if kimi.has_signal("stream_started"):
		kimi.stream_started.connect(_on_stream_started)
	if kimi.has_signal("token_received"):
		kimi.token_received.connect(_on_token_received)
	if kimi.has_signal("stream_finished"):
		kimi.stream_finished.connect(_on_stream_finished)
	
	# Update model button now that kimi is ready
	if _model_quick_btn and is_instance_valid(kimi) and "current_model" in kimi:
		_model_quick_btn.text = " ⚡ " + kimi.current_model.get_file().left(12)


# ══════════════════ UI CONSTRUCTION ══════════════════

func _build_ui():
	add_theme_constant_override("separation", 0)
	
	_build_nav_bar() # Premium Tab Nav with indicator
	
	# Main Content Area
	var content_wrap = PanelContainer.new()
	content_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_wrap.add_theme_stylebox_override("panel", _sb(C_BG_DEEP, 0))
	
	tabs = TabContainer.new()
	tabs.tabs_visible = false # We use custom nav bar
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	
	# TAB 1: Chat
	chat_tab = VBoxContainer.new()
	chat_tab.name = "Chat"
	_build_chat_area()
	tabs.add_child(chat_tab)
	
	# TAB 2: Agent
	agent_tab = VBoxContainer.new()
	agent_tab.name = "Agent"
	_build_agent_area()
	tabs.add_child(agent_tab)
	
	# TAB 3: Project
	project_tab = VBoxContainer.new()
	project_tab.name = "Project"
	_build_project_area()
	tabs.add_child(project_tab)
	
	# TAB 4: History
	history_tab = VBoxContainer.new()
	history_tab.name = "History"
	_build_history_area()
	tabs.add_child(history_tab)
	
	content_wrap.add_child(tabs)
	add_child(content_wrap)
	
	# Thin accent border instead of HSeparator
	var border = ColorRect.new()
	border.color = C_BORDER
	border.custom_minimum_size.y = 1
	add_child(border)
	
	_build_context_bar()
	_build_input_area()
	_build_toolbox_toggle()
	_build_action_buttons()


func _build_nav_bar():
	var bar = PanelContainer.new()
	bar.name = "NavBar"
	var style = _sb(C_BG_SIDEBAR, 0)
	style.content_margin_top = 6
	style.content_margin_bottom = 2
	style.content_margin_left = 8
	style.content_margin_right = 8
	bar.add_theme_stylebox_override("panel", style)
	
	var outer_vbox = VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 0)
	
	# Top row: tabs + model + settings
	_nav_hbox = HBoxContainer.new()
	_nav_hbox.add_theme_constant_override("separation", 0)
	
	_nav_buttons.clear()
	_add_nav_btn(_nav_hbox, "💬", 0)
	_add_nav_btn(_nav_hbox, "🤖", 1)
	_add_nav_btn(_nav_hbox, "📂", 2)
	_add_nav_btn(_nav_hbox, "📜", 3)
	
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_nav_hbox.add_child(spacer)
	
	# Quick model switcher button
	_model_quick_btn = Button.new()
	_model_quick_btn.name = "ModelQuickBtn"
	var model_name = "Model"
	if is_instance_valid(kimi) and "current_model" in kimi:
		model_name = kimi.current_model.get_file().left(12)
	_model_quick_btn.text = "⚡"
	_model_quick_btn.flat = true
	_model_quick_btn.add_theme_font_size_override("font_size", 11)
	_model_quick_btn.add_theme_color_override("font_color", C_ACCENT_ALT)
	_model_quick_btn.tooltip_text = "Quick switch AI model"
	_model_quick_btn.pressed.connect(_show_quick_model_menu)
	_model_quick_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_nav_hbox.add_child(_model_quick_btn)
	
	# Token counter
	_token_count_label = Label.new()
	_token_count_label.name = "TokenCount"
	_token_count_label.text = ""
	_token_count_label.add_theme_font_size_override("font_size", 10)
	_token_count_label.add_theme_color_override("font_color", C_TEXT_DIM)
	_token_count_label.tooltip_text = "Tokens used"
	_nav_hbox.add_child(_token_count_label)
	
	var settings_btn = Button.new()
	settings_btn.text = "⚙"
	settings_btn.flat = true
	settings_btn.add_theme_font_size_override("font_size", 14)
	settings_btn.add_theme_color_override("font_color", C_TEXT_DIM)
	settings_btn.add_theme_color_override("font_hover_color", C_ACCENT)
	settings_btn.pressed.connect(_show_settings)
	settings_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_nav_hbox.add_child(settings_btn)
	
	outer_vbox.add_child(_nav_hbox)
	
	# Animated underline indicator
	var indicator_bar = Control.new()
	indicator_bar.custom_minimum_size.y = 2
	_nav_indicator = ColorRect.new()
	_nav_indicator.name = "NavIndicator"
	_nav_indicator.color = C_ACCENT
	_nav_indicator.custom_minimum_size = Vector2(40, 2)
	_nav_indicator.position = Vector2(0, 0)
	indicator_bar.add_child(_nav_indicator)
	outer_vbox.add_child(indicator_bar)
	
	bar.add_child(outer_vbox)
	add_child(bar)
	
	# Set initial active state
	_update_nav_active(0)

func _add_nav_btn(parent, label: String, idx: int):
	var btn = Button.new()
	btn.text = label
	btn.flat = true
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", C_TEXT_DIM)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(func():
		tabs.current_tab = idx
		_update_nav_active(idx)
	)
	_nav_buttons.append(btn)
	parent.add_child(btn)

func _update_nav_active(idx: int):
	for i in _nav_buttons.size():
		var c = C_ACCENT if i == idx else C_TEXT_DIM
		_nav_buttons[i].add_theme_color_override("font_color", c)
	# Animate indicator
	if _nav_indicator and _nav_buttons.size() > idx:
		var target_btn = _nav_buttons[idx]
		var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(_nav_indicator, "position:x", target_btn.position.x, 0.25)
		tween.parallel().tween_property(_nav_indicator, "custom_minimum_size:x", target_btn.size.x, 0.25)

func _build_chat_area():
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	
	var chat_panel = PanelContainer.new()
	chat_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_panel.add_theme_stylebox_override("panel", _sb(C_BG_DEEP, 0))
	
	chat_container = VBoxContainer.new()
	chat_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_container.add_theme_constant_override("separation", 2)
	
	scroll.add_child(chat_container)
	chat_panel.add_child(scroll)
	chat_tab.add_child(chat_panel) # NOW ATTACHED TO TAB

func _build_agent_area():
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	var title = Label.new()
	title.text = "AGENT ACTIVITY"
	title.add_theme_color_override("font_color", C_ACCENT)
	title.add_theme_font_size_override("font_size", 11)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	
	var step_lbl = Label.new()
	step_lbl.name = "StepCount"
	step_lbl.text = "0 steps"
	step_lbl.add_theme_font_size_override("font_size", 9)
	step_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	header.add_child(step_lbl)
	vbox.add_child(header)
	
	_activity_panel = PanelContainer.new()
	_activity_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_activity_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	
	var activiy_scroll = ScrollContainer.new()
	activiy_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	var activity_list = VBoxContainer.new()
	activity_list.name = "ActivityList"
	activity_list.add_theme_constant_override("separation", 3)
	activiy_scroll.add_child(activity_list)
	_activity_panel.add_child(activiy_scroll)
	
	vbox.add_child(_activity_panel)
	margin.add_child(vbox)
	agent_tab.add_child(margin)

func _build_project_area():
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	var title = Label.new()
	title.text = "PROJECT CONTEXT"
	title.add_theme_color_override("font_color", C_ACCENT_ALT)
	title.add_theme_font_size_override("font_size", 11)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	
	var scan_btn = Button.new()
	scan_btn.text = "🔄 Scan"
	scan_btn.flat = true
	scan_btn.add_theme_font_size_override("font_size", 10)
	scan_btn.add_theme_color_override("font_color", C_ACCENT_ALT)
	scan_btn.pressed.connect(_on_scan)
	scan_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	header.add_child(scan_btn)
	vbox.add_child(header)
	
	var proj_scroll = ScrollContainer.new()
	proj_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	var stats = Label.new()
	stats.name = "FileStats"
	stats.text = "Click 🔄 Scan to analyze your project."
	stats.add_theme_font_size_override("font_size", 13)
	stats.add_theme_color_override("font_color", C_TEXT_DIM)
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	proj_scroll.add_child(stats)
	
	vbox.add_child(proj_scroll)
	margin.add_child(vbox)
	project_tab.add_child(margin)


func _build_input_area():
	var panel = PanelContainer.new()
	var p_style = _sb(C_PANEL, 0)
	p_style.content_margin_top = 6
	p_style.content_margin_bottom = 8
	p_style.content_margin_left = 8
	p_style.content_margin_right = 8
	panel.add_theme_stylebox_override("panel", p_style)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	
	# Attachments bar (hidden by default)
	_attachments_bar = HBoxContainer.new()
	_attachments_bar.name = "AttachmentsBar"
	_attachments_bar.visible = false
	_attachments_bar.add_theme_constant_override("separation", 4)
	vbox.add_child(_attachments_bar)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)

	input_field = TextEdit.new()
	input_field.placeholder_text = "Ask Hiru anything... (/ for commands, @ for files)"
	input_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_field.custom_minimum_size = Vector2(0, 50) # Starting height
	input_field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	input_field.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	input_field.scroll_fit_content_height = true # Auto-expand
	input_field.gui_input.connect(_on_input_gui_input)
	input_field.text_changed.connect(_on_input_text_changed)
	
	var style := _sb(Color("#0d0d18"), 10, true, C_ACCENT.darkened(0.6))
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	input_field.add_theme_stylebox_override("normal", style)
	input_field.add_theme_stylebox_override("focus", _sb(Color("#0d0d18"), 10, true, C_ACCENT))
	input_field.add_theme_color_override("font_color", C_TEXT)
	input_field.add_theme_color_override("font_placeholder_color", C_TEXT_DIM)
	input_field.add_theme_font_size_override("font_size", 15)
	
	# Send button with glow
	send_btn = Button.new()
	send_btn.text = " ➤ "
	send_btn.custom_minimum_size = Vector2(36, 36)
	send_btn.pressed.connect(_on_send_pressed)
	_style_btn(send_btn, C_ACCENT)

	var cancel_btn = Button.new()
	cancel_btn.name = "CancelBtn"
	cancel_btn.text = " ✖ "
	cancel_btn.visible = false
	cancel_btn.custom_minimum_size = Vector2(36, 36)
	cancel_btn.pressed.connect(_on_cancel_pressed)
	_style_btn(cancel_btn, C_ERR)

	hbox.add_child(input_field)
	hbox.add_child(send_btn)
	hbox.add_child(cancel_btn)
	vbox.add_child(hbox)
	
	# Shortcuts hint
	var hint = Label.new()
	hint.text = "Enter ↵ send • Shift+Enter ↵ new line • Ctrl+L clear"
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", Color(C_TEXT_DIM, 0.4))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)
	
	panel.add_child(vbox)
	add_child(panel)

func _build_toolbox_toggle():
	var bar = PanelContainer.new()
	var b_style = _sb(C_PANEL, 0)
	b_style.content_margin_top = 4
	b_style.content_margin_bottom = 4
	bar.add_theme_stylebox_override("panel", b_style)
	
	var hbox = HBoxContainer.new()
	
	toolbox_btn = Button.new()
	toolbox_btn.text = " 🛠️ Actions & Tools "
	toolbox_btn.flat = true
	toolbox_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toolbox_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbox_btn.toggle_mode = true
	toolbox_btn.toggled.connect(_on_toolbox_toggled)
	_style_btn(toolbox_btn, Color(0, 0, 0, 0.0))
	
	status_label = Label.new()
	status_label.text = "● Ready"
	status_label.add_theme_color_override("font_color", Color("#00ff88"))
	status_label.add_theme_font_size_override("font_size", 12)
	
	hbox.add_child(toolbox_btn)
	hbox.add_child(status_label)
	bar.add_child(hbox)
	add_child(bar)


func _build_action_buttons():
	toolbox_panel = VBoxContainer.new()
	toolbox_panel.visible = false
	toolbox_panel.add_theme_constant_override("separation", 4)
	var inner = PanelContainer.new()
	inner.add_theme_stylebox_override("panel", _sb(C_PANEL, 0))
	
	var rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	
	var row1 = HBoxContainer.new()
	row1.add_theme_constant_override("separation", 2)
	_add_action_btn(row1, "📝 Gen", "Generate: Create new GDScript from your prompt", _on_generate)
	_add_action_btn(row1, "🔧 Fix", "Auto-Fix: AI reads logs and fixes errors automatically", _on_fix)
	_add_action_btn(row1, "💡 Exp", "Explain: Get a clear explanation of code or logic", _on_explain)
	rows.add_child(row1)

	var row2 = HBoxContainer.new()
	row2.add_theme_constant_override("separation", 2)
	_add_action_btn(row2, "🧩 Node", "Create Node: Setup a new Scene and script hierarchy", _on_create_node)
	_add_action_btn(row2, "📂 Scan", "Scan: Refresh project file structure for AI context", _on_scan)
	_add_action_btn(row2, "🗑️ Clr", "Clear: Reset chat history and start fresh", _on_clear)
	rows.add_child(row2)

	var row3 = HBoxContainer.new()
	row3.add_theme_constant_override("separation", 2)
	_add_action_btn(row3, "▶️ Play", "Run Main: Launch the project's main scene", _on_play_main)
	_add_action_btn(row3, "🎬 Scene", "Run Scene: Launch the currently open scene", _on_play_current)
	_add_action_btn(row3, "⏹️ Stop", "Stop: Force stop the running game", _on_stop_game)
	rows.add_child(row3)
	
	var row4 = HBoxContainer.new()
	row4.add_theme_constant_override("separation", 2)
	var heal_btn = Button.new()
	heal_btn.name = "HealBtn"
	heal_btn.text = "🔁 Self-Healing: OFF"
	heal_btn.tooltip_text = "Self-Healing: AI monitors logs and auto-fixes bugs while you test"
	heal_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heal_btn.toggle_mode = true
	heal_btn.toggled.connect(_on_self_healing_toggled)
	_style_btn(heal_btn, Color("#2d1b69"))
	row4.add_child(heal_btn)
	rows.add_child(row4)
	
	inner.add_child(rows)
	toolbox_panel.add_child(inner)
	add_child(toolbox_panel)

func _on_toolbox_toggled(on: bool):
	toolbox_panel.visible = on
	toolbox_btn.text = " 👇 Actions & Tools " if on else " 🛠️ Actions & Tools "
	_scroll_bottom()


func _add_action_btn(parent: HBoxContainer, text: String, tip: String, callback: Callable):
	var btn = Button.new()
	btn.text = text
	btn.tooltip_text = tip
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(callback)
	_style_btn(btn)
	parent.add_child(btn)


# ══════════════════ STYLING ══════════════════

func _sb(color: Color, radius: int = 8, border: bool = false, b_color: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	if border:
		s.set_border_width_all(1)
		s.border_color = b_color if b_color != Color.TRANSPARENT else color.lightened(0.1)
		s.border_blend = true
	return s


func _style_btn(btn: Button, bg: Color = C_BTN):
	var radius := 6
	btn.add_theme_stylebox_override("normal", _sb(bg, radius, true, bg.lightened(0.1)))
	btn.add_theme_stylebox_override("hover", _sb(bg.lightened(0.15), radius, true, C_ACCENT))
	btn.add_theme_stylebox_override("pressed", _sb(bg.darkened(0.2), radius, true, C_ACCENT.lightened(0.3)))
	btn.add_theme_color_override("font_color", C_TEXT)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_font_size_override("font_size", 14)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


# ══════════════════ CHAT MESSAGES ══════════════════

func _add_msg(role: String, text: String):
	var bubble = PanelContainer.new()
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Role-specific styling
	var border_color = C_BORDER
	var bg_color = C_BG_DEEP
	var pcol: Color = C_TEXT
	var prefix: String = "✦ HIRU"
	
	match role:
		"user":
			prefix = "YOU"
			pcol = C_ACCENT_ALT
			border_color = C_ACCENT_ALT.darkened(0.6)
			bg_color = Color("#0f1018")
		"ai":
			prefix = "✦ HIRU"
			pcol = C_ACCENT
			border_color = C_ACCENT.darkened(0.5)
		"system":
			prefix = "SYSTEM"
			pcol = C_SYS
			border_color = C_SYS.darkened(0.7)
		"error":
			prefix = "ERROR"
			pcol = Color("#ff5555")
			border_color = Color("#ff5555").darkened(0.6)
	
	var bstyle = _sb(bg_color, 6, true, border_color)
	bstyle.border_width_left = 3
	bstyle.border_width_right = 0
	bstyle.border_width_top = 0
	bstyle.border_width_bottom = 0
	bstyle.content_margin_bottom = 10
	bstyle.content_margin_top = 8
	bstyle.content_margin_left = 14
	bstyle.content_margin_right = 12
	bubble.add_theme_stylebox_override("panel", bstyle)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)

	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	var sender = Label.new()
	sender.text = prefix
	sender.add_theme_color_override("font_color", pcol)
	sender.add_theme_font_size_override("font_size", 9)
	header.add_child(sender)
	
	var timestamp = Label.new()
	timestamp.text = Time.get_time_string_from_system().left(5)
	timestamp.add_theme_color_override("font_color", Color(C_TEXT_DIM, 0.4))
	timestamp.add_theme_font_size_override("font_size", 8)
	header.add_child(timestamp)
	
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	
	var copy_btn = Button.new()
	copy_btn.text = "📋"
	copy_btn.flat = true
	copy_btn.add_theme_font_size_override("font_size", 9)
	copy_btn.add_theme_color_override("font_color", C_TEXT_DIM)
	copy_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	copy_btn.tooltip_text = "Copy message"
	copy_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	copy_btn.pressed.connect(func():
		DisplayServer.clipboard_set(text)
		copy_btn.text = "✅"
		await get_tree().create_timer(2.0).timeout
		if is_instance_valid(copy_btn): copy_btn.text = "📋"
	)
	header.add_child(copy_btn)
	
	vbox.add_child(header)

	var content = RichTextLabel.new()
	content.bbcode_enabled = true
	content.fit_content = true
	content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.selection_enabled = true
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.text = _fmt(text)
	content.add_theme_color_override("default_color", C_TEXT if role != "user" else C_ACCENT_ALT)
	content.add_theme_font_size_override("normal_font_size", 15)
	vbox.add_child(content)

	bubble.add_child(vbox)
	chat_container.add_child(bubble)
	
	# Animate entrance
	bubble.modulate.a = 0
	var tween = create_tween()
	tween.tween_property(bubble, "modulate:a", 1.0, 0.15)
	_scroll_bottom()


func _fmt(text: String) -> String:
	var r = text
	var rx = RegEx.new()
	
	# 1. Multiline Code Blocks (Tolerate typo '```gdscript extends Node')
	rx.compile("```([a-zA-Z0-9_ \\t]*\\n)?([\\s\\S]*?)```")
	for m in rx.search_all(r):
		var lang = m.get_string(1).strip_edges()
		if lang == "": lang = "code"
		var content = m.get_string(2).strip_edges()
		var header = "[b][color=#a87ffb] 📝 " + lang + " [/color][/b]\n"
		var block = header + "[color=#a8c7fa][code]" + content + "[/code][/color]\n"
		r = r.replace(m.get_string(), block)
		
	# 2. Headings (Markdown ###)
	rx.compile("#{1,4}\\s+(.*)")
	for m in rx.search_all(r):
		r = r.replace(m.get_string(), "[b][color=#ffffff]" + m.get_string(1) + "[/color][/b]")

	# 3. Bold
	rx.compile("\\*\\*([^*]+)\\*\\*")
	for m in rx.search_all(r):
		r = r.replace(m.get_string(), "[b]" + m.get_string(1) + "[/b]")
		
	# 4. Inline code
	rx.compile("`([^`]+)`")
	for m in rx.search_all(r):
		r = r.replace(m.get_string(), "[color=#ffb48a]" + m.get_string(1) + "[/color]")
		
	return r


func _scroll_bottom():
	if not is_inside_tree():
		return
	await get_tree().process_frame
	await get_tree().process_frame
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


func _show_thinking(status: String = "AI is thinking...", phase: String = "scan"):
	# Remove existing if any
	_hide_thinking()

	var panel = PanelContainer.new()
	panel.name = "ThinkingPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Phase-specific border color
	var phase_color = {
		"scan": Color("#42a5f5"),
		"wait": Color("#ffd93d"),
		"read": Color("#64b5f6"),
		"edit": Color("#00e676"),
		"think": Color("#ab47bc")
	}.get(phase, C_ACCENT)
	
	var st = _sb(Color.TRANSPARENT, 0)
	panel.add_theme_stylebox_override("panel", st)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	
	var vbox = VBoxContainer.new()
	vbox.name = "ThinkingVBox"
	vbox.add_theme_constant_override("separation", 4)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	
	# Phase-specific icon
	var phase_icon = {
		"scan": "📂", "wait": "⏳", "read": "📖", "edit": "✏️", "think": "🧠"
	}.get(phase, "⏳")
	
	var spinner = Label.new()
	spinner.text = phase_icon
	spinner.name = "Spinner"
	spinner.add_theme_font_size_override("font_size", 16)
	hbox.add_child(spinner)

	var lbl = Label.new()
	lbl.name = "StatusLabel"
	lbl.text = status
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", phase_color)
	lbl.add_theme_font_size_override("font_size", 12)
	hbox.add_child(lbl)
	
	vbox.add_child(hbox)
	margin.add_child(vbox)
	panel.add_child(margin)
	chat_container.add_child(panel)
	
	# Scroll to bottom after adding
	_scroll_bottom()

func _update_thinking(status: String, phase: String = "wait"):
	var p = chat_container.get_node_or_null("ThinkingPanel")
	if not p:
		_show_thinking(status, phase)
		return
	
	# Update icon and label
	var phase_icon = {
		"scan": "📂", "wait": "⏳", "read": "📖", "edit": "✏️", "think": "🧠"
	}.get(phase, "⏳")
	var phase_color = {
		"scan": Color("#42a5f5"),
		"wait": Color("#ffd93d"),
		"read": Color("#64b5f6"),
		"edit": Color("#00e676"),
		"think": Color("#ab47bc")
	}.get(phase, C_ACCENT)
	
	var spinner_node = p.find_child("Spinner", true, false)
	if spinner_node: spinner_node.text = phase_icon
	
	var lbl = p.find_child("StatusLabel", true, false)
	if lbl:
		# Keep ThinkingPanel compact — truncate long status text
		var short_status = status.strip_edges().replace("\n", " ")
		if short_status.length() > 100:
			short_status = short_status.substr(0, 100) + "..."
		lbl.text = short_status
		lbl.add_theme_color_override("font_color", phase_color)
	
	# Scroll to bottom only once
	_scroll_bottom()


func _hide_thinking():
	var p = chat_container.get_node_or_null("ThinkingPanel")
	if p:
		p.queue_free()


func _add_welcome():
	# Clear any existing
	for c in chat_container.get_children(): c.queue_free()
	
	var spacer = Control.new()
	spacer.custom_minimum_size.y = 30
	chat_container.add_child(spacer)

	var center = CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	
	# Logo/Brand
	var brand_hbox = HBoxContainer.new()
	brand_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	brand_hbox.add_theme_constant_override("separation", 8)
	var logo = Label.new()
	logo.text = "✦"
	logo.add_theme_font_size_override("font_size", 28)
	logo.add_theme_color_override("font_color", C_ACCENT)
	brand_hbox.add_child(logo)
	var brand = Label.new()
	brand.text = "HiruAI"
	brand.add_theme_font_size_override("font_size", 22)
	brand.add_theme_color_override("font_color", Color.WHITE)
	brand_hbox.add_child(brand)
	vbox.add_child(brand_hbox)
	
	var lbl = Label.new()
	lbl.text = "Your AI coding assistant for Godot"
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl)
	
	# Quick action cards
	var cards_label = Label.new()
	cards_label.text = "Quick Start"
	cards_label.add_theme_font_size_override("font_size", 11)
	cards_label.add_theme_color_override("font_color", C_TEXT_DIM)
	cards_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(cards_label)
	
	var cards = VBoxContainer.new()
	cards.add_theme_constant_override("separation", 6)
	_add_quick_card(cards, "📝", "Generate Script", "Create a new GDScript from description", func(): _send("/generate"))
	_add_quick_card(cards, "🔧", "Fix Errors", "Auto-detect and fix project errors", func(): _on_fix())
	_add_quick_card(cards, "💡", "Explain Code", "Get explanations of your code", func(): _on_explain())
	_add_quick_card(cards, "🧩", "Create Node", "Build new scene & script hierarchy", func(): _on_create_node())
	vbox.add_child(cards)
	
	# Version info
	var ver = Label.new()
	ver.text = "v2.0 • Powered by NVIDIA AI"
	ver.add_theme_font_size_override("font_size", 9)
	ver.add_theme_color_override("font_color", Color(C_TEXT_DIM, 0.5))
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(ver)
	
	center.add_child(vbox)
	chat_container.add_child(center)
	
	# Animate entrance
	center.modulate.a = 0
	var tween = create_tween().set_ease(Tween.EASE_OUT)
	tween.tween_property(center, "modulate:a", 1.0, 0.5)

func _add_quick_card(parent: VBoxContainer, icon: String, title: String, desc: String, callback: Callable):
	var card = PanelContainer.new()
	var st = _sb(C_PANEL, 8, true, C_BORDER)
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	st.content_margin_left = 12
	st.content_margin_right = 12
	card.add_theme_stylebox_override("panel", st)
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	
	var ic = Label.new()
	ic.text = icon
	ic.add_theme_font_size_override("font_size", 16)
	hbox.add_child(ic)
	
	var text_vbox = VBoxContainer.new()
	text_vbox.add_theme_constant_override("separation", 1)
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t = Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 12)
	t.add_theme_color_override("font_color", Color.WHITE)
	text_vbox.add_child(t)
	var d = Label.new()
	d.text = desc
	d.add_theme_font_size_override("font_size", 10)
	d.add_theme_color_override("font_color", C_TEXT_DIM)
	text_vbox.add_child(d)
	hbox.add_child(text_vbox)
	
	var arrow = Label.new()
	arrow.text = "→"
	arrow.add_theme_color_override("font_color", C_TEXT_DIM)
	hbox.add_child(arrow)
	
	card.add_child(hbox)
	
	# Invisible click button
	var btn = Button.new()
	btn.flat = true
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.modulate.a = 0
	btn.pressed.connect(callback)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.add_child(btn)
	
	parent.add_child(card)


# ══════════════════ SEND LOGIC ══════════════════

func _on_send_pressed():
	_send(input_field.text)

func _on_text_submitted(_text: String):
	_send(input_field.text)

func _on_input_gui_input(event: InputEvent):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER and not event.shift_pressed:
			get_viewport().set_input_as_handled()
			_send(input_field.text)
		elif event.keycode == KEY_L and event.ctrl_pressed:
			get_viewport().set_input_as_handled()
			_on_clear()
		elif event.keycode == KEY_K and event.ctrl_pressed:
			get_viewport().set_input_as_handled()
			_show_command_palette()
		elif event.keycode == KEY_ESCAPE:
			if _cmd_popup and _cmd_popup.visible:
				_cmd_popup.hide()

func _on_input_text_changed():
	var text = input_field.text
	# Detect slash commands
	if text.begins_with("/") and text.length() < 20:
		_show_slash_suggestions(text)
		return
	else:
		if _cmd_popup and _cmd_popup.visible:
			_cmd_popup.hide()
			
	# Detect @ mentions mode
	var words = text.split(" ")
	for word in words:
		if word.begins_with("@") and word.length() > 1:
			var query = word.substr(1).to_lower()
			_show_file_suggestions(query)
			return
			
	# Hide if no match
	if _file_suggestion_popup and _file_suggestion_popup.visible:
		_file_suggestion_popup.hide()

func _show_file_suggestions(query: String):
	if not _file_suggestion_popup or not is_instance_valid(_file_suggestion_popup):
		_file_suggestion_popup = PopupPanel.new()
		_file_suggestion_popup.name = "FileMentionPopup"
		var popup_style = _sb(C_PANEL, 8, true, C_BORDER)
		_file_suggestion_popup.add_theme_stylebox_override("panel", popup_style)
		add_child(_file_suggestion_popup)
	
	for c in _file_suggestion_popup.get_children():
		c.queue_free()
		
	var Scanner = load("res://addons/hiruai/project_scanner.gd")
	if not Scanner: return
	
	# Try to quickly find files (limit to 5)
	var files: Array[String] = []
	Scanner._scan_dir("res://", files, 0)
	
	var matches = []
	for f in files:
		if query in f.to_lower():
			matches.append(f)
			if matches.size() > 5: break
			
	if matches.is_empty():
		_file_suggestion_popup.hide()
		return
		
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	
	var title = Label.new()
	title.text = "Attach File"
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", C_TEXT_DIM)
	vbox.add_child(title)
	
	for m in matches:
		var btn = Button.new()
		btn.text = "📄 " + m.get_file()
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 11)
		btn.add_theme_color_override("font_color", C_TEXT)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var bind_m = m
		btn.pressed.connect(func():
			_attach_file_to_context(bind_m)
			var cur_text = input_field.text
			# Remove the @query part
			var words = cur_text.split(" ")
			for i in words.size():
				if words[i].begins_with("@") and query in words[i].to_lower():
					words.remove_at(i)
					break
			input_field.text = " ".join(words)
			input_field.set_caret_column(input_field.text.length())
			_file_suggestion_popup.hide()
		)
		vbox.add_child(btn)
		
	_file_suggestion_popup.add_child(vbox)
	var pos = input_field.get_global_rect().position
	pos.y -= matches.size() * 24 + 40
	_file_suggestion_popup.popup(Rect2(pos, Vector2(280, 0)))

func _attach_file_to_context(path: String):
	if path not in _context_files:
		_context_files.append(path)
		_update_context_bar()
		_add_msg("system", "📎 Attached " + path.get_file() + " to context.")
		
		# Show attachment bar
		if _attachments_bar:
			_attachments_bar.visible = true
			var btn = Button.new()
			btn.text = "📄 " + path.get_file() + " ✕"
			btn.flat = true
			btn.add_theme_font_size_override("font_size", 9)
			var sb = _sb(Color("#2c2c3a"), 4)
			sb.content_margin_top = 2
			sb.content_margin_bottom = 2
			btn.add_theme_stylebox_override("normal", sb)
			btn.pressed.connect(func():
				_context_files.erase(path)
				_update_context_bar()
				btn.queue_free()
				if _context_files.is_empty():
					_attachments_bar.visible = false
			)
			_attachments_bar.add_child(btn)

func _send(text: String):
	if text.strip_edges().is_empty():
		return
	if kimi.is_busy():
		_add_msg("system", "Please wait for the current response.")
		return
	
	# Hide command popup
	if _cmd_popup and _cmd_popup.visible:
		_cmd_popup.hide()
	
	# Handle slash commands
	var stripped = text.strip_edges()
	if stripped.begins_with("/"):
		var handled = _handle_slash_command(stripped)
		if handled:
			input_field.text = ""
			return

	_add_msg("user", text)
	input_field.text = ""
	_read_loop_count = 0
	_step_counter = 0
	_activity_log.clear()

	# Only send file tree on first message or after Clear
	if not _tree_sent:
		_add_activity("📂", "Scanning project structure...", Color("#42a5f5"))
		await get_tree().create_timer(0.1).timeout
		var Scanner = load("res://addons/hiruai/project_scanner.gd")
		var context = ""
		if Scanner:
			context = Scanner.get_file_tree()
		chat_history.append({"role": "user", "content": text + "\n\n[Project]\n" + context})
		_tree_sent = true
		_add_activity("✅", "Project scanned successfully", Color("#00e676"))
	else:
		chat_history.append({"role": "user", "content": text})

	_send_to_ai()


func _send_to_ai():
	var messages: Array = [ {"role": "system", "content": _system_prompt()}]
	# Token saving: only send last 6 messages
	var recent = chat_history.slice(maxi(0, chat_history.size() - 6))
	messages.append_array(recent)

	_set_status("⏳ Thinking...", C_SYS)
	_step_counter += 1
	_last_request_time = Time.get_ticks_msec()
	_add_activity("⏳", "Step %d — Sending to %s..." % [_step_counter, kimi.current_model.get_file()], Color("#ffd93d"))
	
	# Toggle buttons
	send_btn.visible = false
	var cancel = find_child("CancelBtn", true, false)
	if cancel: cancel.visible = true
	
	kimi.send_chat(messages)


# ══════════════════ STREAMING HANDLERS ══════════════════

func _on_stream_started():
	"""Called when first SSE token arrives — create live bubble."""
	_hide_thinking()
	_streaming_raw_text = ""
	_step_counter += 1
	
	_thinking_duration_sec = maxi(1, (Time.get_ticks_msec() - _last_request_time) / 1000)
	_add_activity("🧠", "AI is generating response...", Color("#ab47bc"))
	
	# Create streaming bubble
	_streaming_bubble = PanelContainer.new()
	_streaming_bubble.name = "StreamingBubble"
	_streaming_bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bstyle = StyleBoxEmpty.new()
	bstyle.content_margin_top = 8
	_streaming_bubble.add_theme_stylebox_override("panel", bstyle)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)


	# Streaming indicator
	var stream_hint = Label.new()
	stream_hint.name = "StreamHint"
	stream_hint.text = "● streaming..."
	stream_hint.add_theme_color_override("font_color", Color("#00e676"))
	stream_hint.add_theme_font_size_override("font_size", 10)
	vbox.add_child(stream_hint)

	_streaming_content = RichTextLabel.new()
	_streaming_content.bbcode_enabled = true
	_streaming_content.fit_content = true
	_streaming_content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_streaming_content.scroll_active = false
	_streaming_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_streaming_content.add_theme_color_override("default_color", C_TEXT)
	_streaming_content.add_theme_font_size_override("normal_font_size", 15)
	_streaming_content.text = ""
	vbox.add_child(_streaming_content)

	_streaming_bubble.add_child(vbox)
	chat_container.add_child(_streaming_bubble)
	_scroll_bottom()


func _on_token_received(token: String):
	"""Called per-token — append to live bubble with real-time cleaning."""
	_streaming_raw_text += token
	if _streaming_content and is_instance_valid(_streaming_content):
		# 1. Update live display (CLEANED)
		var display = _clean_display_text(_streaming_raw_text)
		_streaming_content.text = _fmt(display)
		
		# 2. Live Thinking Update (compact preview only — full text goes to collapsible card later)
		var thought = _extract_thoughts(_streaming_raw_text, true) # Partial allowed
		if thought != "":
			var preview = thought.strip_edges().replace("\n", " ").substr(0, 80)
			if thought.length() > 80:
				preview += "..."
			_update_thinking("Planning: " + preview, "think")
		
		# 3. Auto-scroll
		_scroll_bottom()


func _on_stream_finished(full_text: String):
	"""Called when SSE stream ends — clean up streaming bubble."""
	pass
	_streaming_content = null
	_streaming_raw_text = ""
	_add_activity("✅", "Response complete", Color("#00e676"))
	# Estimate tokens (~4 chars per token)
	var est_tokens = full_text.length() / 4
	_update_token_display(est_tokens)


func _phase_from_icon(icon: String) -> String:
	match icon:
		"📂", "🔍": return "scan"
		"📖": return "read"
		"✏️", "💾": return "edit"
		"🧠": return "think"
		"⏳": return "wait"
		_: return "wait"


# ══════════════════ AI RESPONSE HANDLER ══════════════════

func _on_ai_response(text: String):
	_hide_thinking()
	
	# DO NOT queue_free yet. We check it below to avoid double message.
	_streaming_content = null
	
	# Restore buttons
	send_btn.visible = true
	var cancel = find_child("CancelBtn", true, false)
	if cancel: cancel.visible = false

	# 1) Extract all commands
	var searches = _extract_searches(text)
	var reads = _extract_reads(text)
	var read_lines = _extract_read_lines(text)
	var saves = _extract_saves(text)
	var deletes = _extract_deletes(text)
	var run_req = _extract_run_game(text)

	# 1) PRE-ACTION: Show Activity Chips for commands
	var thoughts = _extract_thoughts(text)
	if thoughts != "":
		_add_thought_card_with_text(thoughts)
	
	if searches.size() > 0:
		_add_activity_bubble("🔍 Searching for %d keyword(s)..." % searches.size(), Color("#9c27b0"))
	if reads.size() > 0:
		_add_activity_bubble("📖 Analyzing %d file(s)..." % reads.size(), Color("#42a5f5"))
	if saves.size() > 0:
		for s in saves:
			var lines = s["content"].split("\n").size()
			_add_activity_bubble("💾 Processing %s (%d lines of code)..." % [s["path"].get_file(), lines], Color("#00e676"))
	if deletes.size() > 0:
		_add_activity_bubble("🗑️ Deleting %d file(s)..." % deletes.size(), Color("#f87171"))

	# 1.1) Show CLEAN AI message (no raw code blocks)
	chat_history.append({"role": "assistant", "content": text})
	var clean_text = _clean_display_text(text)
	
	# ONLY add message if it wasn't already streamed
	if not _streaming_bubble and clean_text != "":
		_add_msg("ai", clean_text)
	elif _streaming_bubble and is_instance_valid(_streaming_bubble):
		# If it was streamed, just finalize the last bubble
		var hint = _streaming_bubble.find_child("StreamHint", true, false)
		if hint: hint.queue_free()
		
		# Ensure formatted properly and CLEANED
		var rtxt = _streaming_bubble.find_child("RichTextLabel", true, false)
		if rtxt:
			rtxt.text = _fmt(clean_text) # Use CLEAN text, not raw!
			rtxt.visible_ratio = 1.0
			
		_streaming_bubble = null # Mark as finished
	
	_set_status("● Ready", Color("#00ff88"))


	# 3) Handle SEARCH requests
	if searches.size() > 0 and _read_loop_count < MAX_READ_LOOPS:
		_read_loop_count += 1
		_add_activity("🔍", "Searching %d keyword(s)..." % searches.size(), Color("#9c27b0"))
		var Scanner = load("res://addons/hiruai/project_scanner.gd")
		var search_results := ""
		if Scanner:
			for q in searches:
				_add_activity("🔍", "Searching for '" + q + "'...", Color("#42a5f5"))
				var result = Scanner.search_text(q)
				_add_file_card("Keyword: " + q, "Searched", Color("#9c27b0"))
				search_results += "\n=== Search: %s ===\n%s\n" % [q, result]
			
		chat_history.append({
			"role": "user",
			"content": "Search results:\n" + search_results + "\nNow use [READ:] or [READ_LINES:] on the files you need, or proceed."
		})
		_send_to_ai()
		return

	# 3a) Handle READ requests first — auto-read loop
	if reads.size() > 0 and _read_loop_count < MAX_READ_LOOPS:
		_read_loop_count += 1
		_add_activity("📖", "Reading %d file(s)..." % reads.size(), Color("#42a5f5"))
		var Scanner = load("res://addons/hiruai/project_scanner.gd")
		var file_contents := ""
		var read_count := 0
		for read_path in reads:
			if read_count >= 3:
				break
			_add_activity("📖", "Reading " + read_path.get_file() + "...", Color("#64b5f6"))
			var content = Scanner.read_file(read_path)
			_add_file_card(read_path, "Analyzed", C_READ)
			file_contents += "\n--- %s ---\n%s\n" % [read_path, content]
			if read_path not in _read_files:
				_read_files.append(read_path)
			if read_path not in _context_files:
				_context_files.append(read_path)
				_update_context_bar()
			read_count += 1
		if reads.size() > 3:
			file_contents += "\n(Skipped %d files. Use [READ:] again for remaining.)" % (reads.size() - 3)
		_add_activity("🧠", "Analyzing " + str(read_count) + " file(s)...", Color("#ab47bc"))
		chat_history.append({
			"role": "user",
			"content": "File contents:\n" + file_contents + "\nProceed with the task."
		})
		_send_to_ai()
		return

	# 3b) Handle READ_LINES requests
	if read_lines.size() > 0 and _read_loop_count < MAX_READ_LOOPS:
		_read_loop_count += 1
		var Scanner = load("res://addons/hiruai/project_scanner.gd")
		var file_contents := ""
		for rl in read_lines:
			_add_activity("📖", "Reading lines %d-%d of %s..." % [rl["start"], rl["end"], rl["path"].get_file()], Color("#64b5f6"))
			var content = Scanner.read_file_lines(rl["path"], rl["start"], rl["end"])
			_add_file_card(rl["path"], "Analyzed", C_READ.darkened(0.2), "#L%d-%d" % [rl["start"], rl["end"]])
			file_contents += "\n--- %s (lines %d-%d) ---\n%s\n" % [rl["path"], rl["start"], rl["end"], content]
		chat_history.append({
			"role": "user",
			"content": "File contents:\n" + file_contents + "\nProceed with the task."
		})
		_send_to_ai()
		return

	# 4) If there are SAVE/DELETE ops, validate planning and READ-before-SAVE
	if saves.size() > 0 or deletes.size() > 0:
		# ── FORCED PLANNING PHASE ──
		# If AI jumped straight to SAVE without reading/searching ANYTHING first,
		# force a planning cycle: auto-read target files + demand [THOUGHT:] plan.
		if _read_loop_count == 0 and _read_loop_count < MAX_READ_LOOPS:
			_read_loop_count += 1
			_add_msg("system", "🧠 **Planning phase** — Hiru is analyzing your project before making changes...")
			_add_activity("🧠", "Planning: reading files before acting", Color("#ab47bc"))
			
			var Scanner = load("res://addons/hiruai/project_scanner.gd")
			var auto_read_contents := ""
			
			# Auto-read existing files the AI wants to modify
			for s in saves:
				if FileAccess.file_exists(s["path"]) and s["path"] not in _read_files:
					var content = Scanner.read_file(s["path"])
					auto_read_contents += "\n--- %s ---\n%s\n" % [s["path"], content]
					_add_file_card(s["path"], "Auto-Read", C_READ)
					_read_files.append(s["path"])
			
			# Also auto-read files referenced in delete targets
			for d_path in deletes:
				if FileAccess.file_exists(d_path) and d_path not in _read_files:
					var content = Scanner.read_file(d_path)
					auto_read_contents += "\n--- %s ---\n%s\n" % [d_path, content]
					_read_files.append(d_path)
			
			var plan_prompt := "SYSTEM: PLANNING PHASE REQUIRED.\n"
			plan_prompt += "You MUST plan before making changes. Follow this flow:\n"
			plan_prompt += "1. [THOUGHT:] — Explain your COMPLETE strategy step by step. What will you change? Why? What could break?\n"
			plan_prompt += "2. [READ:] / [SEARCH:] — If you need to check more files or find references, do it now.\n"
			plan_prompt += "3. [SAVE:] — Only AFTER planning, provide the [SAVE:] blocks with accurate, complete code.\n\n"
			
			if auto_read_contents != "":
				plan_prompt += "I've auto-loaded the files you want to modify. Study them carefully:\n" + auto_read_contents
				plan_prompt += "\nNow start with [THOUGHT:] analyzing the code above, then provide your [SAVE:] blocks."
			else:
				plan_prompt += "These appear to be new files. Use [THOUGHT:] to explain your design decisions, then provide [SAVE:] blocks."
			
			chat_history.append({"role": "user", "content": plan_prompt})
			_send_to_ai()
			return
		
		# Validate: block SAVE if file was never READ (force AI to read first)
		var unread_saves: Array[String] = []
		for s in saves:
			var spath: String = s["path"]
			# Allow new file creation (file doesn't exist yet)
			if FileAccess.file_exists(spath) and spath not in _read_files:
				unread_saves.append(spath)
		
		if unread_saves.size() > 0 and _read_loop_count < MAX_READ_LOOPS:
			# AI tried to SAVE without reading — force a read cycle
			_read_loop_count += 1
			var Scanner = load("res://addons/hiruai/project_scanner.gd")
			var file_contents := ""
			for upath in unread_saves:
				_add_activity("⚠️", "Must read " + upath.get_file() + " before editing...", Color("#ffd93d"))
				var content = Scanner.read_file(upath)
				_add_file_card(upath, "READ", C_READ)
				file_contents += "\n--- %s ---\n%s\n" % [upath, content]
				if upath not in _read_files:
					_read_files.append(upath)
			_add_msg("system", "⚠️ AI tried to edit without reading first. Auto-reading %d file(s)..." % unread_saves.size())
			chat_history.append({
				"role": "user",
				"content": "SYSTEM: You tried to SAVE files without reading them first. Here are the current contents. You MUST preserve all existing code and only change what was requested:\n" + file_contents + "\nNow redo the edit correctly. Include the COMPLETE file content."
			})
			_send_to_ai()
			return

		# --- CHECK MISSING PRELOAD DEPENDENCIES ---
		var missing_preloads = _find_missing_preloads(saves)
		var missing_preload_paths: Array[String] = []
		var syntax_errors: Array[Dictionary] = []
		
		for mp in missing_preloads:
			var src = mp["source"]
			var mis = mp["missing"]
			if src not in missing_preload_paths:
				missing_preload_paths.append(src)
			
			var ext = mis.get_extension().to_lower()
			var err = ""
			if ext in ["gd", "tscn", "tres", "txt", "json", "csv", "md"]:
				err = 'CRITICAL ERROR: You used `preload("%s")` but "%s" DOES NOT EXIST! You MUST generate its complete code using a `[SAVE:%s]` block.' % [mis, mis.get_file(), mis]
			else:
				err = 'CRITICAL ERROR: You used `preload("%s")` for a missing asset! Change your code to use `load()` instead of `preload()`, or remove it.' % [mis]
			
			syntax_errors.append({"path": src, "error": err})

		# --- SYNTAX AUTO-FIX LOOP ---
		# Temporarily write non-.gd files to disk so preload() resolves during syntax check
		var _temp_written_paths: Array[String] = []
		for s in saves:
			if not s["path"].ends_with(".gd") and not FileAccess.file_exists(s["path"]):
				var ok = _write_project_file(s["path"], s["content"])
				if ok:
					_temp_written_paths.append(s["path"])
		
		for s in saves:
			var spath: String = s["path"]
			# Only check syntax if the file wasn't already flagged for missing preloads
			if spath.ends_with(".gd") and spath not in missing_preload_paths:
				var scode: String = s["content"]
				var err_msg = _check_syntax_error(scode)
				if err_msg != "":
					syntax_errors.append({"path": spath, "error": err_msg})
		
		# Clean up temp files (they'll be properly saved if user Accepts)
		for tmp_path in _temp_written_paths:
			_delete_project_file(tmp_path)
		
		if syntax_errors.size() > 0 and _read_loop_count < MAX_READ_LOOPS:
			_read_loop_count += 1
			var err_list := ""
			for se in syntax_errors:
				err_list += "\n- File: %s\n- Error: %s\n" % [se["path"], se["error"]]
			
			_add_msg("system", "🔍 **Syntax check failed.** Hiru is auto-fixing the code...")
			_add_activity("✏️", "Auto-fixing syntax errors...", Color("#00e676"))
			
			chat_history.append({
				"role": "user",
				"content": "SYSTEM: The code you provided has compilation errors or missing dependencies. You MUST fix them before I can accept it.\n" + \
						   "1. START with `[THOUGHT:]` to analyze WHY the error happened and how to fix it.\n" + \
						   "2. Then redo ALL `[SAVE:]` blocks (both the corrected ones and the original ones that had no errors so no code is lost):\n" + err_list
			})
			_send_to_ai()
			return
		
		_pending_saves = []
		for s in saves:
			_pending_saves.append(s)
		_pending_deletes = []
		for d in deletes:
			_pending_deletes.append(d)

		# Show pending file cards
		for save_data in _pending_saves:
			_add_file_card(save_data["path"], "PENDING SAVE", C_SYS)
		for del_path in _pending_deletes:
			_add_file_card(del_path, "PENDING DELETE", C_SYS)

		# Show accept / reject buttons
		_show_approval_ui()
		_set_status("⏸ Waiting for approval...", C_SYS)
		return

	# Handle RUN_GAME requests
	if run_req != "":
		_add_msg("system", "🚀 AI requested to run the game (%s). Use the Play buttons below to test." % run_req)
		# We don't auto-run for safety, but we let the user know

	# LIMIT FALLBACK: Prevent silent hanging
	var wants_to_action = reads.size() > 0 or read_lines.size() > 0 or searches.size() > 0 or saves.size() > 0 or deletes.size() > 0
	if wants_to_action and _read_loop_count >= MAX_READ_LOOPS:
		_add_msg("error", "⚠️ AI reached maximum internal steps (%d). Stopped to prevent infinite loop." % MAX_READ_LOOPS)
		_set_status("● Limit Reached", Color("#ffbb00"))
		return

	_set_status("● Ready", Color("#00ff88"))


func _clean_display_text(text: String) -> String:
	"""STRICT technical tags removal for streaming and final display."""
	var result = text
	var rx = RegEx.new()

	# 1. Clear THOUGHTS completely (even if partial/open-ended at the end)
	# This regex matches from [THOUGHT: to either the closing ] or the end of string $
	rx.compile("\\[THOUGHT:[\\s\\S]*?(\\]|$)")
	result = rx.sub(result, "", true)

	# 2. Clear technical commands [SAVE:], [READ:], etc. (even if partial/open at end)
	rx.compile("\\[(SAVE|READ|READ_LINES|SEARCH|DELETE):[\\s\\S]*?(\\]|$)")
	result = rx.sub(result, "", true)

	# 3. Clear code blocks (even if partial/open at end)
	rx.compile("```[\\s\\S]*?(```|$)")
	result = rx.sub(result, "", true)

	# 4. Clean up repetitive robotic phrases (AI Loops)
	var robotic_phrases = [
		"User keeps greeting without specifying a task",
		"To break the cycle, I'll proactively",
		"Saya akan memastikan untuk tidak meminimifikasi",
		"Saya memahami peringatan sistem ini"
	]
	for phrase in robotic_phrases:
		if phrase in result:
			var rob_rx = RegEx.new()
			rob_rx.compile("(?m)^.*" + phrase + ".*$[\n\r]*")
			result = rob_rx.sub(result, "", true)

	# 5. Hide [RESULT:] tags
	result = result.replace("[RESULT:]\n", "").replace("[RESULT:]", "").replace("[RESULT: ]\n", "").replace("[RESULT: ]", "")

	# 6. Clean up leftovers
	rx.compile("(?m)^\\s*(HT:|SAVE:|READ:|READ_LINES:|SEARCH:|DELETE:).*$")
	result = rx.sub(result, "", true)

	# 5. Clean up extra blank lines
	while "\n\n\n" in result:
		result = result.replace("\n\n\n", "\n\n")

	return result.strip_edges()


func _show_approval_ui():
	"""Show Accept / Reject buttons for pending file changes."""
	# Remove old approval panel if exists
	if _approval_panel and is_instance_valid(_approval_panel):
		_approval_panel.queue_free()

	_approval_panel = PanelContainer.new()
	_approval_panel.name = "ApprovalPanel"
	_approval_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ap_style = StyleBoxEmpty.new()
	ap_style.content_margin_top = 10
	ap_style.content_margin_bottom = 10
	_approval_panel.add_theme_stylebox_override("panel", ap_style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	# Files list with Preview button
	for s_data in _pending_saves:
		var row = HBoxContainer.new()
		var lbl = Label.new()
		lbl.text = "💾 " + s_data["path"].get_file()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_color_override("font_color", C_SYS)
		
		var btn = Button.new()
		btn.text = "Preview Diff"
		btn.flat = true
		btn.add_theme_color_override("font_color", Color("#42a5f5"))
		# Create local scope binding for lambda
		var path_bind = s_data["path"]
		var content_bind = s_data["content"]
		btn.pressed.connect(func(): _preview_diff(path_bind, content_bind))
		
		row.add_child(lbl)
		row.add_child(btn)
		vbox.add_child(row)
		
	for d_path in _pending_deletes:
		var row = HBoxContainer.new()
		var lbl = Label.new()
		lbl.text = "🗑️ " + d_path.get_file()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_color_override("font_color", C_ERR)
		row.add_child(lbl)
		vbox.add_child(row)

	# Buttons row
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)

	var accept_btn = Button.new()
	accept_btn.text = "Accept"
	accept_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	accept_btn.flat = true
	accept_btn.add_theme_color_override("font_color", Color("#00e676"))
	accept_btn.pressed.connect(_on_accept_changes)
	btn_row.add_child(accept_btn)

	var reject_btn = Button.new()
	reject_btn.text = "Reject"
	reject_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reject_btn.flat = true
	reject_btn.add_theme_color_override("font_color", Color("#ff5252"))
	reject_btn.pressed.connect(_on_reject_changes)
	btn_row.add_child(reject_btn)

	vbox.add_child(btn_row)
	_approval_panel.add_child(vbox)

	# Animate in
	_approval_panel.modulate.a = 0.0
	chat_container.add_child(_approval_panel)

	var tween = create_tween()
	tween.tween_property(_approval_panel, "modulate:a", 1.0, 0.3)
	_scroll_bottom()

func _preview_diff(path: String, new_content: String):
	var old_content = ""
	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		if file:
			old_content = file.get_as_text()
			file.close()

	var win = Window.new()
	win.title = "Unified Diff Preview: " + path.get_file()
	win.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	win.size = Vector2(900, 650)
	win.close_requested.connect(win.queue_free)

	var panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pstyle = StyleBoxFlat.new()
	pstyle.bg_color = Color("#1e1e1e")
	panel.add_theme_stylebox_override("panel", pstyle)

	var ce = CodeEdit.new()
	ce.editable = false
	ce.draw_tabs = true
	ce.gutters_draw_line_numbers = true
	ce.minimap_draw = true
	ce.scroll_past_end_of_file = true
	ce.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ce.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Try to use editor theme for fonts
	if Engine.is_editor_hint():
		var ed_theme = EditorInterface.get_editor_theme()
		if ed_theme:
			ce.theme = ed_theme
			var font = ed_theme.get_font("source", "EditorFonts")
			if font: ce.add_theme_font_override("font", font)
			var font_size = ed_theme.get_font_size("source_size", "EditorFonts")
			if font_size: ce.add_theme_font_size_override("font_size", font_size)

	# --- Unified Diff Calculation (LCS) ---
	var old_lines = old_content.split("\n")
	var new_lines = new_content.split("\n")
	
	var m = old_lines.size()
	var n = new_lines.size()
	var diff_ops = []
	
	# Max ~3162x3162 grid, prevents long freezing on massive files
	if m * n < 10000000:
		var L = []
		for i in range(m + 1):
			var row = []
			row.resize(n + 1)
			row.fill(0)
			L.append(row)
			
		for i in range(1, m + 1):
			for j in range(1, n + 1):
				if old_lines[i - 1] == new_lines[j - 1]:
					L[i][j] = L[i - 1][j - 1] + 1
				else:
					L[i][j] = maxi(L[i - 1][j], L[i][j - 1])
					
		var i = m
		var j = n
		
		while i > 0 and j > 0:
			if old_lines[i - 1] == new_lines[j - 1]:
				diff_ops.push_front({"type": "=", "text": old_lines[i - 1]})
				i -= 1
				j -= 1
			elif L[i - 1][j] > L[i][j - 1]:
				diff_ops.push_front({"type": "-", "text": old_lines[i - 1]})
				i -= 1
			else:
				diff_ops.push_front({"type": "+", "text": new_lines[j - 1]})
				j -= 1
				
		while i > 0:
			diff_ops.push_front({"type": "-", "text": old_lines[i - 1]})
			i -= 1
		while j > 0:
			diff_ops.push_front({"type": "+", "text": new_lines[j - 1]})
			j -= 1
			
	else:
		# Fallback for massive files: Just show old then new to prevent engine freeze
		for line in old_lines: diff_ops.append({"type": "-", "text": line})
		for line in new_lines: diff_ops.append({"type": "+", "text": line})
			
	var diff_lines = PackedStringArray()
	for op in diff_ops:
		if op.type == "+":
			diff_lines.append("+ " + op.text)
		elif op.type == "-":
			diff_lines.append("- " + op.text)
		else:
			diff_lines.append("  " + op.text)
			
	ce.text = "\n".join(diff_lines)
	
	# Apply background colors
	for i in range(diff_ops.size()):
		if diff_ops[i].type == "+":
			ce.set_line_background_color(i, Color(0.1, 0.8, 0.1, 0.2)) # Green
		elif diff_ops[i].type == "-":
			ce.set_line_background_color(i, Color(0.8, 0.1, 0.1, 0.2)) # Red

	panel.add_child(ce)
	win.add_child(panel)
	add_child(win)
	win.popup()


func _on_accept_changes():
	"""User approved — apply all pending saves and deletes."""
	_set_status("⏳ Saving...", C_SYS)
	
	# Clear previous undo stack
	_undo_stack.clear()
	
	# Remove approval UI instantly
	if _approval_panel and is_instance_valid(_approval_panel):
		_approval_panel.queue_free()
		_approval_panel = null

	var fs = EditorInterface.get_resource_filesystem() if Engine.is_editor_hint() else null
	
	# Apply saves
	for save_data in _pending_saves:
		var path = save_data["path"]
		var old_text = ""
		var existed = false
		if FileAccess.file_exists(path):
			existed = true
			var f = FileAccess.open(path, FileAccess.READ)
			if f: old_text = f.get_as_text(); f.close()
			
		# Add to undo stack
		_undo_stack.append({
			"path": path,
			"content": old_text,
			"type": "save" if existed else "create"
		})
			
		var ok = _write_project_file(path, save_data["content"])
		if ok:
			var diff_stats = _calculate_diff(old_text, save_data["content"])
			_add_file_card(path, "Edited", C_SAVE, diff_stats)
			if fs:
				fs.update_file(path)
				# Force reload if it's an open script
				# This can be slow, so we only do it for GDScript
				if path.ends_with(".gd"):
					var res = load(path)
					if res is Script:
						res.reload()
		else:
			_add_file_card(path, "SAVE FAILED", C_ERR)
	
	# Apply deletes
	for d_path in _pending_deletes:
		var old_text = ""
		if FileAccess.file_exists(d_path):
			var f = FileAccess.open(d_path, FileAccess.READ)
			if f: old_text = f.get_as_text(); f.close()
			
		_undo_stack.append({
			"path": d_path,
			"content": old_text,
			"type": "delete"
		})
		
		var ok = _delete_project_file(d_path)
		if ok:
			_add_file_card(d_path, "Deleted", C_DELETE)
			if fs: fs.update_file(d_path)
		else:
			_add_msg("error", "Failed to delete: " + d_path)
	
	_pending_saves = []
	_pending_deletes = []
	_set_status("● Ready", Color("#00ff88"))
	_add_msg("system", "✅ All changes applied! Use `/undo` to revert.")

	# Force Godot to recognize the new files
	if fs:
		# Use scan() instead of re_scan_resources() for better performance
		fs.scan()
		
		# Wait just one frame for the OS to flush if needed
		await get_tree().process_frame
		
		# Refresh inspector if needed
		var edited = EditorInterface.get_inspector().get_edited_object()
		if edited:
			EditorInterface.get_inspector().edit(edited)

	_pending_saves.clear()
	_pending_deletes.clear()
	_set_status("● Ready", Color("#00ff88"))
	
	if _self_healing_enabled:
		await get_tree().create_timer(0.5).timeout
		_on_play_main()

func _on_cancel_pressed():
	kimi.cancel_request()
	_hide_thinking()
	
	# Restore buttons
	send_btn.visible = true
	var cancel = get_node_or_null("CancelBtn")
	if not cancel:
		for c in get_children():
			var found = c.find_child("CancelBtn", true, false)
			if found: cancel = found
	if cancel: cancel.visible = false
	
	_set_status("● Cancelled", Color("#ffbb00"))
	_add_msg("system", "⏹ Request cancelled by user.")


func _on_reject_changes():
	"""User rejected — discard all pending changes."""
	if _approval_panel and is_instance_valid(_approval_panel):
		_approval_panel.queue_free()
		_approval_panel = null

	var count = _pending_saves.size() + _pending_deletes.size()
	_pending_saves.clear()
	_pending_deletes.clear()

	_add_msg("system", "❌ Changes rejected. %d file operation(s) discarded." % count)
	_set_status("● Ready", Color("#00ff88"))


func _on_ai_error(error: String):
	_hide_thinking()
	_add_msg("error", error)
	_set_status("● Error", C_ERR)


func _set_status(text: String, color: Color):
	if status_label:
		status_label.text = text
		status_label.add_theme_color_override("font_color", color)


# ══════════════════ FILE OPERATIONS ══════════════════

func _extract_searches(text: String) -> Array[String]:
	"""Extract [SEARCH:keyword] tags."""
	var results: Array[String] = []
	var rx = RegEx.new()
	rx.compile("\\[SEARCH:([^\\]]+)\\]")
	for m in rx.search_all(text):
		var k = m.get_string(1).strip_edges()
		if k != "" and k not in results:
			results.append(k)
	return results


func _extract_reads(text: String) -> Array[String]:
	"""Extract [READ:path] tags from AI response."""
	var paths: Array[String] = []
	var rx = RegEx.new()
	# Match either [READ:path] or <parameter=file>path</parameter> (fallback for weird models)
	rx.compile("\\[READ:([^\\]]+)\\]|<parameter=file>\\s*(.*?)\\s*<\\/parameter>")
	for m in rx.search_all(text):
		var p = m.get_string(1)
		if p == "":
			p = m.get_string(2)
		
		# Bersihkan spasi dan newline jika AI typo
		p = p.replace(" ", "").replace("\n", "").replace("\r", "")
			
		# AI often forgets res:// when hallucinating tool calls
		if p != "" and not p.begins_with("res://"):
			p = "res://" + p.trim_prefix("/")
			
		if p != "" and p not in paths:
			paths.append(p)
	return paths


func _extract_read_lines(text: String) -> Array[Dictionary]:
	"""Extract [READ_LINES:path:start-end] tags."""
	var results: Array[Dictionary] = []
	var rx = RegEx.new()
	# Allow any characters for path until the last colon before digits
	rx.compile("\\[READ_LINES:\\s*(.+?)\\s*:\\s*(\\d+)\\s*-\\s*(\\d+)\\s*\\]")
	for m in rx.search_all(text):
		var p = m.get_string(1).replace(" ", "").replace("\n", "").replace("\r", "")
		if not p.begins_with("res://"):
			p = "res://" + p.trim_prefix("/")
		results.append({
			"path": p,
			"start": int(m.get_string(2)),
			"end": int(m.get_string(3))
		})
	return results


func _extract_thoughts(text: String, allow_partial: bool = false) -> String:
	"""Extract [THOUGHT:plan] tags from AI response."""
	var rx = RegEx.new()
	if allow_partial:
		rx.compile("\\[THOUGHT:([\\s\\S]*?)(?:\\]|$)")
	else:
		rx.compile("\\[THOUGHT:([\\s\\S]*?)\\]")
	
	var m = rx.search(text)
	if m:
		return m.get_string(1).strip_edges()
	return ""


func _extract_saves(text: String) -> Array[Dictionary]:
	"""Extract [SAVE:path] + code block pairs, or fuzzily match markdown code blocks!"""
	var saves: Array[Dictionary] = []
	var claimed_blocks: Array[String] = []
	
	# Pass 1: Strict [SAVE:path] with backticks (The intended way)
	var rx_strict = RegEx.new()
	rx_strict.compile("\\[SAVE:([^\\]]+)\\][\\s\\S]*?```(?:[a-zA-Z0-9_ \\t]*\\n)?([\\s\\S]*?)```")
	var strict_matches = rx_strict.search_all(text)
	for m in strict_matches:
		var raw_content = m.get_string(2)
		saves.append({
			"path": m.get_string(1).strip_edges(),
			"content": _clean_extraneous_gdscript(raw_content)
		})
		claimed_blocks.append(raw_content)

	# Pass 2: Fuzzy fallback (AI forgot [SAVE:] but wrote `res://...` nearby, OR inside comment)
	var rx_code = RegEx.new()
	rx_code.compile("```(?:[a-zA-Z0-9_ \\t]*\\n)?([\\s\\S]*?)```")
	var code_matches = rx_code.search_all(text)
	
	for m_code in code_matches:
		var raw_content = m_code.get_string(1)
		
		# Skip if we already captured this exact block via Pass 1
		var is_claimed = false
		for cb in claimed_blocks:
			if raw_content.strip_edges() == cb.strip_edges():
				is_claimed = true
				break
		if is_claimed: continue
		
		var start_pos = m_code.get_start()
		# Look at the text strictly before this code block (up to 150 chars backwards)
		var check_start = maxi(0, start_pos - 150)
		var pre_text = text.substr(check_start, start_pos - check_start)
		
		# Match any Godot file path (e.g. res://inventory.gd)
		var rx_path = RegEx.new()
		rx_path.compile("(res://[a-zA-Z0-9_\\-\\./\\\\]+\\.[a-zA-Z0-9_]+)")
		var path_matches = rx_path.search_all(pre_text)
		
		var found_path = ""
		if path_matches.size() > 0:
			# Grab the CLOSEST path right above the code block
			found_path = path_matches[path_matches.size() - 1].get_string(1).strip_edges()
		else:
			# Fallback: Check if the first line of the code block is a path comment # res://...
			var first_line = raw_content.split("\n")[0].strip_edges()
			if first_line.begins_with("#") and "res://" in first_line:
				var c_rx = RegEx.new()
				c_rx.compile("(res://[a-zA-Z0-9_\\-\\./\\\\]+\\.[a-zA-Z0-9_]+)")
				var cm = c_rx.search(first_line)
				if cm: found_path = cm.get_string(1).strip_edges()
				
		if found_path != "":
			saves.append({
				"path": found_path,
				"content": _clean_extraneous_gdscript(raw_content)
			})
			claimed_blocks.append(raw_content)

	# Pass 3: [SAVE:path] strictly but NO backticks at all (AI completely hallucinated and dumped text)
	var rx_no_backticks = RegEx.new()
	rx_no_backticks.compile("\\[SAVE:([^\\]]+)\\]")
	var no_bt_matches = rx_no_backticks.search_all(text)
	for i in no_bt_matches.size():
		var path = no_bt_matches[i].get_string(1).strip_edges()
		
		# Skip if we already got this path
		var already_has = false
		for s in saves:
			if s["path"] == path:
				already_has = true
				break
		if already_has: continue
		
		var start_pos = no_bt_matches[i].get_end()
		var end_pos = text.length()
		if i + 1 < no_bt_matches.size():
			end_pos = no_bt_matches[i + 1].get_start()
			
		var next_tag = text.find("[", start_pos)
		if next_tag != -1 and not text.substr(next_tag, 6).begins_with("[node") and not text.substr(next_tag, 4).begins_with("[gd_"):
			end_pos = mini(end_pos, next_tag)
			
		var block_content = text.substr(start_pos, end_pos - start_pos).strip_edges()
		if block_content != "":
			saves.append({
				"path": path,
				"content": _clean_extraneous_gdscript(_strip_code_boilerplate(block_content))
			})

	return saves

func _clean_extraneous_gdscript(code: String) -> String:
	"""Removes accidental 'gdscript' word glued to 'extends Node'."""
	var result = code.strip_edges()
	if result.begins_with("gdscript"):
		var after = result.substr(8).strip_edges()
		if after.begins_with("extends ") or after.begins_with("class_name ") or after.begins_with("@") or after.begins_with("func ") or after.begins_with("var ") or after.begins_with("const ") or after.begins_with("signal ") or after.begins_with("#"):
			# It was hallucinated, strip the 'gdscript' out.
			return after
	return result


func _strip_code_boilerplate(block: String) -> String:
	"""Finds where the actual GDScript begins when backticks are absent."""
	var lines = block.split("\n")
	var result = []
	var in_code = false
	for line in lines:
		var ln = line.strip_edges()
		if not in_code:
			var test_ln = ln
			if test_ln.begins_with("gdscript"):
				test_ln = test_ln.substr(8).strip_edges()
				
			if test_ln.begins_with("extends ") or test_ln.begins_with("class_name ") or test_ln.begins_with("@") or test_ln.begins_with("func ") or test_ln.begins_with("var ") or test_ln.begins_with("const ") or test_ln.begins_with("signal ") or test_ln.begins_with("#"):
				in_code = true
				if test_ln != ln:
					line = line.replace("gdscript", "").strip_edges()
			elif test_ln.begins_with("[gd_scene ") or test_ln.begins_with("[gd_resource "):
				in_code = true
				if test_ln != ln:
					line = line.replace("gdscript", "").strip_edges()
		if in_code:
			result.append(line)
			
	if result.is_empty():
		return block.strip_edges()
	return "\n".join(result).strip_edges()


func _extract_deletes(text: String) -> Array[String]:
	"""Extract [DELETE:path] tags."""
	var paths: Array[String] = []
	var rx = RegEx.new()
	rx.compile("\\[DELETE:([^\\]]+)\\]")
	for m in rx.search_all(text):
		paths.append(m.get_string(1).strip_edges())
	return paths


func _write_project_file(path: String, content: String) -> bool:
	"""Write a file to the project. Only res:// paths allowed."""
	if not path.begins_with("res://"):
		print("[HiruAI] ⚠️ Blocked: ", path, " (not res://)")
		return false
	for b in [".godot", ".import", ".git"]:
		if b in path:
			print("[HiruAI] ⚠️ Blocked protected: ", path)
			return false

	# Auto-create directories
	var dir_path = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		print("[HiruAI] ❌ Cannot write: ", path)
		return false

	file.store_string(content)
	file.close()
	print("[HiruAI] ✅ Saved: ", path)
	return true


func _delete_project_file(path: String) -> bool:
	"""Delete a file from the project. Only res:// paths allowed."""
	if not path.begins_with("res://"):
		print("[HiruAI] ⚠️ Blocked delete: ", path)
		return false
	for b in [".godot", ".import", ".git", "addons/hiruai"]:
		if b in path:
			print("[HiruAI] ⚠️ Blocked delete protected: ", path)
			return false

	var err = DirAccess.remove_absolute(path)
	if err == OK:
		print("[HiruAI] 🗑️ Deleted: ", path)
		return true
	else:
		print("[HiruAI] ❌ Cannot delete: ", path, " (err: ", err, ")")
		return false


# ══════════════════ ANIMATED FILE CARDS ══════════════════

func _add_activity(icon: String, text: String, color: Color = Color.WHITE):
	"""Log detailed agent activity to the AGENT TAB and Thinking Panel."""
	# 1. Internal Log
	var entry = {"icon": icon, "text": text, "color": color, "time": Time.get_ticks_msec()}
	_activity_log.append(entry)
	
	# 2. Update Thinking Panel (Chat Tab)
	_update_thinking(icon + " " + text, _phase_from_icon(icon))
	
	# 3. Update Activity List (Agent Tab)
	if not _activity_panel: return
	var list = _activity_panel.find_child("ActivityList", true, false)
	if not list: return
	
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	
	var ic = Label.new()
	ic.text = icon
	ic.add_theme_font_size_override("font_size", 12)
	row.add_child(ic)
	
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.4))
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	
	list.add_child(row)
	
	# Small animation: pulse the last activity
	var tween = create_tween()
	row.modulate.a = 0
	tween.tween_property(row, "modulate:a", 1.0, 0.2)
	
	# Also show a quick toast in chat for visibility
	_set_status("● " + text.left(20) + "...", color)
	
	# Update Agent Tab Step Counter
	if agent_tab:
		var step_lbl = agent_tab.find_child("StepCount", true, false)
		if step_lbl:
			var steps = list.get_child_count()
			step_lbl.text = str(steps) + " steps"


func _add_thought_card(seconds: int):
	"""Minimal thought duration chip (no expandable content)."""
	if seconds < 1: seconds = 1
	var dur_str = _format_duration(seconds)
	
	var chip = PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st = _sb(Color("#0e0e18"), 8, true, Color("#2a1f4e"))
	st.content_margin_top = 6
	st.content_margin_bottom = 6
	st.content_margin_left = 12
	st.content_margin_right = 12
	chip.add_theme_stylebox_override("panel", st)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	
	var icon = Label.new()
	icon.text = "🧠"
	icon.add_theme_font_size_override("font_size", 12)
	hbox.add_child(icon)
	
	var lbl = Label.new()
	lbl.text = "Thought for " + dur_str
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color("#ab47bc"))
	hbox.add_child(lbl)
	
	chip.add_child(hbox)
	chat_container.add_child(chip)
	
	# Animate entrance
	chip.modulate.a = 0
	var tween = create_tween()
	tween.tween_property(chip, "modulate:a", 1.0, 0.2)
	_scroll_bottom()


func _add_thought_card_with_text(plan: String):
	"""Premium collapsible thought card — compact chip with expandable scroll content."""
	var dur_str = _format_duration(_thinking_duration_sec)
	
	# ── Outer Wrapper ──
	var wrapper = PanelContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var wrap_style = _sb(Color("#0e0e18"), 8, true, Color("#2a1f4e"))
	wrap_style.content_margin_top = 0
	wrap_style.content_margin_bottom = 0
	wrap_style.content_margin_left = 0
	wrap_style.content_margin_right = 0
	wrapper.add_theme_stylebox_override("panel", wrap_style)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	
	# ── Header Chip (always visible, clickable) ──
	var chip = Button.new()
	chip.text = "  🧠 Thought for %s  ▸" % dur_str
	chip.flat = true
	chip.alignment = HORIZONTAL_ALIGNMENT_LEFT
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.add_theme_font_size_override("font_size", 11)
	chip.add_theme_color_override("font_color", Color("#ab47bc"))
	chip.add_theme_color_override("font_hover_color", Color("#ce93d8"))
	chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	
	var chip_normal = _sb(Color.TRANSPARENT, 8)
	chip_normal.content_margin_top = 7
	chip_normal.content_margin_bottom = 7
	chip_normal.content_margin_left = 10
	chip_normal.content_margin_right = 10
	chip.add_theme_stylebox_override("normal", chip_normal)
	var chip_hover = _sb(Color("#161625"), 8)
	chip_hover.content_margin_top = 7
	chip_hover.content_margin_bottom = 7
	chip_hover.content_margin_left = 10
	chip_hover.content_margin_right = 10
	chip.add_theme_stylebox_override("hover", chip_hover)
	chip.add_theme_stylebox_override("pressed", chip_hover)
	vbox.add_child(chip)
	
	# ── Content Panel (hidden by default, scrollable) ──
	var content_panel = PanelContainer.new()
	content_panel.name = "ThoughtContent"
	content_panel.visible = false
	var cp_style = _sb(Color("#0a0a14"), 0)
	cp_style.content_margin_left = 14
	cp_style.content_margin_right = 10
	cp_style.content_margin_top = 2
	cp_style.content_margin_bottom = 8
	content_panel.add_theme_stylebox_override("panel", cp_style)
	
	# Divider line between chip and content
	var divider = ColorRect.new()
	divider.color = Color("#2a1f4e", 0.4)
	divider.custom_minimum_size.y = 1
	
	# ScrollContainer with smart max height
	var line_count = plan.split("\n").size()
	var smart_height = clampi(line_count * 20 + 20, 60, 180)
	
	var scroll_box = ScrollContainer.new()
	scroll_box.custom_minimum_size.y = smart_height
	scroll_box.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll_box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	
	var plan_lbl = RichTextLabel.new()
	plan_lbl.bbcode_enabled = true
	plan_lbl.fit_content = true
	plan_lbl.selection_enabled = true
	plan_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plan_lbl.add_theme_color_override("default_color", Color("#9e9eb0"))
	plan_lbl.add_theme_font_size_override("normal_font_size", 12)
	plan_lbl.text = "[i]" + plan + "[/i]"
	
	scroll_box.add_child(plan_lbl)
	
	var content_vbox = VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", 0)
	content_vbox.add_child(divider)
	content_vbox.add_child(scroll_box)
	content_panel.add_child(content_vbox)
	vbox.add_child(content_panel)
	
	wrapper.add_child(vbox)
	chat_container.add_child(wrapper)
	
	# ── Toggle Animation ──
	chip.pressed.connect(func():
		content_panel.visible = !content_panel.visible
		if content_panel.visible:
			chip.text = "  🧠 Thought for %s  ▾" % dur_str
		else:
			chip.text = "  🧠 Thought for %s  ▸" % dur_str
		_scroll_bottom()
	)
	
	# Animate entrance
	wrapper.modulate.a = 0
	var tween = create_tween()
	tween.tween_property(wrapper, "modulate:a", 1.0, 0.2)
	_scroll_bottom()


func _format_duration(seconds: int) -> String:
	"""Format seconds into a readable duration string."""
	if seconds < 1:
		return "<1s"
	elif seconds >= 60:
		return "%dm %ds" % [seconds / 60, seconds % 60]
	else:
		return "%ds" % seconds

func _add_activity_bubble(text: String, color: Color):
	"""Small minimalist chip in chat Area to show AI's current ACTION."""
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	
	var dot = ColorRect.new()
	dot.custom_minimum_size = Vector2(8, 8)
	dot.color = color
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(dot)
	
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.3))
	hbox.add_child(lbl)
	
	chat_container.add_child(hbox)
	_scroll_bottom()

func _add_file_card(path: String, operation: String, color: Color, diff_str: String = ""):
	"""Cursor-style compact file chip."""
	var chip = PanelContainer.new()
	var style = _sb(C_PANEL, 6, true, color.darkened(0.5))
	chip.add_theme_stylebox_override("panel", style)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	
	var ic = Label.new()
	ic.text = "📄"
	ic.add_theme_font_size_override("font_size", 10)
	hbox.add_child(ic)
	
	var fname = Label.new()
	fname.text = path.get_file()
	fname.add_theme_font_size_override("font_size", 11)
	fname.add_theme_color_override("font_color", Color.WHITE)
	hbox.add_child(fname)
	
	if diff_str != "":
		var diff = Label.new()
		diff.text = diff_str
		diff.add_theme_color_override("font_color", color)
		diff.add_theme_font_size_override("font_size", 9)
		hbox.add_child(diff)
	
	var btn = Button.new()
	btn.flat = true
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(func(): _open_file_in_editor(path))
	
	chip.add_child(hbox)
	chip.add_child(btn)
	chat_container.add_child(chip)
	_scroll_bottom()
	
	# Update Project Tab List
	_update_project_list(path)

func _update_project_list(path: String):
	if not project_tab: return
	var stats = project_tab.find_child("FileStats", true, false)
	if stats:
		if not path in stats.text:
			stats.text += "\n• " + path

func _calculate_diff(old_text: String, new_text: String) -> String:
	var old_lines = old_text.split("\n")
	var new_lines = new_text.split("\n")
	
	var added = 0
	var removed = 0
	
	if old_text == "":
		return "+" + str(new_lines.size()) + " -0"
		
	added = maxi(0, new_lines.size() - old_lines.size())
	removed = maxi(0, old_lines.size() - new_lines.size())
	
	if added == 0 and removed == 0 and old_text != new_text:
		added = 1; removed = 1
		
	return "+" + str(added) + " -" + str(removed)

func _open_file_in_editor(path: String):
	if not Engine.is_editor_hint(): return
	var res = load(path)
	if res:
		EditorInterface.select_file(path)
		EditorInterface.edit_resource(res)
		_set_status("📖 Opened " + path.get_file(), C_AI)
	else:
		_set_status("❌ Cannot find " + path.get_file(), C_ERR)


# ══════════════════ QUICK ACTIONS ══════════════════

func _on_generate():
	_send("Generate a new GDScript for my project. Ask me what kind of script I need, then create and SAVE the complete script file.")

func _on_fix():
	# Read Godot log and send errors
	var Scanner = load("res://addons/hiruai/project_scanner.gd")
	var log_text = Scanner.read_godot_log()
	_send("""[DEBUGGING MISSION]
Analyze the following Godot Log. 
1. Identify the EXACT file and line number causing the error.
2. Use [READ:] to inspect that file around the erroneous line.
3. In your [THOUGHT:], explain WHY the error happened (Logic? Syntax? Missing node?) and how you will solve it definitively.
4. Use [SAVE:] once you are 100% sure of the fix.

GODOT LOG:
%s""" % log_text)

func _on_explain():
	_send("Read all the scripts in my project and explain what each one does in detail.")

func _on_create_node():
	_send("Help me create a new node structure for my project. Ask me what I need, then CREATE and SAVE the .tscn and .gd files.")

func _on_scan():
	var Scanner = load("res://addons/hiruai/project_scanner.gd")
	var tree = Scanner.get_file_tree()
	_add_msg("system", "📂 Project Structure:\n\n" + tree)

func _on_clear():
	_save_current_conversation()
	for child in chat_container.get_children():
		child.queue_free()
	chat_history.clear()
	_tree_sent = false
	_read_files.clear()
	_context_files.clear()
	_update_context_bar()
	_total_tokens = 0
	_update_token_display(0)
	_add_welcome()


# ══════════════════ SETTINGS ══════════════════

func _show_settings():
	var dialog = AcceptDialog.new()
	dialog.title = "🤖 HiruAI Settings"
	dialog.min_size = Vector2(450, 280)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)

	# API Key section
	var key_label = Label.new()
	key_label.text = "NVIDIA API Key:"
	key_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(key_label)

	var key_input = LineEdit.new()
	key_input.placeholder_text = "nvapi-..."
	key_input.secret = true
	key_input.text = kimi.api_key
	vbox.add_child(key_input)

	# Model selection section
	var model_label = Label.new()
	model_label.text = "AI Model Selection:"
	model_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(model_label)

	var model_opt = OptionButton.new()
	var models_dict = kimi.MODELS
	var idx = 0
	var select_idx = 0
	for m_name in models_dict:
		model_opt.add_item(m_name)
		if models_dict[m_name] == kimi.current_model:
			select_idx = idx
		idx += 1
	
	model_opt.add_separator()
	model_opt.add_item("Custom Model...")
	
	if select_idx == 0 and kimi.current_model != models_dict.values()[0]:
		model_opt.select(model_opt.get_item_count() - 1)
	else:
		model_opt.select(select_idx)
	
	vbox.add_child(model_opt)

	var custom_model_input = LineEdit.new()
	custom_model_input.placeholder_text = "provider/model-name"
	custom_model_input.text = kimi.current_model
	custom_model_input.visible = (model_opt.get_selected_id() == model_opt.get_item_count() - 1)
	vbox.add_child(custom_model_input)

	model_opt.item_selected.connect(func(id):
		custom_model_input.visible = (id == model_opt.get_item_count() - 1)
	)

	dialog.add_child(vbox)
	add_child(dialog)

	dialog.confirmed.connect(func():
		var new_key = key_input.text.strip_edges()
		var new_model = ""
		if model_opt.get_selected_id() == model_opt.get_item_count() - 1:
			new_model = custom_model_input.text.strip_edges()
		else:
			new_model = models_dict[model_opt.get_item_text(model_opt.get_selected_id())]
		
		if not new_key.is_empty():
			kimi.save_settings(new_key, new_model)
			_add_msg("system", "✅ Settings saved! Using model: " + new_model)
			_set_status("● Ready (" + new_model.get_file() + ")", Color("#00ff88"))
	)
	dialog.popup_centered()


func _on_play_main():
	if Engine.is_editor_hint():
		EditorInterface.play_main_scene()
		_add_msg("system", "▶️ Running main project scene...")
		_set_status("▶️ Playing", Color("#00ff88"))
		_is_game_running_monitored = true

func _on_play_current():
	if Engine.is_editor_hint():
		EditorInterface.play_current_scene()
		_add_msg("system", "🎬 Running current editor scene...")
		_set_status("🎬 Playing", Color("#42a5f5"))
		_is_game_running_monitored = true

func _on_stop_game():
	if Engine.is_editor_hint():
		EditorInterface.stop_playing_scene()
		_add_msg("system", "⏹️ Game execution stopped.")
		_set_status("● Ready", Color("#00ff88"))
		_is_game_running_monitored = false

func _on_self_healing_toggled(on: bool):
	_self_healing_enabled = on
	var btn = find_child("HealBtn", true, false)
	if btn:
		btn.text = "🔁 Self-Healing: ON" if on else "🔁 Self-Healing: OFF"
		_style_btn(btn, Color("#00e676") if on else Color("#2d1b69"))
	
	if on:
		_add_msg("system", "🔁 **Self-Healing Loop Active!**\nAI will now automatically run the game after you Accept changes and fix any errors it finds.")
	else:
		_add_msg("system", "⏸ **Self-Healing Loop Disabled.**")

func _process(_delta):
	if _self_healing_enabled and _is_game_running_monitored:
		if not EditorInterface.is_playing_scene():
			_is_game_running_monitored = false
			_add_msg("system", "🏁 Game stopped. Scanning for errors...")
			_auto_check_errors()

func _auto_check_errors():
	# Simple debounce/wait for logs to flush
	await get_tree().create_timer(0.5).timeout
	var Scanner = load("res://addons/hiruai/project_scanner.gd")
	var log_text = Scanner.read_godot_log()
	
	if "error" in log_text.to_lower() or "warning" in log_text.to_lower():
		_add_msg("system", "⚠️ Errors detected in log! Sending to AI for autonomous fix...")
		_send("[DEBUGGING MISSION]\nI just ran the game and found these errors in the log. \nPlease analyze and fix them automatically until the code works perfectly:\n\n" + log_text)
	else:
		_add_msg("system", "✅ No critical errors found in logs after test run.")


func _check_syntax_error(code: String) -> String:
	"""Check if GDScript code has basic syntax errors."""
	var script = GDScript.new()
	script.source_code = code
	var err = script.reload()
	if err != OK:
		# Map common error codes
		match err:
			ERR_PARSE_ERROR: return "Parse Error (Check for typos, missing colons, or invalid keywords)"
			ERR_COMPILATION_FAILED: return "Compilation Failed (Indentation or syntax error)"
			_: return "Syntax Error (Godot Error Code: %d)" % err
	return ""


func _find_missing_preloads(saves: Array[Dictionary]) -> Array[Dictionary]:
	"""Scan code in saves for preload() of non-existent files to force AI to generate them."""
	var missing: Array[Dictionary] = []
	var all_save_paths: Array[String] = []
	for s in saves:
		all_save_paths.append(s["path"])
	
	var rx = RegEx.new()
	rx.compile('preload\\s*\\(\\s*"([^"]+)"\\s*\\)')
	
	for s in saves:
		var spath = s["path"]
		for m in rx.search_all(s["content"]):
			var dep_path: String = m.get_string(1)
			# Normalize path
			if not dep_path.begins_with("res://"):
				dep_path = "res://" + dep_path.trim_prefix("/")
			# Skip if file already exists on disk
			if FileAccess.file_exists(dep_path):
				continue
			# Skip if already being saved in this batch
			if dep_path in all_save_paths:
				continue
			
			var already_added = false
			for mis in missing:
				if mis["source"] == spath and mis["missing"] == dep_path:
					already_added = true
			if not already_added:
				missing.append({
					"source": spath,
					"missing": dep_path
				})
	return missing



func _extract_run_game(text: String) -> String:
	"""Extract [RUN_GAME:type] tags."""
	var rx = RegEx.new()
	rx.compile("\\[RUN_GAME:(main|current)\\]")
	var m = rx.search(text)
	if m:
		return m.get_string(1)
	return ""


# ══════════════════ SYSTEM PROMPT ══════════════════

func _system_prompt() -> String:
	return """You are **Hiru**, an elite AI coding agent for Godot 4.x (GDScript).
You have DIRECT file-system access to the user's Godot project.
You are NOT a chatbot — you are a professional coding agent like Cursor, Copilot, or Windsurf.

═══ YOUR IDENTITY ═══
- Name: Hiru (Lead Godot Systems Architect & AI Agent)
- Environment: Godot Engine 4.x (GDScript)
- Role: You are a principal 10x developer. You do not just write scripts; you ENGINEER fully functional, interconnected systems. You build robust, scalable, and production-ready architectures.
- Languages: English & Indonesian (Professional/Santai).

═══ THE MASTERMIND PROTOCOL (STRICT) ═══
You operate in a continuous cycle of Planning, Gathering Context, Execution, and Validation. For EVERY response:

1. **DEEP THOUGHT & STRATEGY [THOUGHT]** (MANDATORY):
   - **[THOUGHT:] is REQUIRED.** You must ALWAYS start with a detailed technical breakdown.
   - You must act as a Senior Architect. Instead of patching small holes, look at the big picture. How does this new feature interact with the existing system?
   - Formulate a 100% complete step-by-step plan before writing any code. Check for edge cases, missing nodes, or potential null references.
   - Example: `[THOUGHT: Building an inventory. Steps: 1. SEARCH for existing item definitions. 2. READ GameManager to understand global state. 3. SAVE a new Inventory.gd Autoload. 4. SAVE an InventoryUI.tscn (Control) to display it. 5. Modify Player to emit 'item_picked_up' signals. Risk: Must ensure InventoryUI is properly instanced.]`

2. **RESOURCES ACQUISITION [PRE-ACTION]** (MANDATORY BEFORE SAVING):
   - **NO GUESSWORK.** If you don't confidently know the exact names of nodes, variables, or functions in a file, you MUST [READ:] or [SEARCH:] it first.
   - Never assume the structure of `player.gd` or `main.tscn`. Scan them.

3. **SURGICAL EXECUTION [ACTION]**:
   - Use `[SAVE:res://path.gd]` to update or create files.
   - **CRITICAL - NO LAZY CODE**: You MUST output the ENTIRE file. Never use comments like `# ... rest of existing code ...` or `# ... implementation here ...`. If you leave out existing code, it WILL be deleted permanently.
   - **SYSTEM COMPLETENESS**: If you make a new script that needs a UI, you MUST also output the `[SAVE:...]` block to create that `.tscn` file. Don't leave the user with half a feature.

4. **FINAL VALIDATION [RESULT]**:
   - Start with `[RESULT:]`.
   - Provide a concise summary of systems built or fixed.
   - **Crucial Editor Instructions**: Since you cannot click inside the Godot Editor, you MUST explicitly tell the user if they need to:
     - Add a script to Autoload (Project Settings).
     - Assign a specific Node Path in the inspector.
     - Connect a signal manually via the Editor UI.

═══ ERROR PREVENTION PROTOCOLS (STRICT) ═══
- **MENTAL COMPILATION**: Before saving, verify: Unclosed brackets/parentheses, missing colons `if x:`, correct tab-based indentation, and matching `if/elif/else` blocks.
- **CIRCULAR DEPENDENCY**: Never use `preload()` for scripts that depend on each other. Use `load()` strings instead.
- **PRELOAD COMPLETENESS**: If you `preload("res://SomeFile.tscn")`, that file MUST exist. If it doesn't, you MUST generate its code using `[SAVE:res://SomeFile.tscn]` in the exact same response.
- **DEFENSIVE PROGRAMMING**: 
  - ALWAYS use `is_instance_valid(node)` or `if node != null:` before calling methods on dynamic nodes.
  - Assume `get_node()` or `$` might fail. Use `@onready` and check for nulls.
  - Check `if not signal.is_connected(callable):` before connecting via code.

═══ GODOT 4.X MASTER ARCHITECTURE ═══
- **STATIC TYPING**: Be strictly typed. (`var health: float = 100.0`, `func move(dir: Vector2) -> void:`). This stops bugs before they happen.
- **DECOUPLING VIA SIGNALS**: Children should NEVER `get_parent()`. Children emit signals (`signal health_depleted`), parents connect and react.
- **STATE MACHINES**: Use enums (`enum State {IDLE, WALK}`) and `match state:` statements for complex logic (Player/Enemy AI) instead of spaghetti `if/else`.
- **UI RESPONSIVENESS**: Use Godot's built-in containers (`VBoxContainer`, `MarginContainer`, `GridContainer`). Do NOT manually set positions/sizes in code for UI elements.

═══ AUTONOMOUS HARD RULES ═══
- **PLAN FIRST, ACT SECOND**: [THOUGHT:] → [READ:]/[SEARCH:] → [SAVE:]. Skipping [THOUGHT:] is a CRITICAL violation.
- **DEBUGGING IS SURGICAL**: If fixing an error, DO NOT just guess. Find the exact file and line number mentioned in the error. Use [READ:] to look at that line. Analyze why it crashed, then fix the root cause, not the symptom.
- **PERSISTENT DEBUGGING**: If your fix fails twice, STOP. Your assumption is wrong. Use [SEARCH:] to find where the variable is actually defined or modified globally.
- **NO CHATTY FILLER**: Minimize apologetic fluff ("I'm sorry", "My apologies"). You are a cold, precise engineering machine. Act like it.

═══ COMMANDS REFERENCE ═══
[SEARCH:keyword] — Global project search for definitions.
[READ:res://...] — Read file (max 150 lines).
[READ_LINES:res://...:start-end] — Precise line reading.
[SAVE:res://...] — Write 100% full file content.
[DELETE:res://...] — Erase file from disk.
"""


# ══════════════════ NEW FEATURES ══════════════════

func _build_history_area():
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	var title = Label.new()
	title.text = "CONVERSATIONS"
	title.add_theme_color_override("font_color", C_ACCENT)
	title.add_theme_font_size_override("font_size", 11)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	
	var new_btn = Button.new()
	new_btn.text = "+ New"
	new_btn.flat = true
	new_btn.add_theme_font_size_override("font_size", 10)
	new_btn.add_theme_color_override("font_color", C_ACCENT_ALT)
	new_btn.pressed.connect(_on_new_conversation)
	new_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	header.add_child(new_btn)
	vbox.add_child(header)
	
	var conv_scroll = ScrollContainer.new()
	conv_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	var conv_list = VBoxContainer.new()
	conv_list.name = "ConversationList"
	conv_list.add_theme_constant_override("separation", 4)
	conv_scroll.add_child(conv_list)
	vbox.add_child(conv_scroll)
	
	var hint = Label.new()
	hint.text = "Conversations are saved when you clear or start new."
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", Color(C_TEXT_DIM, 0.5))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)
	
	margin.add_child(vbox)
	history_tab.add_child(margin)

func _build_context_bar():
	"""Context bar showing files currently in AI context."""
	var bar = PanelContainer.new()
	bar.name = "ContextBar"
	var st = _sb(Color("#0a0a12"), 0)
	st.content_margin_top = 3
	st.content_margin_bottom = 3
	st.content_margin_left = 8
	bar.add_theme_stylebox_override("panel", st)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	
	var ctx_icon = Label.new()
	ctx_icon.text = "📎"
	ctx_icon.add_theme_font_size_override("font_size", 10)
	hbox.add_child(ctx_icon)
	
	var ctx_label = Label.new()
	ctx_label.name = "ContextLabel"
	ctx_label.text = "No files in context"
	ctx_label.add_theme_font_size_override("font_size", 9)
	ctx_label.add_theme_color_override("font_color", C_TEXT_DIM)
	ctx_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctx_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hbox.add_child(ctx_label)
	
	bar.add_child(hbox)
	add_child(bar)

func _update_context_bar():
	var bar = find_child("ContextBar", true, false)
	if not bar: return
	var lbl = bar.find_child("ContextLabel", true, false)
	if not lbl: return
	if _context_files.is_empty():
		lbl.text = "No files in context"
	else:
		var names = []
		for f in _context_files:
			names.append(f.get_file())
		lbl.text = ", ".join(names)

func _update_token_display(tokens: int = 0):
	_total_tokens += tokens
	if _token_count_label:
		if _total_tokens > 1000:
			_token_count_label.text = "%.1fk" % (_total_tokens / 1000.0)
		else:
			_token_count_label.text = "%d tok" % _total_tokens

func _show_quick_model_menu():
	var popup = PopupMenu.new()
	popup.name = "ModelPopup"
	var models = kimi.MODELS
	var idx = 0
	for m_name in models:
		popup.add_item(m_name, idx)
		if models[m_name] == kimi.current_model:
			popup.set_item_disabled(idx, true)
			popup.set_item_text(idx, "✓ " + m_name)
		idx += 1
	popup.id_pressed.connect(func(id):
		var keys = models.keys()
		if id < keys.size():
			var new_model = models[keys[id]]
			kimi.current_model = new_model
			kimi.save_settings(kimi.api_key, new_model)
			if _model_quick_btn:
				_model_quick_btn.text = " ⚡ " + new_model.get_file().left(12)
			_add_msg("system", "✅ Model switched to: " + new_model.get_file())
		popup.queue_free()
	)
	add_child(popup)
	popup.popup(Rect2(get_global_mouse_position(), Vector2(200, 0)))

func _show_slash_suggestions(text: String):
	var commands = {
		"/fix": "🔧 Auto-fix errors from Godot log",
		"/explain": "💡 Explain project code",
		"/generate": "📝 Generate new GDScript",
		"/refactor": "♻️ Refactor and clean up code",
		"/optimize": "⚡ Optimize performance",
		"/test": "🧪 Generate unit tests",
		"/scan": "📂 Scan project structure",
		"/undo": "↩️ Undo last file edits",
		"/clear": "🗑️ Clear chat history",
	}
	
	var filtered = {}
	for cmd in commands:
		if cmd.begins_with(text.strip_edges().to_lower()) or text.strip_edges() == "/":
			filtered[cmd] = commands[cmd]
	
	if filtered.is_empty():
		if _cmd_popup and _cmd_popup.visible:
			_cmd_popup.hide()
		return
	
	_show_command_list(filtered)

func _show_command_palette():
	var commands = {
		"/fix": "🔧 Auto-fix errors from Godot log",
		"/explain": "💡 Explain project code",
		"/generate": "📝 Generate new GDScript",
		"/refactor": "♻️ Refactor and clean up code",
		"/optimize": "⚡ Optimize performance",
		"/test": "🧪 Generate unit tests",
		"/scan": "📂 Scan project structure",
		"/undo": "↩️ Undo last file edits",
		"/clear": "🗑️ Clear chat history",
	}
	_show_command_list(commands)

func _show_command_list(commands: Dictionary):
	if _cmd_popup and is_instance_valid(_cmd_popup):
		_cmd_popup.queue_free()
	
	_cmd_popup = PopupPanel.new()
	_cmd_popup.name = "CmdPopup"
	var popup_style = _sb(C_PANEL, 8, true, C_BORDER)
	_cmd_popup.add_theme_stylebox_override("panel", popup_style)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	
	var title = Label.new()
	title.text = "Commands"
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", C_TEXT_DIM)
	vbox.add_child(title)
	
	for cmd in commands:
		var btn = Button.new()
		btn.text = cmd + "  " + commands[cmd]
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 11)
		btn.add_theme_color_override("font_color", C_TEXT)
		btn.add_theme_color_override("font_hover_color", C_ACCENT)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var cmd_bind = cmd
		btn.pressed.connect(func():
			input_field.text = cmd_bind + " "
			input_field.set_caret_column(input_field.text.length())
			_cmd_popup.hide()
		)
		vbox.add_child(btn)
	
	_cmd_popup.add_child(vbox)
	add_child(_cmd_popup)
	
	var pos = input_field.get_global_rect().position
	pos.y -= commands.size() * 24 + 40
	_cmd_popup.popup(Rect2(pos, Vector2(280, 0)))

func _handle_slash_command(text: String) -> bool:
	var parts = text.split(" ", true, 2)
	var cmd = parts[0].to_lower()
	var args = parts[1] if parts.size() > 1 else ""
	
	match cmd:
		"/fix":
			_on_fix()
			return true
		"/explain":
			_on_explain()
			return true
		"/generate":
			if args != "":
				_send("Generate a GDScript for: " + args + ". Create and SAVE the complete script file.")
			else:
				_on_generate()
			return true
		"/refactor":
			if args != "":
				_send("Refactor and clean up this code/file: " + args + ". Read the file first, then SAVE the improved version.")
			else:
				_send("Read all scripts in my project and suggest refactoring improvements. Focus on code quality, readability, and performance.")
			return true
		"/optimize":
			_send("Analyze my project for performance issues. Read the scripts and suggest/apply optimizations. Focus on: signal usage, _process efficiency, memory management, node references.")
			return true
		"/test":
			if args != "":
				_send("Generate GDScript unit tests for: " + args + ". SAVE the test file to res://tests/.")
			else:
				_send("Generate unit tests for my main game scripts. SAVE them to res://tests/.")
			return true
		"/scan":
			_on_scan()
			return true
		"/undo":
			_on_undo()
			return true
		"/clear":
			_on_clear()
			return true
		_:
			return false

func _on_undo():
	if _undo_stack.is_empty():
		_add_msg("system", "⚠️ Nothing to undo.")
		return
	
	_add_msg("system", "↩️ Undoing last %d changes..." % _undo_stack.size())
	
	for action in _undo_stack:
		var path = action["path"]
		var type = action["type"]
		var old_content = action["content"]
		
		match type:
			"save":
				_write_project_file(path, old_content)
				_add_activity("↩️", "Restored: " + path.get_file(), C_SAVE)
			"create":
				_delete_project_file(path)
				_add_activity("↩️", "Deleted created file: " + path.get_file(), C_DELETE)
			"delete":
				_write_project_file(path, old_content)
				_add_activity("↩️", "Restored deleted file: " + path.get_file(), C_SAVE)
	
	var fs = EditorInterface.get_resource_filesystem() if Engine.is_editor_hint() else null
	if fs: fs.scan()
	
	_undo_stack.clear()
	_add_msg("system", "✅ Undo complete.")

func _on_new_conversation():
	_save_current_conversation()
	_on_clear()

func _save_current_conversation():
	if chat_history.size() == 0:
		return
	
	# Generate title from first user message
	var title = _current_conversation_title
	if title == "":
		for msg in chat_history:
			if msg["role"] == "user":
				title = msg["content"].left(40).strip_edges()
				if title.length() >= 38:
					title += "..."
				break
		if title == "":
			title = "Conversation %d" % (_conversation_list.size() + 1)
	
	_conversation_list.append({
		"title": title,
		"messages": chat_history.duplicate(true),
		"timestamp": Time.get_datetime_string_from_system()
	})
	_current_conversation_title = ""
	_refresh_history_list()

func _refresh_history_list():
	if not history_tab: return
	var list = history_tab.find_child("ConversationList", true, false)
	if not list: return
	for c in list.get_children(): c.queue_free()
	
	for i in range(_conversation_list.size() - 1, -1, -1):
		var conv = _conversation_list[i]
		var card = PanelContainer.new()
		var st = _sb(C_PANEL, 6, true, C_BORDER)
		st.content_margin_top = 6
		st.content_margin_bottom = 6
		card.add_theme_stylebox_override("panel", st)
		
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)
		
		var ic = Label.new()
		ic.text = "💬"
		ic.add_theme_font_size_override("font_size", 12)
		hbox.add_child(ic)
		
		var text_vbox = VBoxContainer.new()
		text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var t = Label.new()
		t.text = conv["title"]
		t.add_theme_font_size_override("font_size", 11)
		t.add_theme_color_override("font_color", Color.WHITE)
		t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		text_vbox.add_child(t)
		var ts = Label.new()
		ts.text = conv.get("timestamp", "")
		ts.add_theme_font_size_override("font_size", 9)
		ts.add_theme_color_override("font_color", C_TEXT_DIM)
		text_vbox.add_child(ts)
		hbox.add_child(text_vbox)
		
		var load_btn = Button.new()
		load_btn.text = "↩"
		load_btn.flat = true
		load_btn.add_theme_color_override("font_color", C_ACCENT_ALT)
		load_btn.tooltip_text = "Load this conversation"
		var idx_bind = i
		load_btn.pressed.connect(func(): _load_conversation(idx_bind))
		load_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		hbox.add_child(load_btn)
		
		card.add_child(hbox)
		list.add_child(card)

func _load_conversation(idx: int):
	if idx < 0 or idx >= _conversation_list.size(): return
	var conv = _conversation_list[idx]
	
	# Clear current
	for child in chat_container.get_children():
		child.queue_free()
	
	chat_history = conv["messages"].duplicate(true)
	_current_conversation_title = conv["title"]
	_tree_sent = true
	
	# Replay messages visually
	for msg in chat_history:
		if msg["role"] == "user":
			_add_msg("user", msg["content"].left(200))
		elif msg["role"] == "assistant":
			_add_msg("ai", _clean_display_text(msg["content"]))
	
	tabs.current_tab = 0
	_update_nav_active(0)
	_add_msg("system", "📜 Loaded conversation: " + conv["title"])
