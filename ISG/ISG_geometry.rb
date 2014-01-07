################################################################################
# Filename: ISG_geometry.rb
# Created as a part of "Iterative Shape Grammars" experiment to assess if the
# proposed method can improve traditional SG methods, which tipically defines
# all rules prior to generating design.
# Author: Jernej Vidmar
# Version: 0.1
# Date: December, 2013
################################################################################

################################################################################
# Base ShapeGrammars module for namespace clashes prevention
################################################################################
module IterativeSG
	############################################################################
	# Geometry related methods.
	############################################################################
	module Geometry
		class << self
			# we need boundary points for many calculations, so it makes sense
			# to store them
			attr_accessor :boundary_points
		end
		
		########################################################################
		# Initialize Geometry module and fill it up with needed information for
		# faster access to often used data.
		# 
		# Accepts:
		# boundary_component - which is of class Sketchup::ComponentInstance.
		# 
		# Notes:
		# Component that represents shape boundary should only contain one face
		# which can be convex.
		# 
		# Returns:
		# True.
		########################################################################
		def Geometry::initialize(boundary_component)
			@boundary_component = boundary_component
			@boundary_points = component_outer_loop(boundary_component)
			return true
		end
		
		########################################################################
		# Check if face is inside boundary object, specified by Controller. Face
		# is inside boundary even if it touches some of the edges. This method
		# works for convex hull boundaries.
		# 
		# Accepts:
		# center_point - shape's bounding box center
		# shape_points - array of shape points.
		# 
		# Returns:
		# True if face is completely inside the specified boundary,
		# False otherwise.
		########################################################################
		def Geometry::inside_boundary?(center, shape_points)
			# first check if bounds center is outside of the boundary
			# we can skip rest if center is outside...
			result = Geom.point_in_polygon_2D(center, @boundary_points, true)
			return false if result == false
			
			# check if all points lie inside specified boundary.
			shape_points.each do |pt|
				result = Geom.point_in_polygon_2D(pt, @boundary_points, true)
				return false if result == false
			end
			return true
		end
		# ent = Sketchup.active_model.selection[0]
		# IterativeSG::Geometry::inside_boundary?(sel.position, sel.points)
		
		########################################################################
		# Return only the specified number of closest shapes.
		# 
		# Accepts:
		# entity - solution shape (Group)
		# num_of_closest - number of closest shapes returned
		# 
		# Notes:
		# TODO: at the moment we only compare distance from bounding box center.
		# We should also check if two shapes are toucing each other.
		# 
		# Returns:
		# Sorted array of shapes (groups) based on distance (closest at the
		# begining)
		########################################################################
		def Geometry::get_closest(entity, num_of_closest = 10)
			sorted_by_distance = self.sort_by_distance(entity)
			closest_objects = sorted_by_distance[0..num_of_closest-1]
			return closest_objects
		end
		# IterativeSG::Geometry::get_closest(sel)

		########################################################################
		# Sort all shapes in solution based on the distance from the 
		# selected shape.
		# 
		# Accepts:
		# entity - solution shape (ComponentInstance)
		# 
		# Notes:
		# TODO: at the moment we only compare distance from bounding box center.
		# We should also check if two shapes are toucing each other.
		# 
		# Returns:
		# Sorted array of shapes (groups) based on distance (closest at the
		# begining)
		########################################################################
		def Geometry::sort_by_distance(entity)
			point = entity.position
			distance_hash = Hash.new
			solution_shapes = Controller.solution_shapes.clone
			solution_shapes.delete entity
			solution_shapes.each do |shape|
				distance_hash[shape] = point.distance(shape.position)
			end
			sorted_distance = distance_hash.sort_by { |key, value| value }
			closest_objects = Array.new
			sorted_distance.each { |obj| closest_objects << obj[0] }
			return closest_objects
		end

		########################################################################
		# Find object at specified distance and vector. We use this to quickly
		# find shapes that match shape rule definition if they are made of many
		# objects.
		# 
		# Accepts:
		# entity - solution shape (ComponentInstance)
		# solution_shapes - list of appropriate candidates ( usually
		# ComponentInstance-s) for match
		# distance - distance between two objects
		# vector - direction between two objects positions
		# 
		# Notes:
		# 
		# Returns:
		# Array of all ComponentInstace object that match distance and vector
		# specification.
		########################################################################
		def Geometry::get_by_distance(entity, solution_shapes, distance, vector)
			point = entity.position
			solution_shapes.delete entity
			objects = Array.new
			solution_shapes.each do |ent|
				if (point.distance(ent.position)) == distance
					# also make sure vector is paralel to one specified
					if vector.parallel?(point.vector_to(ent.position))
						objects << ent
					end
				end
			end
			return objects.flatten
		end

		########################################################################
		# Find objects in specified direction. Objects are returned only when
		# they are found in unobstructed way - that is when no other, uspecified
		# object is in their way. We therefore need candidates in order to check
		# this.
		# 
		# Accepts:
		# entity - component from which search is begun
		# candidates - list of shapes that are valid resuls.
		# count - how many objects we should search for.
		# vector - direction of search.
		# max_distance - how far can found shape be from initial position.
		# 
		# Notes:
		# 
		# Returns:
		# Array of ComponentInstace objects that match required specification.
		########################################################################
		def Geometry::collect_in_direction(entity, candidates = Sketchup.active_model.entities,
				count = 2, vector = [1,0,0], max_distance = 10_000)
			model = Sketchup.active_model
			pos = entity.position
			# begin from entity
			ray = [pos, vector]
			result = 1
			distance = 0
			components = Array.new
			until (components.length == count) or (distance > max_distance)
				result = model.raytest(ray, false)
				break if result == nil		
				new_pos = result[0]
				ray = [new_pos,vector]
				component = result[1][0]
				next if component == entity
				# exit if wrong shape was hit by raytest... 
				unless candidates.include? component
					return []
				end
				components << component
				components.uniq!	
			end
			return components
		end
		# IterativeSG::Geometry::collect_in_direction(sel)
		# 
		########################################################################
		# Check if two groups match. That is if the face they contain are exact
		# same shape and at exact same place.
		# 
		# Accepts:
		# Accepts two groups, which are being compared.
		# 
		# Notes:
		# At the moment both groups should contain only one face with same
		# amount of vertices.
		# 
		# Returns:
		# True if two groups are identical, False otherwise.
		########################################################################
		def Geometry::identical?(entity_1, entity_2)
			# most of the shapes do not match, so skip all other if their position
			# is not the same.
			# TODO maybe we should improve this?
			return false if entity_1.position != entity_2.position

			# get local transformation of shape if their ID is the same
			if entity_1.component_name == entity_2.component_name
				return true if entity_1.trans_array == entity_2.trans_array
			end
			
			# match points
			group_2_points = entity_2.points.clone
			group_2_vertices_length = group_2_points.length
			entity_1.points.each do |point_1|
				# find vertex in second group that matches this vertex position
				group_2_points.each do |point_2|
					if  point_1 == point_2
						group_2_points.delete point_2
						# puts 'vertex found'
						break
					end
				end
				
				# if vertex was not found, we can skip rest of the routine.
				if group_2_vertices_length == group_2_points.length
					return false 
				else
					group_2_vertices_length -= 1
				end
			end
			
			# if all vertices were deleted, polygons are matching
			return group_2_points.empty?
		end
		# IterativeSG::Geometry::identical?(group_1, group_2)
			
		########################################################################
		# Create new ComponentDefinition with a face from specified points.
		# 
		# Accepts:
		# name - name of new shape
		# points - list of 3D points from which convex face will be created
		# material - material to be applied to face
		# 
		# Notes:
		# For now this method creates only convex faces.
		# 
		# Returns:
		# New ComponentInstance object.
		########################################################################
		def Geometry::add_face_in_component(name, points, face_material = nil,
			edge_material = nil)
			# Create group and fill it with face
			comp_definition = Sketchup.active_model.definitions.add(name)

			ordered_points = convex_hull(points)
			face = comp_definition.entities.add_face(ordered_points)

			# face normal up!
			face.reverse! if face.normal.z < 0
			face.material = face_material unless face_material == nil
			face.edges.each {|e| e.material = edge_material} unless edge_material == nil
			# add it to the model
			return Sketchup.active_model.entities.add_instance(comp_definition, [0,0,0])	
		end
		
		########################################################################	
		# PRIVATE METHODS BELOW!
		########################################################################		
		private
		
		########################################################################
		# Calculate 2D (x,y) position of boundary vertices in global space.
		# 
		# Accepts:
		# Bounary object which is of class Sketchup::ComponentInstance.
		# 
		# Notes:
		# Component that represents shape boundary should only contain one face
		# which can be convex.
		# 
		# Returns:
		# Sorted array of 3D points (Z coordinate is always 0).
		########################################################################
		def Geometry::component_outer_loop(boundary_component)
			# get face's outer vertices
			face = boundary_component.definition.entities.select do
				|ent| ent.is_a? Sketchup::Face
			end
			# make sure only one exists in specified boundary component
			if face.length > 1
				UI.messagebox "Boundary component should only contain one face.", MB_OK
				@boundary_points = nil
				return false
			end
			# if all is OK, load loop vertices
			outer_vertices = face.last.outer_loop.vertices
			
			# remember component transformation
			component_transformation = boundary_component.transformation.to_a
			
			# now recalculate points position so they are in global space
			points = Array.new
			outer_vertices.each do |vertex|
				point = vertex.position
				# apply transformation to it
				point.transform! component_transformation
				# and add it to array of points
				points << [point.x, point.y, point.z]
			end
			# and return it
			return points
		end
		
		########################################################################
		# Sort vertices so they form convex hull for polygon creation. See
		# http://en.wikibooks.org/wiki/Algorithm_Implementation/Geometry/Convex_hull/Monotone_chain#Ruby
		# for more information. This method works only in horizontal plane!
		# 
		# Accepts:
		# points - list of 3D points from which convex face will be created
		# 
		# Notes:
		# 
		# Returns:
		# Vertices in order which forms convex hull.
		########################################################################
		def Geometry::convex_hull(points)
			sorted_vertices = sort_vertices(points)
			
			return sorted_vertices if sorted_vertices.length < 3
			lower = Array.new
			sorted_vertices.each do |p|
				while lower.length > 1 and cross(lower[-2], lower[-1], p) <= 0 do lower.pop end
				lower.push(p)
			end
			upper = Array.new
			sorted_vertices.reverse_each do |p|
				while upper.length > 1 and cross(upper[-2], upper[-1], p) <= 0 do upper.pop end
				upper.push(p)
			end
			return lower[0...-1] + upper[0...-1]
		end
		
		########################################################################
		# Calculate cross product. See http://en.wikibooks.org/wiki/Algorithm_Implementation/Geometry/Convex_hull/Monotone_chain#Ruby
		# for more information.
		# 
		# Accepts:
		# add documentation
		# 
		# Notes:
		# 
		# Returns:
		# cross product
		########################################################################
		def Geometry::cross(o, a, b)
			(a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
		end
		
		########################################################################

		# 
		# Return:

		########################################################################
		# Sort the vertices by x-coordinate (in case of a tie, sort by
		# y-coordinate).  See http://en.wikibooks.org/wiki/Algorithm_Implementation/Geometry/Convex_hull/Monotone_chain#Ruby
		# for more information.
		# 
		# Accepts:
		# points - list of 3D point objects
		# 
		# Notes:
		# 
		# Returns:
		# Vertices in sorted by x coordinate.
		########################################################################
		def Geometry::sort_vertices(points)
			sorted_points = Array.new
			# remove each vertex, one by one until all are sorted
			until points.empty?
				x_min = y_min = 1_000_000.m
				selected_point = Geom::Point3d.new
				# find the vertex with min x
				points.each do |point|
					pos_x = point.x
					pos_y = point.y
					if pos_x < x_min
						x_min = pos_x
						selected_point = point
					# or min y if x is the same...
					elsif (pos_x == x_min) and (pos_y < y_min)
						y_min = pos_y
						selected_point = point
					end
				end
				sorted_points << selected_point
				points.delete selected_point
			end
			return sorted_points
		end
		
		########################################################################
		# Sort the components by x-coordinate or y cooridanate.
		# 
		# Accepts:
		# components - list of ISG component objects
		# direction - :x for horizontal or :y for vertical search
		# 
		# Notes:
		# 
		# Returns:
		# Shapes in order defined.
		########################################################################
		def Geometry::sort_components_in_direction(components, direction = :x)
			sorted_components = Array.new
			# remove each vertex, one by one until all are sorted
			until components.empty?
				x_min = y_min = 1_000_000.m
				selected_component = Geom::Point3d.new
				# find the vertex with min x
				components.each do |component|
					point = component.position
					if direction == :x
						pos_x = point.x
						if pos_x < x_min
							x_min = pos_x
							selected_component = component
						end
					else
						pos_y = point.y
						if pos_y < y_min
							y_min = pos_y
							selected_component = component
						end
					end
				end
				sorted_components << selected_component
				components.delete selected_component
			end
			return sorted_components
		end
	end
end