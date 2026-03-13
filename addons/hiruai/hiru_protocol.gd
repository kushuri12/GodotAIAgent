@tool
extends Node
class_name HiruProtocol

static func extract_searches(text: String) -> Array[String]:
	var results: Array[String] = []
	var rx = RegEx.new()
	rx.compile("\\[SEARCH:([^\\]]+)\\]|<search:([^>]+)>|<search>\\s*(.*?)\\s*</search>")
	for m in rx.search_all(text):
		var k = ""
		for i in range(1, 4):
			if m.get_string(i) != "":
				k = m.get_string(i).strip_edges()
				break
		if k != "" and k not in results:
			results.append(k)
	return results

static func extract_reads(text: String) -> Array[String]:
	var paths: Array[String] = []
	var rx = RegEx.new()
	# Support [READ:path], <read:path>, <read>path</read>, and legacy parameter tags
	rx.compile("\\[READ:([^\\]]+)\\]|<read:([^>]+)>|<read>\\s*(.*?)\\s*</read>|<parameter=file>\\s*(.*?)\\s*</parameter>")
	for m in rx.search_all(text):
		var p = ""
		for i in range(1, 5):
			if m.get_string(i) != "":
				p = m.get_string(i)
				break
		
		p = p.replace(" ", "").replace("\n", "").replace("\r", "").strip_edges()
		if p != "" and not p.begins_with("res://"): p = "res://" + p.trim_prefix("/")
		if p != "" and p not in paths: paths.append(p)
	return paths

static func extract_read_lines(text: String) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var rx = RegEx.new()
	# Support [READ_LINES:path:start-end], <read_lines:path:start-end>, and <read_lines path="..." start="..." end="..."/>
	rx.compile("(?:\\[READ_LINES:| <read_lines\\s*path=\")\\s*(.+?)\\s*(?::| \"\\s*start=\")\\s*(\\d+)\\s*(?:-| \"\\s*end=\")\\s*(\\d+)\\s*(?:\\]|\"\\/>)")
	
	var rx2 = RegEx.new()
	rx2.compile("<read_lines:([^:]+):(\\d+)-(\\d+)>")
	
	for m in rx.search_all(text):
		var p = m.get_string(1).replace(" ", "").replace("\n", "").replace("\r", "").strip_edges()
		if not p.begins_with("res://"): p = "res://" + p.trim_prefix("/")
		results.append({
			"path": p,
			"start": int(m.get_string(2)),
			"end": int(m.get_string(3))
		})
	for m in rx2.search_all(text):
		var p = m.get_string(1).replace(" ", "").replace("\n", "").replace("\r", "").strip_edges()
		if not p.begins_with("res://"): p = "res://" + p.trim_prefix("/")
		results.append({
			"path": p,
			"start": int(m.get_string(2)),
			"end": int(m.get_string(3))
		})
	return results

static func extract_replaces(text: String) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var patterns = [
		"\\[REPLACE:\\s*(.+?)\\s*:\\s*(\\d+)\\s*-\\s*(\\d+)\\s*\\][\\s\\S]*?```(?:[a-zA-Z0-9_ \\t]*\\n)?([\\s\\S]*?)```",
		"<replace\\s*path=\"([^\"]+)\"\\s*start=\"(\\d+)\"\\s*end=\"(\\d+)\">\\s*(?:```[\\s\\S]*?```|([\\s\\S]*?))\\s*<\\/replace>",
		"<replace:([^:]+):(\\d+)-(\\d+)>[\\s\\S]*?```(?:[a-zA-Z0-9_ \\t]*\\n)?([\\s\\S]*?)```"
	]
	
	for p_str in patterns:
		var rx = RegEx.new()
		rx.compile(p_str)
		for m in rx.search_all(text):
			var p = m.get_string(1).strip_edges()
			if not p.begins_with("res://"): p = "res://" + p.trim_prefix("/")
			var content = m.get_string(4)
			# Fallback if XML content wasn't in backticks
			if content == "" and m.get_group_count() >= 4: content = m.get_string(4)
			
			results.append({
				"path": p,
				"start": int(m.get_string(2)),
				"end": int(m.get_string(3)),
				"content": content
			})
	return results

static func extract_scene_scans(text: String) -> Array[String]:
	var results: Array[String] = []
	var rx = RegEx.new()
	rx.compile("\\[SCENE_SCAN:([^\\]]+)\\]|<scene_scan:([^>]+)>|<scene_scan>\\s*(.*?)\\s*</scene_scan>")
	for m in rx.search_all(text):
		var p = ""
		for i in range(1, 4):
			if m.get_string(i) != "":
				p = m.get_string(i).strip_edges()
				break
		if not p.begins_with("res://"): p = "res://" + p.trim_prefix("/")
		if p not in results: results.append(p)
	return results

static func extract_thoughts(text: String, allow_partial: bool = false) -> String:
	var patterns = [
		"(?is)\\[THOUGHT:?\\s*([\\s\\S]*?)\\[/THOUGHT\\]",
		"(?is)<thought>([\\s\\S]*?)</thought>"
	]
	if allow_partial:
		patterns.append("(?is)\\[THOUGHT:?\\s*[^]]*\\]([\\s\\S]*)$")
		patterns.append("(?is)<thought>([\\s\\S]*)$")
	for p in patterns:
		var rx = RegEx.new()
		rx.compile(p)
		var m = rx.search(text)
		if m and m.get_string(1).strip_edges() != "":
			return m.get_string(1).strip_edges()
	if allow_partial and "[THOUGHT]" in text:
		var start = text.find("[THOUGHT]") + 9
		return text.substr(start).strip_edges()
	if allow_partial and "<thought>" in text:
		var start = text.find("<thought>") + 9
		return text.substr(start).strip_edges()
	return ""

static func extract_saves(text: String) -> Array[Dictionary]:
	var saves: Array[Dictionary] = []
	var claimed_blocks: Array[String] = []
	var save_patterns = [
		"\\[SAVE:([^\\]]+)\\][\\s\\S]*?```(?:[a-zA-Z0-9_ \\t]*\\n)?([\\s\\S]*?)```",
		"\\[SAVE:([^\\]]+)\\]([\\s\\S]*?)\\[(?:/SAVE|END_SAVE)\\]",
		"<save\\s*path=\"([^\"]+)\">\\s*(?:```(?:[a-zA-Z0-9_ \\t]*\\n)?([\\s\\S]*?)```|([\\s\\S]*?))\\s*<\\/save>",
		"<save:([^>]+)>\\s*```(?:[a-zA-Z0-9_ \\t]*\\n)?([\\s\\S]*?)```"
	]
	for pattern in save_patterns:
		var rx_strict = RegEx.new()
		rx_strict.compile(pattern)
		var matches = rx_strict.search_all(text)
		for m in matches:
			var path = m.get_string(1).strip_edges()
			var raw_content = m.get_string(2)
			if raw_content == "" and m.get_group_count() >= 3:
				raw_content = m.get_string(3)
			
			if raw_content == "": continue
			
			saves.append({
				"path": path,
				"content": clean_extraneous_gdscript(raw_content)
			})
			claimed_blocks.append(raw_content)

	var rx_code = RegEx.new()
	rx_code.compile("```(?:[a-zA-Z0-9_ \\t]*\\n)?([\\s\\S]*?)```")
	var code_matches = rx_code.search_all(text)
	for m_code in code_matches:
		var raw_content = m_code.get_string(1)
		var is_claimed = false
		for cb in claimed_blocks:
			if raw_content.strip_edges() == cb.strip_edges():
				is_claimed = true; break
		if is_claimed: continue
		var start_pos = m_code.get_start()
		var check_start = maxi(0, start_pos - 150)
		var pre_text = text.substr(check_start, start_pos - check_start)
		var rx_path = RegEx.new()
		rx_path.compile("(res://[a-zA-Z0-9_\\-\\./\\\\]+\\.[a-zA-Z0-9_]+)")
		var path_matches = rx_path.search_all(pre_text)
		var found_path = ""
		if path_matches.size() > 0:
			found_path = path_matches[path_matches.size() - 1].get_string(1).strip_edges()
		else:
			var first_line = raw_content.split("\n")[0].strip_edges()
			if first_line.begins_with("#") and "res://" in first_line:
				var c_rx = RegEx.new()
				c_rx.compile("(res://[a-zA-Z0-9_\\-\\./\\\\]+\\.[a-zA-Z0-9_]+)")
				var cm = c_rx.search(first_line)
				if cm: found_path = cm.get_string(1).strip_edges()
		if found_path != "":
			saves.append({
				"path": found_path,
				"content": clean_extraneous_gdscript(raw_content)
			})
			claimed_blocks.append(raw_content)

	var rx_no_backticks = RegEx.new()
	rx_no_backticks.compile("\\[SAVE:([^\\]]+)\\]")
	var no_bt_matches = rx_no_backticks.search_all(text)
	for i in no_bt_matches.size():
		var path = no_bt_matches[i].get_string(1).strip_edges()
		var already_has = false
		for s in saves:
			if s["path"] == path: already_has = true; break
		if already_has: continue
		var start_pos = no_bt_matches[i].get_end()
		var end_pos = text.length()
		if i + 1 < no_bt_matches.size(): end_pos = no_bt_matches[i + 1].get_start()
		var next_tag = text.find("[", start_pos)
		if next_tag != -1 and not text.substr(next_tag, 6).begins_with("[node") and not text.substr(next_tag, 4).begins_with("[gd_"):
			end_pos = mini(end_pos, next_tag)
		var block_content = text.substr(start_pos, end_pos - start_pos).strip_edges()
		if block_content != "":
			saves.append({
				"path": path,
				"content": clean_extraneous_gdscript(strip_code_boilerplate(block_content))
			})
	return saves

static func clean_extraneous_gdscript(code: String) -> String:
	var result = code.strip_edges()
	if result.begins_with("gdscript"):
		var after = result.substr(8).strip_edges()
		if after.begins_with("extends ") or after.begins_with("class_name ") or after.begins_with("@") or after.begins_with("func ") or after.begins_with("var ") or after.begins_with("const ") or after.begins_with("signal ") or after.begins_with("#"):
			return after
	return result

static func strip_code_boilerplate(block: String) -> String:
	var lines = block.split("\n")
	var result = []
	var in_code = false
	for line in lines:
		var ln = line.strip_edges()
		if not in_code:
			var test_ln = ln
			if test_ln.begins_with("gdscript"): test_ln = test_ln.substr(8).strip_edges()
			if test_ln.begins_with("extends ") or test_ln.begins_with("class_name ") or test_ln.begins_with("@") or test_ln.begins_with("func ") or test_ln.begins_with("var ") or test_ln.begins_with("const ") or test_ln.begins_with("signal ") or test_ln.begins_with("#"):
				in_code = true
				if test_ln != ln: line = line.replace("gdscript", "").strip_edges()
			elif test_ln.begins_with("[gd_scene ") or test_ln.begins_with("[gd_resource "):
				in_code = true
				if test_ln != ln: line = line.replace("gdscript", "").strip_edges()
		if in_code: result.append(line)
	if result.is_empty(): return block.strip_edges()
	return "\n".join(result).strip_edges()

static func extract_deletes(text: String) -> Array[String]:
	var paths: Array[String] = []
	var rx = RegEx.new()
	rx.compile("\\[DELETE:([^\\]]+)\\]|<delete:([^>]+)>|<delete>\\s*(.*?)\\s*</delete>")
	for m in rx.search_all(text):
		var p = ""
		for i in range(1, 4):
			if m.get_string(i) != "":
				p = m.get_string(i).strip_edges()
				break
		if p != "" and not p.begins_with("res://"): p = "res://" + p.trim_prefix("/")
		if p != "" and p not in paths: paths.append(p)
	return paths

static func extract_run_game(text: String) -> String:
	var rx = RegEx.new()
	rx.compile("\\[RUN_GAME:(main|current)\\]")
	var m = rx.search(text)
	if m: return m.get_string(1)
	return ""
