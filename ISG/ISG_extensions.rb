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
	# Extension of Sketchup::Group objects.
	############################################################################
	module Group
		attr_reader :shape_ID
		########################################################################
		# Initialize Sketchup::Group object so that ISG can work with it. For
		# now we add uniqe ID so shapes can be easiliy identified.
		# 
		# Accepts:
		# A Group with a face that represents a shape.
		# 
		# Notes:
		# Each Group has a uniqe ID which is persistent when the Group is copied.
		# 
		# Returns:
		# Object uniqe ID.
		########################################################################
		def initialize_ISG_shape(shape_id)
			# create dictionary
			@dict = self.attribute_dictionary 'IterativeSG', true
			
			# if dictionary doesn't exist, add received ID
			if (@dict.get_attribute 'IterativeSG', 'shape_ID') == nil
				@shape_ID = shape_id
				@dict.set_attribute 'IterativeSG', 'shape_ID', shape_id
				#
			else
				@shape_ID = @dict.get_attribute 'IterativeSG', 'shape_ID'
			end
			return @shape_ID
		end
	end
end