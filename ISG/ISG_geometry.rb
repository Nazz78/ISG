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
		
		def Geometry::initialize(boundary_component)
			@boundary_points = component_outer_loop(boundary_component)
		end
		
		########################################################################
		# Check if face is inside boundary object, specified by Controller. Face
		# is inside boundary even if it touches some of the edges. This method
		# works for convex hull boundaries.
		# 
		# Returns true if face is completely inside the specified boundary,
		# false otherwise.
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
		# PRIVATE METHODS BELOW!
		########################################################################		
		private
		
		########################################################################
		# Calculate 2D (x,y) position of boundary vertices in global space.
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
