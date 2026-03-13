@tool
extends Node
class_name HiruValidator

static func check_syntax_error(code: String) -> String:
	var script = GDScript.new()
	script.source_code = code
	var err = script.reload()
	if err != OK:
		match err:
			ERR_PARSE_ERROR: return "Parse Error (Check for typos, missing colons, or invalid keywords)"
			ERR_COMPILATION_FAILED: return "Compilation Failed (Indentation or syntax error)"
			_: return "Syntax Error (Godot Error Code: %d)" % err
	return ""

static func find_missing_preloads(saves: Array[Dictionary]) -> Array[Dictionary]:
	var missing: Array[Dictionary] = []
	var all_save_paths: Array[String] = []
	for s in saves: all_save_paths.append(s["path"])
	var rx = RegEx.new()
	rx.compile('preload\\s*\\(\\s*"([^"]+)"\\s*\\)')
	for s in saves:
		var spath = s["path"]
		for m in rx.search_all(s["content"]):
			var dep_path: String = m.get_string(1)
			if not dep_path.begins_with("res://"): dep_path = "res://" + dep_path.trim_prefix("/")
			if FileAccess.file_exists(dep_path): continue
			if dep_path in all_save_paths: continue
			var already_added = false
			for mis in missing:
				if mis["source"] == spath and mis["missing"] == dep_path: already_added = true
			if not already_added: missing.append({"source": spath, "missing": dep_path})
	return missing
