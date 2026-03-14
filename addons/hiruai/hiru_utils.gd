@tool
extends Node
class_name HiruUtils

static func sb(color: Color, radius: int = 8, border: bool = false, b_color: Color = Color.TRANSPARENT) -> StyleBoxFlat:
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

static func style_btn(btn: Button, bg: Color = HiruConst.C_BTN):
	var radius := 6
	btn.add_theme_stylebox_override("normal", sb(bg, radius, true, bg.lightened(0.1)))
	btn.add_theme_stylebox_override("hover", sb(bg.lightened(0.15), radius, true, HiruConst.C_ACCENT))
	btn.add_theme_stylebox_override("pressed", sb(bg.darkened(0.2), radius, true, HiruConst.C_ACCENT.lightened(0.3)))
	btn.add_theme_color_override("font_color", HiruConst.C_TEXT)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_font_size_override("font_size", 14)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

static func fmt(text: String) -> String:
	var r = text
	var rx = RegEx.new()
	
	# 1. Multiline Code Blocks
	rx.compile("```([a-zA-Z0-9_ \\t]*\\n)?([\\s\\S]*?)```")
	for m in rx.search_all(r):
		var lang = m.get_string(1).strip_edges()
		if lang == "": lang = "code"
		var content = m.get_string(2).strip_edges()
		var header = "[b][color=#a87ffb] 📝 " + lang + " [/color][/b]\n"
		var block = header + "[color=#a8c7fa][code]" + content + "[/code][/color]\n"
		r = r.replace(m.get_string(), block)
		
	# 2. Headings
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

static func clean_display_text(text: String) -> String:
	var result = text
	
	# Clear THOUGHTS (Smart cleaning for streaming)
	# This hides thoughts even before the closing tag is received, without wiping the whole message
	var thought_patterns = [
		"(?is)\\[THOUGHT:?\\s*[\\s\\S]*?(\\[/THOUGHT\\]|$)",
		"(?is)<thought>[\\s\\S]*?(</thought>|$)",
		"(?is)<think>[\\s\\S]*?(</think>|$)"
	]
	for p in thought_patterns:
		var rx_t = RegEx.new()
		rx_t.compile(p)
		result = rx_t.sub(result, "", true)

	# If only partial tags remain (e.g. at the start), clear them without wiping the whole rest of message
	result = result.replace("[THOUGHT]", "").replace("[/THOUGHT]", "").replace("<thought>", "").replace("</thought>", "").replace("<think>", "").replace("</think>", "")

	# Clear SAVE/REPLACE tags (Smart cleaning for streaming/partial content)
	var save_repro_patterns = [
		"(?is)\\[(SAVE|REPLACE):[^\\]]*\\][\\s\\S]*?(\\[(?:/SAVE|END_SAVE|/REPLACE)\\]|(?=\\[(SAVE|REPLACE|READ|SEARCH|THOUGHT))|$)",
		"(?is)\\[(SAVE|REPLACE):[^\\]]*\\]\\s*```[\\s\\S]*?(```|$)"
	]
	for sp in save_repro_patterns:
		var s_rx = RegEx.new()
		s_rx.compile(sp)
		result = s_rx.sub(result, "", true)

	# Clear other commmands
	var tech_rx = RegEx.new()
	tech_rx.compile("(?is)\\[(SAVE|REPLACE|READ|READ_LINES|SEARCH|DELETE|SCENE_SCAN|SKILL_SYNC|RUN_GAME|RUN_CHECK|RESULT|SCAN_TREE):[\\s\\S]*?(\\]+|$)")
	result = tech_rx.sub(result, "", true)
	
	result = result.replace("[SCAN_TREE]", "").replace("[RUN_CHECK]", "")

	# Clear blocks like [PLAN] and [PROGRESS]
	var block_patterns = [
		"(?is)\\[PLAN\\][\\s\\S]*?\\[/PLAN\\]",
		"(?is)\\[PROGRESS\\][\\s\\S]*?\\[/PROGRESS\\]"
	]
	for bp in block_patterns:
		var brx = RegEx.new()
		brx.compile(bp)
		result = brx.sub(result, "", true)

	result = result.replace("[PLAN]", "").replace("[/PLAN]", "").replace("[PROGRESS]", "").replace("[/PROGRESS]", "")

	# Clean repetitive phrases
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

	result = result.replace("[RESULT:]\n", "").replace("[RESULT:]", "").replace("[RESULT: ]\n", "").replace("[RESULT: ]", "")

	# Clear XML-style tags
	var xml_tags = ["read", "read_lines", "search", "delete", "scene_scan", "save", "replace"]
	for tag in xml_tags:
		var xml_rx = RegEx.new()
		xml_rx.compile("(?is)<" + tag + "[^>]*>[\\s\\S]*?</" + tag + ">")
		result = xml_rx.sub(result, "", true)
		xml_rx.compile("(?is)<" + tag + "[^>]*/>")
		result = xml_rx.sub(result, "", true)
		xml_rx.compile("(?is)<" + tag + ":[^>]+>")
		result = xml_rx.sub(result, "", true)

	var protocol_rx = RegEx.new()
	protocol_rx.compile("(?im)^\\s*(SAVE|REPLACE|READ|READ_LINES|SEARCH|DELETE|SCENE_SCAN|SKILL_SYNC|RUN_GAME|RESULT):.*$")
	result = protocol_rx.sub(result, "", true)
	
	var tag_rx = RegEx.new()
	tag_rx.compile("(?i)\\[\\s*/?\\s*(SAVE|REPLACE|THOUGHT|READ|SEARCH|DELETE|SCENE_SCAN|SKILL_SYNC|RUN_GAME|RESULT|END_SAVE|READ_LINES)\\s*:?[\\s\\S]*?\\]+")
	result = tag_rx.sub(result, "", true)
	
	var placeholders = ["[/SAVE]", "[END_SAVE]", "[/REPLACE]", "[/THOUGHT]", "[/READ]", "<thought>", "</thought>"]
	for p in placeholders:
		result = result.replace(p, "")

	# 5. Final pass for leading residue (commas, dots, formatting leftovers)
	result = result.strip_edges()
	var junk := true
	while junk and result.length() > 0:
		junk = false
		for char in [".", ",", ";", ":", " ", "\n", "\r", "\t"]:
			if result.begins_with(char):
				result = result.substr(1).strip_edges()
				junk = true
				break

	return result

static func format_duration(seconds: int) -> String:
	if seconds < 1: return "<1s"
	elif seconds >= 60: return "%dm %ds" % [seconds / 60, seconds % 60]
	else: return "%ds" % seconds

static func phase_from_icon(icon: String) -> String:
	match icon:
		"📂", "🔍": return "scan"
		"📖": return "read"
		"✏️", "💾": return "edit"
		"🧠": return "think"
		"⏳": return "wait"
		_: return "wait"
