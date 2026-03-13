@tool
extends Node
## Hiru Skill: UI & UX Engineering
## This skill covers Godot's Control node system and design principles.

func get_skill_name() -> String:
	return "UI & UX Engineering"

func get_advice(context: String = "") -> String:
	return """
[SKILL: UI DESIGN]
Expertise in Godot's UI system:

1. **Containers are King**: Never position nodes manually using `position`. Use `VBoxContainer`, `HBoxContainer`, `GridContainer`, and `MarginContainer`.
2. **Anchor & Offsets**: Understanding `Layout` presets (Full Rect, Center, etc.) is critical for responsive UI.
3. **Themes**: Use `Theme` resources to apply global styles (fonts, colors, styles) instead of overriding them on every single node.
4. **Custom Controls**: Create reusable UI components (e.g., a "CustomButton" scene) instead of copying buttons everywhere.
5. **Dynamic UI**: Use `Tween` for smooth UI animations (fade in, slide out) rather than `AnimationPlayer` for simple transitions.
6. **Focus System**: Always handle `focus_neighbor` for controller/keyboard navigation support.
"""
