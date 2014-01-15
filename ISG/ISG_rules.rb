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
		attr_reader :rule_ID ,:shape, :isg_type
		attr_reader :requested_objects, :mirror_x, :mirror_y
		
		def find_by_ID(rule_ID)
			
		end
	end

	############################################################################
	# Class Replace is used for shape rules where one (or more) shape is
	# replaced by another.
	############################################################################
	class Replace
		include RulesBase
		########################################################################
		# Initialize rule object and populate it with needed information.
		# 
		# Accepts:
		# specification_hash where:
		# rule_ID - defines the name of the rule
		# origin - specifies the origin of shape to which rule is applied
		# shape - is the shape to which rule is applied
		# origin_new - specifies the origin of new shape
		# shape_new - specifies the shapes which replace current shape
		# mirror_x and mirror_y - can be either 1 or -1. 1 means no reflection, -1
		# means reflection in specified direction.
		# 
		# Notes:
		# 
		# Returns:
		# New object created.
		########################################################################
		def initialize(specification_hash)
			# define variables
			@dictionary = Controller.dict_rules
			@solution_layer = Controller.solution_layer
			@rule_ID = specification_hash['rule_ID']
			@origin = specification_hash['origin']
			@shape = specification_hash['shape']
			@origin_new = specification_hash['origin_new']
			@shape_new = specification_hash['shape_new']
			@mirror_x = specification_hash['mirror_x']
			@mirror_y = specification_hash['mirror_y']
			@disable_overlaping = specification_hash['disable_overlaping']
			@isg_type = 'Replace'
			# also store shape definitions that are used by this rule
			@shape_definitions = Array.new
			
			# setup origin of base shape
			origin_uid = @origin.UID
			# setup base shape. If it's already setup, just return its UID
			shape_uid  = Array.new
			@shape.each do |shp|
				shape_uid << shp.UID
				@shape_definitions << shp.definition
			end
			@shape_definitions.uniq!
			
			# setup origin of shape rule application
			origin_new_uid = @origin_new.UID
				
			# create shape rule application
			shape_new_uid = Array.new
			@shape_new.each do |shp|
				# collect all shape's UIDs so we can store them in dictionary
				shape_new_uid << shp.UID
			end
			
			# create temporary group so we can calculate origin
			temp_grp = Sketchup.active_model.entities.add_group @shape
			temp_grp_new = Sketchup.active_model.entities.add_group @shape_new
			
			# calculate distance vector from original shape to to its marker
			marker1_position = @origin.position
			shape1_position = temp_grp.bounds.min
			marker2_position = @origin_new.position
			shape2_position = temp_grp_new.bounds.min
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
			temp_grp_new.explode
			
			# and we also need to remember it so we
			# can load it at some later time...
			type = ['type', @isg_type]
			origin_uid = ['origin_uid', origin_uid]
			shape_uid = ['shape_uid', shape_uid]
			origin_new_uid = ['origin_new_uid', origin_new_uid]
			shape_new_uid = ['shape_new_uid', shape_new_uid]
			mirror_x = ['mirror_x', @mirror_x]
			mirror_y = ['mirror_y', @mirror_y]
			disable_overlaping = ['disable_overlaping', @disable_overlaping]
			@dictionary[@rule_ID] = [type, origin_uid, shape_uid, origin_new_uid,
				shape_new_uid, mirror_x, mirror_y, disable_overlaping]
			return self
		end

		########################################################################
		# Apply rule to speficied shape.
		# 
		# Accepts:
		# mark_rule - a flag to tell if original shape should be marked with
		# the rule or not. If true the shape will receive rule_id and will thus
		# not be found by collect_candidate_shapes method for that specific rule.
		# original_shape_array - is the actual shape to which rule will be
		# applied. This shape will then be substituted (erased) with those
		# defined by the rule.
		# mirror_x and mirror_y - can be either 1 or -1. 1 means no reflection,
		# -1 means reflection in specified direction.
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
		def apply_rule(mark_rule, original_shape_array, mirror_x, mirror_y)
			original_transformation = 0
			# TODO for now we need to handle single shapes differently than
			# multiple shapes due to Sketchup bug, which causes bugsplat
			# when entities are added to group when defining it.
			# but it seems to work when multiple entities are added...???
			if original_shape_array.length == 1
				original_shape = original_shape_array[0]
				original_transformation = original_shape.transformation
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
				# we can now get proper transformation...
				original_transformation = original_shape.transformation
			else
				# add shapes to group so we do not need to care about transformations
				temp_grp = Sketchup.active_model.entities.add_group original_shape_array
				original_transformation = temp_grp.transformation
				# calculate mirroring if needed
				if @mirror_x == true or @mirror_y == true
					# apply mirroring if needed
					unless mirror_x == 1 and mirror_y == 1
						# let's apply the transformation!
						reflection = Geom::Transformation.scaling temp_grp.bounds.center, mirror_x, mirror_y, 1
						temp_grp.transform! reflection
					end
				end
				# now get proper transformation
				original_transformation = temp_grp.transformation
			end
			# set temp original shape for controller
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
			
			# if overlaping is not allowed, check the shapes
			if @disable_overlaping == true
				# collect all shapes except the shapes that will be replaces.
				solution_shapes = Controller.solution_shapes - original_shape_array
				solution_shapes.each do |shape|
					new_shapes.each do |new_shape|
						if Geometry::overlap_2D?(new_shape, shape) == true
							# fix the shape so that the rule is
							# not applied to it anymore
							if mark_rule == true	
								original_shape_array.each do |original_shape|
									original_shape.rules_applied << @rule_ID
									original_shape.rules_applied.flatten!
									original_shape.rules_applied.uniq!
								end
							end
							Controller.temp_original_shape = original_shape_array
							new_shapes.each { |shp| Controller::remove_shape(shp) }
							return false
						end
					end
				end
			end
						
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
						original_shape_array.each do |original_shape|
							original_shape.rules_applied << @rule_ID
							original_shape.rules_applied.flatten!
						end
					end
					Controller.temp_original_shape = original_shape_array
					new_shapes.each { |shp| Controller::remove_shape(shp) }
					return false
				end
			end

			if mark_rule == true
				original_shape_array.each do |original_shape|
					original_shape.rules_applied << @rule_ID
					original_shape.rules_applied.flatten!
					original_shape.rules_applied.uniq!
				end
			end
			# if original_shape_array.length > 1
			# see if any new shape is identical to original shape.
			# If so, remove it...
			remove_original_shape = true
			original_shape_array.each do |original_shape|
				new_shapes.each do |ent|			
					# now find out which shape replaces previous one and mark it
					# TODO we should define this by the rule itself!
					if Geometry::identical?(ent, original_shape)
						# remove shape from list - we don't need to recheck it
						new_shapes.delete ent
						Controller.remove_shape(ent)
						Controller.temp_original_shape = [original_shape]
						remove_original_shape = false
						break
					end
				end
			end
			
			# In any case we should remove original shape
			if remove_original_shape == true
				original_shape_array.each { |shp| Controller.remove_shape(shp) } 
			end

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
						new_shapes.delete ent
						# we can skip all other shapes for this ent
						break
					end
				end
			end
			# if shapes just replaced existing ones, do
			# not count it as a rule application
			if new_shapes.empty?
				return false
			end
			# elsif original_shape_array.length > 1
				
			return new_shapes
		end
		# original_shape = Sketchup.active_model.selection[0]
		# ISGC::apply_rule(false, 'Rule 1', sel, 1, 1)

		########################################################################
		# Check if rule can be applied to selected shapes.
		# 
		# Accepts:
		# shapes - list of shapes to be checked.
		# 
		# Notes:
		# TODO - improve this method by returning more than one candidate shape
		# 
		# Returns:
		# Ordered list of shapes to which rule can be applied or false if therea
		# are no suitable candidates.
		########################################################################
		def check_rule(shapes)
			# remove boundary if slected
			shapes.delete Controller.boundary_component
			# filter to correct shapes and also return false if no shape
			# is correct component
			all_shapes = Array.new
			correct_definitions = Array.new
			shapes.each do |shp|
				all_shapes << shp if @shape_definitions.include? shp.definition
			end
			return false if all_shapes.empty?
			
			# if there is more than one shape see that the selection matches
			return false if @shape.length > all_shapes.length
			
			# now do also the collection of candidate shapes
			candidates = self.collect_candidate_shapes(all_shapes, true)
			return false if candidates == nil
			
			return candidates
		end
		# ISGC.rules['Rule 3'].check_rule(sel_array)
		
		########################################################################
		# Collect all shapes to which Replace rule instance can be applied.
		# 
		# Accepts:
		# Nothing, fully automatic
		# 
		# Notes:
		# 
		# Returns:
		# One candidate shape to which rule can be applied.
		########################################################################	
		def collect_candidate_shapes(instances = nil, skip_random = false)
			candidates = Array.new
			shape_length = @shape.length
			
			# if there is only one shape in rule we do not have to check much...
			if shape_length == 1
				# limit candidates to instances of correct component definition
				instances = @shape[0].definition.instances unless instances
				# and randomize them
				instances = instances.sort_by { rand } unless skip_random == true

				# now collect only those in solution layer
				shapes =  instances.select {|shp| shp.layer == @solution_layer}
				return nil if instances.empty?

				# we need to find only one, which is not marked with rule. If
				# rule is marked it means it can not be applied anymore!
				shapes.each do |shp|
					candidates << shp unless shp.rules_applied.include? @rule_ID
					break unless candidates.empty?
				end
			# if there is more than 1 shape in the rule,
			# we have to find appropriate match of shapes
			elsif shape_length == 2
				if instances == nil
					shape_1_instances = @shape[0].definition.instances
					shape_1_instances = shape_1_instances.select {|shp| shp.layer == @solution_layer}
					shape_2_instances = @shape[1].definition.instances
					shape_2_instances = shape_2_instances.select {|shp| shp.layer == @solution_layer}
					# randomize shapes so we do not have to check everyone
					# each time; see optimization below..
					shape_1_instances = shape_1_instances.sort_by { rand }
					shape_2_instances = shape_2_instances.sort_by { rand }
				else
					shape_1_instances = instances
					shape_2_instances = instances
				end
				
				# calculate distance only once!
				distance = @shape[0].position.distance(@shape[1].position)
				# also consider vector!
				vector = @shape[0].position.vector_to(@shape[1].position)
				
				# now collect only those in solution layer
				candidates = Array.new
				shape_1_instances.each do |shp|
					# do not check self...
					shape_2_instances.delete shp
					# get distance from shape1 and shape2
					matching_distance = Geometry::get_by_distance(shp,
						shape_2_instances, distance, vector)
					unless matching_distance.empty?
						candidates = ([shp].push matching_distance[0])
					end
					# OPTIMIZATION - we skip expensive (time consuming)
					# checking for other possible candidates if 5 are found.
					break unless candidates.empty?
				end
			end

			if candidates.empty?
				return nil
			else
				return candidates
			end
		end
		# ISGC::collect_candidate_shapes("Rule 1")
	end
	
	############################################################################
	# Class Merge is used for shape rules where two or more shapes are merged
	# together. They can be merged either in x or y direction. For now it is
	# limited to merge only closest shapes. This way it works more on a
	# parametric principle...
	############################################################################
	class Merge
		include RulesBase

		########################################################################
		# Initialize merge rule object and populate it with needed information.
		# 
		# Accepts:
		# specification_hash where:
		# rule_ID - defines the name of the rule
		# merge_in_x - merge shapes in x (horizontal) direction
		# merge_in_y - merge shapes in y (vertical) direction
		# num_of_objects - how many objects should be merged
		# shape_definitions - specifies which shapes can be merged together
		# 
		# Notes:
		# 
		# Returns:
		# New object created.
		########################################################################
		def initialize(specification_hash)
			# define variables
			@dictionary = Controller.dict_rules
			@solution_layer = Controller.solution_layer
			
			@rule_ID = specification_hash['rule_ID']
			@merge_in_x = specification_hash['merge_in_x']
			@merge_in_y = specification_hash['merge_in_y']
			# number of objects to merge
			# TODO - this can be parametric!
			@num_of_objects = specification_hash['num_of_objects']
			# TODO - add in UI
			@max_distance = 1_000.m
			# list of shape definitions on which it works
			@shape_definitions = specification_hash['shape_definitions']
			# specify type for easier acces
			@isg_type = 'Merge'
			
			# define face material based on selection
			edges = @shape_definitions[0].entities.select {|ent| ent.is_a? Sketchup::Edge}
			unless edges.empty?
				@edge_material = edges[0].material
			else
				@edge_material == nil
			end
			faces = @shape_definitions[0].entities.select {|ent| ent.is_a? Sketchup::Face}
			unless faces.empty?
				@face_material = faces[0].material
			else
				@face_material == nil
			end
		
			# and we also need to remember it so we can load it at some
			# later time... but only store it if it doesn't exist yet
			type = ['type', @isg_type]
			merge_in_x = ['merge_in_x', @merge_in_x]
			merge_in_y = ['merge_in_y', @merge_in_y]
			num_of_objects = ['num_of_objects', @num_of_objects]
			definition_names = Array.new
			@shape_definitions.each do |definition|
					definition_names << definition.name
			end
			shape_definitions = ['shape_definitions_names', definition_names]
			
			# now store them to dictionary
			@dictionary[@rule_ID] = Array.new
			@dictionary[@rule_ID] = [type, merge_in_x,
				merge_in_y, num_of_objects, shape_definitions]

			return self
		end

		########################################################################
		# Apply the rule to specified shapes.
		# 
		# Accepts:
		# shapes - list of shapes that will be merged together.
		# 
		# Notes:
		# TODO: add shape checking to see if some newly generated shapes are 
		# the same as existing ones. If so, do not generate new ones but only
		# create new instance of existing component and apply correct
		# transformation.
		# We might want to do this using specification from which shapes new
		# shape is generated.
		# 
		# Returns:
		# New shape which is a result of rule application.
		########################################################################
		def apply_rule(shapes)			
			# collect all information needed
			name = Controller::generate_shape_ID()
			points = Array.new
			shapes.each { |ent| points += ent.points }
			# now add new shape
			new_shape = Geometry::add_face_in_component(name, points,
				@face_material, @edge_material)
			Controller::initialize_shape(new_shape)
			new_shape.applied_by_rule = @rule_ID
			new_shape.layer = @solution_layer
			new_shape.name = 'ISG_Shape'
			
			# and remove original shapes
			entities_to_store = Array.new
			shapes.each do |shp|
				Controller::remove_shape(shp, false)
				entities_to_store << shp
			end
			new_shape.store_erased_entites(entities_to_store)
			return new_shape
		end

		########################################################################
		# Remove specified shape and put back shapes from which it was generated.
		# 
		# Accepts:
		# shape - entity to be erased
		# 
		# Notes:
		# 
		# Returns:
		# True once done
		########################################################################
		def remove_rule(shape)
			hidden_entities = shape.receive_erased_entites()
			hidden_entities.each { |ent| ent.layer = @solution_layer }
			Controller::remove_shape(shape, true)
			return true
		end
		
		########################################################################
		# Check if rule can be applied to selected shapes.
		# 
		# Accepts:
		# shapes - list of shapes to be checked.
		# 
		# Notes:
		# 
		# Returns:
		# Ordered list of shapes to which rule can be applied or false if therea
		# are no suitable candidates.
		########################################################################
		def check_rule(shapes)
			# remove boundary if slected
			shapes.delete Controller.boundary_component
			
			# pick leftmost shape
			sorted_shps = Array.new
			if @merge_in_x == true
				sorted_shps = Geometry::sort_components_in_direction(shapes, :x)
			else
				sorted_shps = Geometry::sort_components_in_direction(shapes, :y)
			end
			# define direction from left to right or from bottom up
			direction = Geom::Vector3d.new 1,0,0
			if @merge_in_y == true
				direction = Geom::Vector3d.new 0,1,0
			end
			# do preliminary check
			candidates = self.collect_candidate_shapes(sorted_shps, direction, true)
			return false if candidates == nil
			
			result = true
			candidates.each do |cand|
				result = false unless sorted_shps.include? cand
			end
			return candidates
		end
		# ISGC.rules['Rule 4'].check_rule(sel_array)

		########################################################################
		# Collect shapes with which we will generate new shape
		# 
		# Accepts:
		# num_of_objects - how many objects should be returned - merged?
		# direction -  direction in which candidates should be searched. If
		# direction is nil, the method will pick random one.
		# skip_random - do not randomize shape picking order. We need to skip
		# randomization when selected shapes are checked for rule applicaton.
		# 
		# Notes:
		# TODO: add shape checking to see if some newly generated shapes are 
		# the same as existing ones. If so, do not generate new ones but only
		# create new instance of existing component and apply correct
		# transformation. We might want to do this using specification from
		# which shapes new shape is generated.
		# 
		# Returns:
		# List of candidate shapes to be merged.
		########################################################################
		def collect_candidate_shapes(all_candidates = @shape_definitions,
				direction = nil, skip_random = false)
			# calculate random direction if needed, we start with x direction
			if direction == nil
				dir = rand(2)
				dir = -1 if dir == 0
				direction = Geom::Vector3d.new dir,0,0
				if @merge_in_x == @merge_in_y
					random = rand(2)
					direction = Geom::Vector3d.new 0,dir,0 if random == 1
				elsif @merge_in_y == true
					direction = Geom::Vector3d.new 0,dir,0
				end
			end
			
			# collect all candidate instances if needed
			instances = Array.new
			if all_candidates == @shape_definitions
				@shape_definitions.each do |shape_definition|
					instances << shape_definition.instances
				end
				instances.flatten!
			else
				instances = all_candidates
			end
					
			# limit to those in solution layer
			instances = instances.select {|i| i.layer == @solution_layer}
			return nil if instances.empty?
			# make copy
			candidates = instances.clone
			
			# pick random instance
			shapes = Array.new
			num = @num_of_objects - 1
			until shapes.empty? == false
				instance = 0
				# skip randomizing in case when check_rule method is called
				if skip_random == false
					instance = instances[rand(instances.length)]
				else
					instance = instances[0]
				end
				# remove object in question from search
				instances.delete instance
				candidates.delete instance

				# now collect closest neighbour
				neighbours = Geometry::collect_in_direction(instance,
					candidates, num, direction, @max_distance) 
				# if nothing was found...
				unless neighbours.empty?
					# check that shapes received are correct component instances
					check = true
					neighbours.each do |comp|
						unless @shape_definitions.include? comp.definition
							instances.delete comp
							check = false
						end
						if Geometry::inside_boundary?(comp.position, comp.points) == false
							instances.delete comp
							check = false
						end
					end
					if check == true
						shapes << instance
						shapes << neighbours
						shapes.flatten!
					end
				end

				return nil if instances.empty?
			end
			# now return the shapes
			return shapes
		end
	end
	
	############################################################################
	# Class Stretch is used for rules which stretch shapes in x or y direction.
	# Since it's parametric it can be used on any shape, only min and max
	# strech dimensions should be provided when initialized and applied.
	############################################################################
	class Stretch
		include RulesBase

		########################################################################
		# Initialize merge rule object and populate it with needed information.
		# 
		# Accepts:
		# specification_hash where:
		# rule_ID - defines the name of the rule
		# stretch_in_x - stretch shapes in x (horizontal) direction
		# stretch_in_y - stretch shapes in y (vertical) direction
		# min_stretch - min value when shrinking shape
		# max_stretch - max value when strething shape
		# constrain_conecting - if true, shapes that connect to shape beeing
		# stretched will be adjusted. if false only one shape will be strethed.
		# shape_definitions - specifies which shapes can be stretched. If this
		# is not specified, rule can stretch any shape.
		# 
		# 
		# Notes:
		# 
		# Returns:
		# New object created.
		########################################################################
		def initialize(specification_hash)
			# define variables
			@dictionary = Controller.dict_rules
			@solution_layer = Controller.solution_layer
			@isg_type = 'Stretch'
			@rule_ID = specification_hash['rule_ID']
			@stretch_in_x = specification_hash['stretch_in_x']
			@stretch_in_y = specification_hash['stretch_in_y']
			@min_stretch = specification_hash['min_stretch']
			@max_stretch = specification_hash['max_stretch']
			@constrain_connecting = specification_hash['constrain_connecting']
			@shape_definitions = specification_hash['shape_definitions']

			
			# prepare them for dict storage
			type = ['type', @isg_type]
			stretch_in_x = ['stretch_in_x', @stretch_in_x]
			stretch_in_y = ['stretch_in_y', @stretch_in_y]
			min_stretch = ['min_stretch', @min_stretch]
			max_stretch = ['max_stretch', @max_stretch]
		
			constrain_connecting = ['constrain_connecting', @constrain_connecting]
			definition_names = Array.new
			@shape_definitions.each do |definition|
					definition_names << definition.name
			end
			shape_definitions = ['shape_definitions_names', definition_names]
			
			# now store them to dictionary
			@dictionary[@rule_ID] = Array.new
			@dictionary[@rule_ID] = [type, stretch_in_x, stretch_in_y,
				min_stretch, max_stretch, shape_definitions, constrain_connecting]
			return self
		end
		
		########################################################################
		# Apply the rule to specified shapes.
		# 
		# Accepts:
		# shape - shape that will be stretched
		# factor_x - factor of how much should the shape be stretched in x direction
		# factor_y - factor of how much should the shape be stretched in y direction
		#  
		# Notes:
		# factor is something between 0 and 10
		# 
		# Returns:
		# New shape which is a result of rule application.
		########################################################################
		def apply_rule(shape, factor_x = 1, factor_y = 1)
			# get original transformation in case we need to set it back
			orig_trans = shape.transformation
			# calculate stretch from factor
			stretch_x = calculate_from_factor(factor_x)
			stretch_y = calculate_from_factor(factor_y)
			# make sure rule can be applied in this direction
			stretch_x = 1 unless @stretch_in_x
			stretch_y = 1 unless @stretch_in_y

			# collect all information needed
			position = shape.position
			# stretch shape
			Geometry::stretch_shape(shape, position, stretch_x, stretch_y)
			# check that it is valid, if not set it back and return false
			shape.update_shape()
			if Geometry::inside_boundary?(shape.position, shape.points) == false
				shape.transformation = orig_trans
				return false
			end
			 # or add rule info to it, so it's not reapplied
			shape.rules_applied << @rule_ID
			# and return it
			return shape
		end
		
		########################################################################
		# Pick random candidate from solution shapes.
		# 
		# Accepts:
		# Nothing
		# 
		# Notes:
		# TODO shape definitions should be added so user is able to apply this
		# rule only to selected shapes.
		# 
		# Returns:
		# Random shape to which rule will be applied.
		########################################################################
		def collect_candidate_shapes
			if @shape_definitions.empty?
				shapes = Controller.solution_shapes
				return shapes[rand(shapes.length)]
			end
		end
		
		########################################################################
		# Helper method to calculate scale based on factor received and min and
		# max values defined.
		# 
		# Accepts:
		# factor - value between 0 and 10
		# 
		# Notes:
		# 
		# Returns:
		# value between @min_stretch and @max_stretch.
		########################################################################
		def calculate_from_factor(factor)
			diff = @max_stretch - @min_stretch
			return (factor/10.0) * diff + @min_stretch
		end
	end
end