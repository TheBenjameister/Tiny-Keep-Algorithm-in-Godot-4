extends Node2D

var circle_radius = 7
var min_room_size = 7
var max_room_size = 15
var num_rooms = 150
var tile_size = 16
var loop_chance = .075
var room_array = [] 
var main_rooms 
var unused_rooms
var secondary_rooms = []
var main_room_coords = []
var path_to_room_dictionary = []
var triangulate_room_coords : PackedVector2Array
var path #Astar pathfinding object 
var triangle_pool = PackedVector2Array()
var path_edges = []
var triangle_edges = []
var unused_edges = []
var corridors = []
var Room = preload("res://room.tscn")

func _ready():
	_roomGen()

func _roomGen(): 
	for i in range(num_rooms):
		var angle = randf_range(0,2*PI)
		var pos =  Vector2(cos(angle), sin(angle)) * circle_radius
		var room_size = Vector2(randi() % (max_room_size - min_room_size) + min_room_size, randi() % (max_room_size - min_room_size) + min_room_size)
		var room = Room.instantiate()
		room._make_room(pos, room_size * tile_size)
		$Rooms.add_child(room)
		room_array.append(room)
	_sort_rooms()
	await get_tree().create_timer(1).timeout
	_snap_to_grid()
	_make_mst()
	_triangulate()
	_add_loops()
	await get_tree().create_timer(1).timeout
	_make_map()


func compare_size(a,b):
	if a.size.length() < b.size.length():
		return true
	return false

func _sort_rooms(): 
	room_array.sort_custom(compare_size)
	var num_main_rooms = floor(num_rooms * .15)
	main_rooms = room_array.slice(num_rooms - num_main_rooms,num_rooms)
	unused_rooms = room_array.slice(0,num_rooms - num_main_rooms -1)

func _snap_to_grid():
	for room in room_array:
		room.position.x = round(room.position.x)
		room.position.y = round(room.position.y)
		#room.mode = RigidBody2D.MODE_STATIC

func _make_mst(): 
	for room in main_rooms : 
		main_room_coords.append(room.position)
		triangulate_room_coords.append(room.position)
	path = find_mst(main_room_coords)
	path_to_room()

func path_to_room():
	for i in main_rooms.size():
		path_to_room_dictionary.append(0)
	for room in main_rooms: 
		var id = path.get_closest_point(room.position)
		path_to_room_dictionary[id] = room

func _triangulate(): 
	var triangle_points = Geometry2D.triangulate_delaunay(triangulate_room_coords)
	for index in len(triangle_points)/3: 
		for n in range(3) : 
			triangle_pool.append(triangulate_room_coords[triangle_points[(index * 3) + n]])
	for index in len(triangle_pool) /3 : 
		for n in range (2): 
			triangle_edges.append([triangle_pool[(index*3) + n + 1] , triangle_pool[(index*3) + n]])
	set_unused_edges()

func find_mst(nodes):
	var path = AStar2D.new()
	path.add_point(path.get_available_point_id(), nodes.pop_front())
	while nodes : 
		var min_dist = INF
		var min_p = null
		var p = null
		for p1_id in path.get_point_ids():
			var p1 = path.get_point_position(p1_id)
			for p2 in nodes : 
				if p1.distance_to(p2) < min_dist:
					min_dist = p1.distance_to(p2)
					min_p = p2
					p = p1
		var n = path.get_available_point_id()
		path.add_point(n, min_p)
		path.connect_points(path.get_closest_point(p),n)
		nodes.erase(min_p)
	for p in path.get_point_ids():
			for c in path.get_point_connections(p):
				var pp = path.get_point_position(p)
				var cp = path.get_point_position(c)
				path_edges.append([cp,pp])
	return path

func set_unused_edges():
	for edge in triangle_edges:
		if not path_edges.has(edge):
			unused_edges.append(edge)

func point_in_room(point,room1,room2):
	var case = 0 #midpoint is in neither boundary, meaning L shaped corridor 
	if point.x <= (room1.position.x + (room1.size.x))/tile_size:
		if point.x >= (room1.position.x - (room1.size.x))/tile_size:
			if point.x <= (room2.position.x + (room2.size.x))/tile_size:
				if point.x >= (room2.position.x - (room2.size.x))/tile_size:
					case = 1 #midpoint is between the boundaries of x, meaning the rooms are above each other
	if point.y <= (room1.position.y + (room1.size.y))/tile_size:
		if point.y >= (room1.position.y - (room1.size.y))/tile_size:
			if point.y <= (room2.position.y + (room2.size.y))/tile_size:
				if point.y >= (room2.position.y - (room2.size.y))/tile_size:
					case = 2 #midpoint is between the boundaries of y, meaning the rooms are next to each other
	if point.x <= (room1.position.x + (room1.size.x))/tile_size:
		if point.x >= (room1.position.x - (room1.size.x))/tile_size:
			if point.x <= (room2.position.x + (room2.size.x))/tile_size:
				if point.x >= (room2.position.x - (room2.size.x))/tile_size:
					if point.y <= (room1.position.y + (room1.size.y))/tile_size:
						if point.y >= (room1.position.y - (room1.size.y))/tile_size:
							if point.y <= (room2.position.y + (room2.size.y))/tile_size:
								if point.y >= (room2.position.y - (room2.size.y))/tile_size:
									case = 3
	return case 

func _add_loops():
	for edge in unused_edges : 
		if randf() < loop_chance:
			var p1_index = path.get_closest_point(edge[0])
			var p2_index = path.get_closest_point(edge[1])
			path.connect_points(p1_index,p2_index)

func _make_map(): 
	var tile_map = $TileMap
	tile_map.clear()
	var full_rect = Rect2()
	for room in main_rooms: 
		var r = Rect2(room.position - room.size, room.get_node("CollisionShape2D").shape.extents * 2)
		full_rect = full_rect.merge(r)
	var topleft = tile_map.local_to_map(full_rect.position)
	var bottomright = tile_map.local_to_map(full_rect.end)
	for x in range(topleft.x - 1, bottomright.x +1): 
		for y in range(topleft.y +1, bottomright.y -1):
			tile_map.set_cell(0,Vector2(x,y),0, Vector2(4,3))
	
	await get_tree().create_timer(1).timeout
	
	var passed = []
	for point_id in path.get_point_ids():
		passed.append(point_id)
		for neighbor_id in path.get_point_connections(point_id):
			if not passed.has(neighbor_id):
				var current_room = path_to_room_dictionary[point_id]
				var neighbor_room = path_to_room_dictionary[neighbor_id]
				var start_p = current_room.position/tile_size
				var end_p = neighbor_room.position/tile_size
				var midpoint = Vector2((start_p.x+end_p.x)/2,(start_p.y+end_p.y)/2)
				var x_diff = sign(end_p.x - start_p.x)
				var y_diff = sign(end_p.y - start_p.y)
				if x_diff == 0 : 
					x_diff = pow(-1.0, randi() %2)
				if y_diff == 0 :
					y_diff = pow(-1.0, randi() %2)
				if point_in_room(midpoint, current_room, neighbor_room) == 1:
					for y in range(start_p.y, end_p.y,y_diff):
						tile_map.set_cell(0,Vector2(midpoint.x+1,y),0, Vector2(0,0))
						tile_map.set_cell(0,Vector2(midpoint.x,y),0, Vector2(0,0))
						tile_map.set_cell(0,Vector2(midpoint.x-1,y),0, Vector2(0,0))
						for room in unused_rooms :
								if (point_in_room(Vector2(midpoint.x,y), room,room) == 3) or (point_in_room(Vector2(midpoint.x+1,y), room,room) == 3) or (point_in_room(Vector2(midpoint.x-1,y), room,room) == 3) : 
									secondary_rooms.append(room)
				if point_in_room(midpoint, current_room, neighbor_room) == 2:
					for x in range(start_p.x, end_p.x,x_diff):
						tile_map.set_cell(0,Vector2(x,midpoint.y+1),0, Vector2(0,0))
						tile_map.set_cell(0,Vector2(x,midpoint.y),0, Vector2(0,0))
						tile_map.set_cell(0,Vector2(x,midpoint.y-1),0, Vector2(0,0))
						for room in unused_rooms:
							if (point_in_room(Vector2(x,midpoint.y), room,room) == 3) or (point_in_room(Vector2(x,midpoint.y+1), room,room) == 3) or (point_in_room(Vector2(x,midpoint.y-1), room,room) == 3) : 
								secondary_rooms.append(room)
								unused_rooms.erase(room)
				if point_in_room(midpoint, current_room, neighbor_room) == 0:
					var x_y = start_p
					var y_x = end_p
					if (randi() % 2) > 0:
						x_y = end_p
						y_x = start_p
					for x in range(x_y.x, y_x.x,x_diff):
						tile_map.set_cell(0,Vector2(x,x_y.y+1),0, Vector2(0,0))
						tile_map.set_cell(0,Vector2(x,x_y.y),0, Vector2(0,0))
						tile_map.set_cell(0,Vector2(x,x_y.y-1),0, Vector2(0,0))
						for room in unused_rooms:
							if (point_in_room(Vector2(x,x_y.y), room,room) == 3) or (point_in_room(Vector2(x,x_y.y+1), room,room) == 3) or (point_in_room(Vector2(x,x_y.y-1), room,room) == 3) : 
								secondary_rooms.append(room)
								unused_rooms.erase(room)
					for y in range(x_y.y, y_x.y,y_diff):
							tile_map.set_cell(0,Vector2(y_x.x+1,y),0, Vector2(0,0))
							tile_map.set_cell(0,Vector2(y_x.x,y),0, Vector2(0,0))
							tile_map.set_cell(0,Vector2(y_x.x-1,y),0, Vector2(0,0))
							for room in unused_rooms :
								if (point_in_room(Vector2(y_x.x,y), room,room) == 3) or (point_in_room(Vector2(y_x.x+1,y), room,room) == 3) or (point_in_room(Vector2(y_x.x-1,y), room,room) == 3) : 
									secondary_rooms.append(room)
									unused_rooms.erase(room)
	
	await get_tree().create_timer(3).timeout
	
	for room in main_rooms: 
		var s = (room.size / tile_size).floor()
		var pos = tile_map.local_to_map(room.position)
		var ul = (room.position / tile_size).floor() - s
		for x in range(2, s.x * 2 + 2):
			for y in range(2, s.y*2 + 2): 
				tile_map.set_cell(0,Vector2(ul.x + x, ul.y + y), 0, Vector2(1,4))
	
	await get_tree().create_timer(1).timeout	
	
	for room in secondary_rooms: 
		var s = (room.size / tile_size).floor()
		var pos = tile_map.local_to_map(room.position)
		var ul = (room.position / tile_size).floor() - s
		for x in range(2, s.x * 2 + 2):
			for y in range(2, s.y*2 + 2): 
				tile_map.set_cell(0,Vector2(ul.x + x, ul.y + y), 0, Vector2(0,2))
	for room in unused_rooms:
		room.queue_free()

func _draw():
	for room in $Rooms.get_children():
		draw_rect(Rect2(room.position - room.size, room.size * 2), Color(32,228, 0), false)
	if not null in main_rooms: 
		for room in main_rooms:
			draw_rect(Rect2(room.position - room.size, room.size * 2), Color(32,228, 0), true)
	if path : 
		for p in path.get_point_ids():
			for c in path.get_point_connections(p):
				var pp = path.get_point_position(p)
				var cp = path.get_point_position(c)
				draw_line(Vector2(pp.x,pp.y), Vector2(cp.x,cp.y), Color(0,0,200), 15, true)

func _process(delta):
	queue_redraw()

