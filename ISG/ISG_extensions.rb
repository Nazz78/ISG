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
		attr_reader :shape_ID, :UID
		########################################################################
		# Initialize Sketchup::Group object so that ISG can work with it. For
		# now we add uniqe ID so shapes can be easiliy identified.
		# 
		# Accepts:
		# shape_ID which is identifier among similar shapes.
		# UID which is uniqe identifier, so we can receive specific instance
		# of the shape.
		# 
		# Notes:
		# Each Group has a ID which is persistent when the Group is copied.
		# 
		# Returns:
		# Object's ID and UID.
		########################################################################
		def initialize_ISG_shape(shape_id, shape_uid)
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

			return @shape_ID, @UID
		end
	end
	
	module ComponentInstance
		attr_reader :UID
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

			return @UID
		end
	end
end