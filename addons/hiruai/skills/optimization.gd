@tool
extends Node
## Hiru Skill: Performance & Optimization
## This skill provides guidance on making Godot games run faster and use less memory.

func get_skill_name() -> String:
	return "Performance & Optimization"

func get_advice(context: String = "") -> String:
	return """
[SKILL: OPTIMIZATION]
Focus on maximizing performance and minimizing resource usage:

1. **Process Logic**:
   - Use `_physics_process` ONLY for physics/movement.
   - Use `_process` for visual updates.
   - If a logic doesn't need to run every frame, use a `Timer` or `Signals`.
2. **Object Pooling**: Instead of `instantiate()` and `queue_free()` for frequent objects (like bullets), reuse them to avoid GC pressure/stutters.
3. **Collision Optimization**:
   - Use simplest shapes (Circle/Rectangle) over Polygon/Concave shapes.
   - Set `CollisionLayer` and `Mask` properly to avoid unnecessary checks.
4. **Drawing/Rendering**:
   - Use `MultiMeshInstance` for many identical meshes.
   - Use `VisibilityNotifier` to stop processing off-screen nodes.
5. **Memory Management**:
   - Manually clear `RefCounted` objects if they form circular references.
   - Be careful with `Callable` bindings and closures that might keep nodes alive.
6. **Thread Safety**: Use `WorkerThreadPool` for heavy calculations (pathfinding, data generation) to keep the main loop smooth.
"""
