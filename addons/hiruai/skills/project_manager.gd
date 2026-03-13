@tool
extends Node
## Hiru Skill: Project Management & Lifecycle
## This skill helps organize large Godot projects and manage the application lifecycle.

func get_skill_name() -> String:
	return "Project Management"

func get_advice(context: String = "") -> String:
	return """
[SKILL: PROJECT MANAGEMENT]
Help the user build scalable and maintainable projects:

1. **Folder Structure**:
   - `res://assets/`: Textures, Audio, Models.
   - `res://scenes/`: `.tscn` files.
   - `res://scripts/`: `.gd` files.
   - `res://resources/`: `.tres` data files.
   - Or "Component-based": Folder per feature (e.g., `res://player/player.tscn` + `player.gd`).
2. **AutoLoads (Singletons)**: Use for global state (Global Settings, Player Progress, Event Bus) but avoid overusing them as they can make unit testing hard.
3. **Internal Tools**: Use `@tool` scripts to streamline level design or data management directly in the editor.
4. **Naming Conventions**:
   - `ClassNames` (PascalCase).
   - `variable_names` (snake_case).
   - `_private_methods` (prefix with underscore).
   - `SIGNAL_NAMES` (all caps or snake_case).
5. **Scene Instances**: Modularize your UI and Gameplay into reusable instances. If a scene gets too large, break it into sub-scenes.
"""
