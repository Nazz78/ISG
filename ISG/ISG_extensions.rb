################################################################################
# Filename: ISG_geometry.rb
# Created as a part of "Iterative Shape Grammars" experiment to assess if the
# proposed method can improve traditional SG methods, which tipically defines
# all rules prior to generating design.
# Author: Jernej Vidmar
# Version: 0.1
# Date: December, 2013
################################################################################
module IterativeSG
	############################################################################
	# Extension of Sketchup::Group objects which are used as shapes.
	############################################################################
	module ComponentInstance
		attr_reader :UID, :points, :position, :trans_array,
		  :component_name
		# rules applied specified which rule has already been aplied to the shape
		attr_accessor :rules_applied
		########################################################################
		# Initialize Sketchup::ComponentInstance object so that ISG can work
		# with it. For now we add uniqe ID so shapes can be easiliy identified.
		# 
		# Accepts:
		# shape_uid which is uniqe identifier, so we can receive specific instance
		# of the shape.
		# 
		# Notes:
		# Each Component has a ID which is persistent when it is copied.
		# 
		# Returns:
		# Object's ID and UID.
		########################################################################
		def initialize_ISG_shape(shape_uid)
			# create dictionary if it doesn't exist
			@dict = self.attribute_dictionary 'IterativeSG', true
			@rules_applied = Array.new
			
			# UIDs are a bit different - when shape is copied, they should
			# not remain the same. So make sure to change them even if they exist.
			current_uid = @dict.get_attribute 'IterativeSG', 'UID'
			if current_uid == nil
				@UID = shape_uid
				@dict.set_attribute 'IterativeSG', 'UID', shape_uid
			else
				if Controller.UIDs.include? current_uid
					@UID = shape_uid
					@dict.set_attribute 'IterativeSG', 'UID', shape_uid
				else
					@UID = current_uid
				end
			end

			@component_name = self.definition.name
			# define current position for faster access
			self.update_shape
			
			return @UID
		end

		########################################################################
		# Update object variables which are used for comparing shapes. See notes
		# below.
		# 
		# Accepts:
		# Nothing.
		# 
		# Notes:
		# This is the list of updated variables:
		# @position in center of bounding box
		# @points is a list of all vertex positions
		# @trans_array is transformation matrix in array
		# 
		# Returns:
		# nil, it just updated @position, @points and @trans_array variables.
		########################################################################
		def update_shape
			# define current position for faster access
			@position = self.bounds.center
			edges = self.definition.entities.to_a { |ent| ent.class == Sketchup::Edge }
			
			# set vertices array
			vertices = Array.new
			edges.each do |edge|
				vertices << edge.vertices
			end
			vertices.flatten!
			vertices.uniq!
			
			# now calculate each vertex global position
			@points = Array.new
			transformation = self.transformation
			vertices.each do |vertex|
				@points << (vertex.position.transform! transformation)
			end
			
			@trans_array = transformation.to_a
			return nil
		end

		########################################################################
		# Initialize Sketchup::ComponentInstance object so that ISG can work
		# with it. For  now we add uniqe ID so shapes can be easiliy identified.
		# 
		# Accepts:
		# UID which is uniqe identifier, so we can receive specific instance
		# of marker.
		# 
		# Notes:
		# 
		# Returns:
		# Object's UID.
		########################################################################
		def initialize_ISG_marker(uid)
			# create dictionary
			@dict = self.attribute_dictionary 'IterativeSG', true
			
			# UIDs are a bit different - when shape is copied, they should
			# not remain the same. So make sure to change them even if they exist.
			current_uid = @dict.get_attribute 'IterativeSG', 'UID'
			if current_uid == nil
				@UID = uid
				@dict.set_attribute 'IterativeSG', 'UID', uid
			else
				if Controller.UIDs.include? current_uid
					@UID = uid
					@dict.set_attribute 'IterativeSG', 'UID', uid
				else
					@UID = current_uid
				end
			end
			# define current position for faster access
			self.update_shape
			
			return @UID
		end
	end
end