@tool
extends Node
class_name HiruDiff

static func calculate_diff_stats(old_text: String, new_text: String) -> String:
	var old_lines = old_text.split("\n")
	var new_lines = new_text.split("\n")
	var added = 0
	var removed = 0
	if old_text == "": return "+" + str(new_lines.size()) + " -0"
	added = maxi(0, new_lines.size() - old_lines.size())
	removed = maxi(0, old_lines.size() - new_lines.size())
	if added == 0 and removed == 0 and old_text != new_text:
		added = 1; removed = 1
	return "+" + str(added) + " -" + str(removed)

static func generate_unified_diff(old_text: String, new_text: String) -> Array[Dictionary]:
	var old_lines = old_text.split("\n")
	var new_lines = new_text.split("\n")
	var m = old_lines.size()
	var n = new_lines.size()
	var diff_ops: Array[Dictionary] = []
	
	if m * n < 10000000:
		var L = []
		for i in range(m + 1):
			var row = []
			row.resize(n + 1)
			row.fill(0)
			L.append(row)
		for i in range(1, m + 1):
			for j in range(1, n + 1):
				if old_lines[i - 1] == new_lines[j - 1]: L[i][j] = L[i - 1][j - 1] + 1
				else: L[i][j] = maxi(L[i - 1][j], L[i][j - 1])
		var i = m
		var j = n
		while i > 0 and j > 0:
			if old_lines[i - 1] == new_lines[j - 1]:
				diff_ops.push_front({"type": "=", "text": old_lines[i - 1]})
				i -= 1; j -= 1
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
		for line in old_lines: diff_ops.append({"type": "-", "text": line})
		for line in new_lines: diff_ops.append({"type": "+", "text": line})
	return diff_ops
