@tool
extends Node
## Hiru Skill: Deep Reasoning & Failure Analysis
## This skill helps Hiru analyze why a plan might fail before execution.

func get_skill_name() -> String:
	return "Reasoning & Failure Analysis"

func apply_reasoning(task: String) -> String:
	var strategy = """
[SKILL: REASONING]
When tackling: %s
1. **Pessimistic Preview**: Identify 3 ways this specific implementation could break Godot's runtime (e.g. null instance, wrong node path, signal name typo).
2. **Context Validation**: Did I check if the node actually exists in the scene?
3. **Dependency Check**: If I change this, do other scripts depend on the old behavior?
4. **Correction Strategy**: If it fails, what is the 'Plan B'?
""" % task
	return strategy
