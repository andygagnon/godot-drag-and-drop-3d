# Main.gd (Attached to a Node3D which acts as the main scene root)
extends Node3D

# --- Constants & Export Variables ---

@export var board_size: int = 8             # 8x8 grid
@export var cell_size: float = 1.0          # Size of one grid cell (e.g., 1 meter)
@export var piece_height: float = 0.2       # Height above the board to lift the piece

# --- Nodes and State Variables ---

var camera_node: Camera3D
var board_node: StaticBody3D
var held_piece: RigidBody3D = null          # Piece must be RigidBody3D to use mode
var initial_y_offset: float = 0.0          # Offset from mouse ray hit point to piece's center
var is_dragging: bool = false
const DRAG_PLANE_Y: float = 0.0            # The Y-coordinate of the board surface
const LAYER_BOARD: int = 1                 # Collision layer 1 (bit 0) for the board
const LAYER_PIECE: int = 2                 # Collision layer 2 (bit 1) for the draggable pieces

# --- Piece Scene Template (Code-Only Definition) ---
# A helper function to create a new draggable piece node dynamically.
func create_piece(color: Color, position_grid: Vector3i) -> RigidBody3D:
	var piece = RigidBody3D.new()
	piece.name = "Piece_%s" % position_grid
	
	# The piece needs a Collider and a Mesh
	var collision_shape = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(cell_size * 0.8, piece_height, cell_size * 0.8)
	collision_shape.shape = shape
	piece.add_child(collision_shape)
	
	var mesh_instance = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = shape.size
	
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	mesh_instance.material_override = material
	
	mesh_instance.mesh = box_mesh
	piece.add_child(mesh_instance)
	
	# Initial snapping to grid
	piece.position = snap_to_grid(Vector3(position_grid.x, 0, position_grid.z))
	# Lift it to sit on top of the board
	piece.position.y = piece_height / 2.0
	
	# FIX 1: Set mode to KINEMATIC (value 2) once, bypassing name/type errors.
	#piece.mode = 2 # MODE_KINEMATIC
	
	# FIX 2: Use freeze=true to anchor it when not being dragged.
	piece.freeze = true 
	piece.freeze = false 
	
	# Setup Collision Layers:
	piece.set_collision_layer_value(LAYER_PIECE, true) # Pieces are on their own layer (for raycasting)
	piece.set_collision_mask_value(LAYER_BOARD, true)  # Pieces collide only with the board
	
	# Add a unique group for raycast filtering check
	piece.add_to_group("draggable_piece")
	
	return piece

# --- Initialization ---

func _ready():
	# 1. Setup Camera and Lighting (Code-only Scene Construction)
	camera_node = Camera3D.new()
	add_child(camera_node)
	camera_node.global_position = Vector3(board_size / 2.0, board_size * 1.5, board_size * 1.5)
	camera_node.look_at(Vector3(board_size / 2.0, 0, board_size / 2.0))
	
	var light = DirectionalLight3D.new()
	add_child(light)
	light.light_color = Color.WHITE
	light.rotation_degrees = Vector3(-45, 45, 0)
	
	# 2. Create the Board (Static Collision Body)
	create_board()
	
	# 3. Spawn Initial Pieces
	spawn_pieces()

# Helper to create a visual and collidable board
func create_board():
	board_node = StaticBody3D.new()
	board_node.name = "GameBoard"
	add_child(board_node)
	
	var mesh = MeshInstance3D.new()
	var plane_mesh = PlaneMesh.new()
	# Size is based on the grid dimensions
	plane_mesh.size = Vector2(board_size * cell_size, board_size * cell_size)
	plane_mesh.material = StandardMaterial3D.new()
	plane_mesh.material.albedo_color = Color(0.2, 0.2, 0.4)
	mesh.mesh = plane_mesh
	board_node.add_child(mesh)
	
	var collision = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	# The box shape must be slightly offset to match the PlaneMesh position
	box_shape.size = Vector3(board_size * cell_size, 0.01, board_size * cell_size)
	collision.shape = box_shape
	board_node.add_child(collision)
	
	# The board's Y position is at 0.0
	board_node.position.y = 0.0
	
	# Setup Collision Layers:
	board_node.set_collision_layer_value(LAYER_BOARD, true)
	board_node.set_collision_mask_value(LAYER_PIECE, true) # Collide with pieces

func spawn_pieces():
	# Example pieces for demonstration
	add_child(create_piece(Color.RED, Vector3i(1, 0, 1)))
	add_child(create_piece(Color.GREEN, Vector3i(6, 0, 1)))
	add_child(create_piece(Color.BLUE, Vector3i(1, 0, 6)))

# --- Grid Snapping Logic ---

# Converts a world position to the nearest center of a grid cell.
func snap_to_grid(world_pos: Vector3) -> Vector3:
	var snapped_x = round(world_pos.x / cell_size) * cell_size
	var snapped_z = round(world_pos.z / cell_size) * cell_size
	
	# Ensure piece remains centered on the plane
	return Vector3(snapped_x, world_pos.y, snapped_z)

# --- Input Handling ---

func _input(event):
	# 1. Detect Mouse Click (Begin Drag)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and not is_dragging:
			
			# Query the 3D space to see what we hit
			var result = raycast_from_mouse(event.position, LAYER_PIECE) # Target pieces layer
			
			if result and result.collider is RigidBody3D and result.collider.is_in_group("draggable_piece"):
				# A draggable piece was hit!
				held_piece = result.collider
				is_dragging = true
				
				# Use freeze=false to unanchor the piece for manual movement
				held_piece.freeze = false
				
				# DEBUG LINE: Confirm pickup is successful
				print("--- Piece picked up: ", held_piece.name, " ---")
				
				# Calculate the vertical offset so the piece doesn't jump
				# distance from the piece's center to the ray hit point
				initial_y_offset = held_piece.global_position.y - result.position.y
				
				# Lift the piece slightly to indicate it's being dragged
				held_piece.global_position.y = DRAG_PLANE_Y + piece_height
				
		# 2. Detect Mouse Release (End Drag)
		elif not event.pressed and is_dragging:
			if held_piece:
				drop_piece()

# --- Physics and Dragging ---

func _process(delta):
	if is_dragging and held_piece:
		# Get the mouse position
		var mouse_pos = get_viewport().get_mouse_position()
		
		# Calculate the world position where the mouse ray hits the board plane
		var ray_origin = camera_node.project_ray_origin(mouse_pos)
		var ray_dir = camera_node.project_ray_normal(mouse_pos)
		
		# Solve for t where ray_origin.y + ray_dir.y * t = DRAG_PLANE_Y
		var t = (DRAG_PLANE_Y - ray_origin.y) / ray_dir.y
		#held_piece.freeze = false
		
		if t > 0:
			var hit_point = ray_origin + ray_dir * t
			held_piece.freeze = true
			
			# Calculate the final position
			var target_pos = hit_point
			
			# Apply the initial vertical offset (keeps the piece steady relative to the click point)
			target_pos.y += initial_y_offset
			
			# Update the held piece's position
			held_piece.global_position = target_pos

# --- Dropping Logic ---

func drop_piece():
	if held_piece:
		# 1. Snap to the nearest grid cell based on current position
		var final_pos = snap_to_grid(held_piece.global_position)
		
		# 2. Keep the piece sitting just above the board
		final_pos.y = piece_height / 2.0
		
		# 3. Apply the final position
		held_piece.global_position = final_pos
		
		# Use freeze=true to re-anchor the piece to prevent it from falling
		held_piece.freeze = true
		held_piece.freeze = false
		
		# 4. Reset state
		held_piece = null
		is_dragging = false

# --- Utility Functions ---

# Helper to perform a single-shot RayCast query
func raycast_from_mouse(mouse_position: Vector2, target_layer: int) -> Dictionary:
	var ray_origin = camera_node.project_ray_origin(mouse_position)
	var ray_end = ray_origin + camera_node.project_ray_normal(mouse_position) * 1000.0 # Cast 1000 units
	
	var space_state = get_world_3d().direct_space_state
	
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	
	# Use direct assignment to the collision_mask property with bitwise shifting.
	# Layer N (1-based) corresponds to bit (N-1) (0-based).
	query.collision_mask = 1 << (target_layer - 1)
	
	return space_state.intersect_ray(query)
