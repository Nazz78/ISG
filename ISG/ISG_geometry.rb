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
		# Bounary object which is of class Sketchup::ComponentInstance.
		# 
		# Notes:
		# Component that represents shape boundary should only contain one face
		# which can be convex.
		# 
		# Returns:
		# True.
		########################################################################
		def Geometry::initialize(boundary_component)
			@boundary_points = component_outer_loop(boundary_component)
			return true
		end
		
		########################################################################
		# Check if face is inside boundary object, specified by Controller. Face
		# is inside boundary even if it touches some of the edges. This method
		# works for convex hull boundaries.
		# 
		# Accepts:
		# Sketchup::Face which is being checked.
		# 
		# Returns:
		# True if face is completely inside the specified boundary,
		# False otherwise.
		########################################################################
		def Geometry::inside_boundary?(face)
			# collect all vertices positions
			vertices = face.vertices
			points = Array.new
			vertices.each {|vertex| points << vertex.position}
			
			# check if all points lie inside specified convex boundary.
			points.each do |pt|
				result = Geom.point_in_polygon_2D(pt, @boundary_points, true)
				return false if result == false
			end
			return true
		end
		# face = Sketchup.active_model.selection[0]
		# ShapeGrammars::Geometry::inside_boundary?(face)

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
		def Geometry::identical?(group_1, group_2)
			# get local transformation of shape if their ID is the same
			# return true if group_1.transformation.to_a == group_2.transformation.to_a
			
			# match points
			group_1_vertices = group_1.entities.to_a.select { |ent|
				ent.class == Sketchup::Face }[0].vertices
			group_1_transformation = group_1.transformation
			group_2_vertices = group_2.entities.to_a.select { |ent|
				ent.class == Sketchup::Face }[0].vertices
			group_2_transformation = group_2.transformation
			
			group_2_vertices_length = group_2_vertices.length
			group_1_vertices.each do |vertex_1|
				pos_1 = vertex_1.position.transform! group_1_transformation
				# find vertex in second group that matches this vertex position
				group_2_vertices.each do |vertex_2|
					pos_2 = vertex_2.position.transform! group_2_transformation
					if  pos_2 == pos_1
						group_2_vertices.delete vertex_2
						# puts 'vertex found'
						break
					end
				end
				
				# if vertex was not found, we can skip rest of the routine.
				if group_2_vertices_length == group_2_vertices.length
					return false 
				else
					group_2_vertices_length -= 1
				end
			end
			
			# if all vertices were deleted, polygons are matching
			return group_2_vertices.empty?
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
	end
end