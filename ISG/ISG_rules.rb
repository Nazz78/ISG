################################################################################
# Filename: ISG_rules.rb
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
	# RulesBase is a mixin module for shared methods.
	############################################################################
	module RulesBase
		# we need to expose original @shape so collect_candidate_shapes method
		# can find all instances of object being replaced.
		attr_reader :rule_ID ,:shape
		
		def find_by_ID(rule_ID)
			
		end
	end
	
	class RuleReplaceOneShape
		include RulesBase
		########################################################################
		# Initialize rule object and populate it with needed information.
		# 
		# Accepts:
		# rule_ID defines the name of the rule
		# mirror_x and mirror_y can be either 1 or -1. 1 means no reflection, -1
		# means reflection in specified direction.
		# origin specifies the origin of shape to which rule is applied
		# shape is the shape to which rule is applied
		# origin_new specifies the origin of new shape
		# shape_new specifies the shapes which replace current shape
		# 
		# Notes:
		# 
		# Returns:
		# true once object is created
		########################################################################
		def initialize(rule_ID, mirror_x, mirror_y,
				origin,	shape, origin_new, shape_new)
			# define variables
			@dictionary = Controller.dict_rules
			@solution_layer = Controller.solution_layer
			
			@rule_ID = rule_ID
			@origin = origin
			@shape = shape
			@origin_new = origin_new
			@shape_new = shape_new
			@mirror_x = mirror_x
			@mirror_y = mirror_y
			
			# setup origin of base shape
			origin_uid = @origin.UID
			# setup base shape. If it is alread setup, it will just return its UID
			shape_uid = @shape.UID
			# shape.set_attribute rule_ID, 'shape', shape_uid
			
			# setup origin of shape rule application
			origin_new_uid = @origin_new.UID
				
			# create shape rule application
			shape_new_uid = Array.new
			@shape_new.each do |shp|
				# collect all shape's UIDs so we can store them in dictionary
				shape_new_uid << shp.UID
			end
			
			# create temporary group so we can calculate origin
			temp_grp = Sketchup.active_model.entities.add_group @shape_new
			
			# calculate distance vector from original shape to to its marker
			marker1_position = @origin.position
			shape1_position = @shape.bounds.min
			marker2_position = @origin_new.position
			shape2_position = temp_grp.bounds.min
			distance1_vector = marker1_position.vector_to shape1_position
			distance2_vector = marker2_position.vector_to shape2_position
			distance_vector = distance1_vector - distance2_vector
			if distance_vector != [0,0,0]
				@translation = Geom::Transformation.new distance_vector.reverse
			else
				@translation = nil
			end
			# we can now remove temporary group
			temp_grp.explode
			
			# and we also need to remember it so we can load it at some later time...
			# but only store it if it doesn't exist yet
			@dictionary[rule_ID] = ['RuleReplaceOneShape', origin_uid, shape_uid,
				origin_new_uid, shape_new_uid, mirror_x, mirror_y]
			return true
		end

		########################################################################
		# Apply rule to speficied shape.
		# 
		# Accepts:
		# mark_rule is a flag to tell if original shape should be marked with
		# the rule or not. If true the shape will receive rule_id and will thus
		# not be found by collect_candidate_shapes method for that specific rule.
		# rule id defines the rule which will be applied
		# original_shape is the actual shape to which rule will be applied. This
		# shape will then be substituted (erased) with those defined by the rule.
		# mirror_x and mirror_y can be either 1 or -1. 1 means no reflection, -1
		# means reflection in specified direction.
		# 
		# Notes:
		# Component that represents shape boundary should only contain one face
		# which can be convex.
		# 
		# Returns:
		# New shapes which are result of rule application or false when rule
		# application does not change the design (all new shapes are identical
		# to already existent ones).
		########################################################################
		def apply_rule(mark_rule, original_shape, mirror_x, mirror_y)
			# get position of original shape
			original_transformation = original_shape.transformation
			reflection = 0
			
			# calculate mirroring if needed
			if @mirror_x == true or @mirror_y == true
				# if original_shape is already mirrored, we need to recalculate
				# scaling transformation to adapt it
				if original_transformation.xaxis.x == -1
					mirror_x = mirror_x * -1
				end
				if original_transformation.yaxis.y == -1
					mirror_y = mirror_y * -1
				end
				# apply mirroring if needed
				unless mirror_x == 1 and mirror_y == 1
					# let's apply the transformation!
					reflection = Geom::Transformation.scaling original_shape.position, mirror_x, mirror_y, 1
					original_shape.transform! reflection
				end
			end
			
			# now get proper transformation
			original_transformation = original_shape.transformation
			Controller.temp_original_shape = nil
			
			# copy shapes of the rule and initialize them
			new_shapes = Array.new
			@shape_new.each do |entity|
				# when shape is copied via Ruby, it doesn't copy the dictionary
				new_entity = entity.copy
				dict = new_entity.attribute_dictionary 'IterativeSG', true
				new_shapes << new_entity
				Controller::initialize_shape(new_entity)
				new_entity.layer = @solution_layer
			end

			# now transform the group so that it matches
			# original shape transformation
			new_entity = Sketchup.active_model.entities.add_group new_shapes
			
			# Once in group, move the shapes to correct location so we have
			# correct origin when applying transformation! We calculate the
			# distance only when rule is defined!
			if @translation != nil
				new_shapes.each do |ent|
					ent.transform! @translation
				end
			end
			
			# once distance is calculated apply transformation
			new_entity.transformation = original_transformation
			
			# explode groups at correct position and filter them to shapes
			exploded_ents = new_entity.explode
			new_shapes = exploded_ents.select {|ent| ent.is_a? Sketchup::ComponentInstance}
			new_shapes.each do |ent|
				ent.update_shape
				# also update list of @solution_shapes
				Controller::solution_shapes << ent
			end
			
			# now make sure rule application is inside
			# bounds, if not, erase all and return false
			new_shapes.each do |shape|
				if Geometry::inside_boundary?(shape.position, shape.points) == false
					# if rule is outside boundary, base shape shuld be marked
					# so that the rule is not applied anymore
					if mark_rule == true
						original_shape.rules_applied << @rule_ID
						original_shape.rules_applied.flatten!
					end
					Controller.temp_original_shape = original_shape
					new_shapes.each { |shp| Controller::remove_shape(shp) }
					return false
				end
			end
			
			# count removed shapes. If the number of removed shapes is identical
			# to the number of new shapes, we know nothing is changed - consider
			# the rule to not be applied
			removed_shapes_count = 0
			new_shapes_count = new_shapes.length
			
			if mark_rule == true
				original_shape.rules_applied << @rule_ID
				original_shape.rules_applied.flatten!
				original_shape.rules_applied.uniq!
			end
			
			# see if any new shape is identical to original shape. If so,
			# remove it
			remove_original_shape = true
			new_shapes.each do |ent|			
				# now find out which shape replaces previous one and mark it
				# TODO we should define this by the rule itself!
				if Geometry::identical?(ent, original_shape)
					# remove shape form list as we do not need to check it again.
					new_shapes.delete ent
					Controller.remove_shape(ent)
					Controller.temp_original_shape = original_shape
					removed_shapes_count += 1
					remove_original_shape = false
					break
				end
			end
			# In any case we should remove original shape
			Controller.remove_shape(original_shape) if remove_original_shape == true
			
			# TODO improve search mechanism
			# also make sure there are no other shapes identical to new ones
			# created. If there are, replace them and update rules_applied.
			new_shapes.each do |ent|
				# remove entity from the search using clone, otherwise it is 
				#just a pointer and shape gets removed from @shapes list.
				temp_shapes = Controller.solution_shapes.clone
				# remove compared entity, so it is not matched against itself.
				temp_shapes.delete ent
				temp_shapes.each do |shp|
					# if identical entity is found, erase new one
					if Geometry::identical?(ent, shp)
						Controller.remove_shape(ent)
						removed_shapes_count += 1
						# we can skip all other shapes for this ent
						break
					end
				end
			end
			
			# if shapes just replaced existing ones, do
			# not count it as a rule application
			if removed_shapes_count == new_shapes_count
				return false
			end
			$test << new_shapes
			
			return Controller.solution_shapes
		end
		# original_shape = Sketchup.active_model.selection[0]
		# ISGC::apply_rule(false, 'Rule 1', sel, 1, 1)
	end
end
$test = []