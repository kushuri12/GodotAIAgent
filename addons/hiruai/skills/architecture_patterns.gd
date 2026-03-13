@tool
extends Node

func get_skill_name():
	return "Architecture Patterns"

func get_advice():
	return """
- **State Machine**: For complex AI or player controllers, use a State Machine pattern. Each state is a separate object or a child node.
- **Signals (Observer)**: Decouple systems using Godot's Signal system. Prefer signals over direct node references for cross-system communication.
- **Resource-based Data**: Store configuration and data in .tres files. It makes the game easier to tweak without changing code.
- **Command Pattern**: For undo/redo or input buffering, use a Command pattern to encapsulate actions.
- **Dependency Injection**: Pass references (like the Player or Camera) to child nodes instead of using `get_parent().get_node(...)`.
- **Node Composition**: Use small, focused nodes that do one thing well (e.g., a "HealthComponent" node).
"""
