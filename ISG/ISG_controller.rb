################################################################################
# Filename: ISG_controller.rb
# Created as a part of "Iterative Shape Grammars" experiment to assess if the
# proposed method can improve traditional SG methods, which tipically defines
# all rules prior to generating design.
# Author: Jernej Vidmar
# Version: 0.1
# Date: December, 2013
################################################################################

Sketchup.send_action "showRubyPanel:"
# Load all other files
rubyScriptsPath = File.expand_path(File.dirname(__FILE__))
Sketchup.load(File.join(rubyScriptsPath, 'ISG_geometry'))
Sketchup.load(File.join(rubyScriptsPath, 'ISG_extensions'))
Sketchup.load(File.join(rubyScriptsPath, 'ISG_user_interface'))
# Load also SKUI for GUI
Sketchup.load(File.join(rubyScriptsPath, 'SKUI', 'core.rb'))

################################################################################
# Base ShapeGrammars module for namespace clashes prevention
################################################################################
module IterativeSG
	############################################################################
	# ShapeGrammars process is controlled using dedicated singleton Controller
	# object.
	############################################################################
	class Controller
		# We only need one Controller, so make it Singleton.
		private_class_method :new
		@@controller = nil
		
		# Create Class level accessors
		class << self
			attr_reader :rules_layer, :solution_layer, :initial_shape
			attr_reader :rules, :boundary_component, :solution_shapes
			attr_reader :shapes, :UIDs, :entities_by_UID
		end

		########################################################################
		# Initialize ShapeGrammar Controller and set up all needed variables to
		# work with it. Controller initialization also sets up layers, ...
		# 
		# Prior to initializing Controller user has to select boundary object
		# which is represented by a SketchUp Component entity. For now this
		# works only in horizontal plane (2D).
		# 
		# Accepts:
		# Bounary object which is of class Sketchup::ComponentInstance.
		# 
		# Notes:
		# Component that represents shape boundary should only contain one face
		# which can be convex.
		# 
		# Returns:
		# True if initialization is sucesfull, False otherwise.
		########################################################################
		def Controller::initialize(boundary_component = Sketchup.active_model.selection[0])
			if boundary_component.is_a? Sketchup::ComponentInstance and
				  boundary_component.definition.name.include? 'Boundary'
				# do nothing, all seems OK
			# if boundary component is not selected, try to guess it
			else
				components = Sketchup.active_model.entities.select { |ent|
					ent.is_a? Sketchup::ComponentInstance }
				boundaries = components.select { |ent|
					ent.definition.name.include? 'Boundary' }
				if boundaries.length > 1
					UI.messagebox "Please select boundary Component!", MB_OK
					return false
				else
					boundary_component = boundaries[0]
				end
			end
			
			# create new controller if it does not exist yet
			@@controller = new unless @@controller
			
			# setup layers
			model = Sketchup.active_model
			layers = model.layers
			@rules_layer = layers.add "ISG Rules"
			@solution_layer = layers.add "ISG Solution"
			@boundary_layer = layers.add "ISG Boundary"
			# create dictionary to store values that need to be saved...
			@dict_shapes = model.attribute_dictionary 'ISG_shapes', true
			@dict_rules = model.attribute_dictionary 'ISG_rules', true
			# create @UIDs so each object can be found after reopening model...
			@UIDs = Array.new
			# Initialize existing shapes
			@shapes = Array.new
			@solution_shapes = Array.new
			# hash of rules
			@rules = Hash.new
			# entities by UID enable us to quickly call entity by its UID
			@entities_by_UID = Hash.new
			# Setup boundary and Geometry module to work with it
			@boundary_component = boundary_component
			Geometry.initialize(boundary_component)
			# now we can initialize all existing shapes and markers
			initialize_existing_shapes
			initialize_origin_markers
			
			# once shapes and markers are initialized, we should cleanup rules
			cleanup_rules
			
			# we can now initialize existing rules
			initialize_existing_rules
		
			return true
		end
		# IterativeSG::Controller::initialize
		
		########################################################################
		# Apply specified rule to speficied shape.
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
		def Controller::apply_rule(mark_rule, rule_id, original_shape, mirror_x, mirror_y)
			# get position of original shape
			original_transformation = original_shape.transformation
			reflection = 0
			
			# calculate mirroring if needed
			if @rules[rule_id]['mirror_x'] == true or @rules[rule_id]['mirror_y'] == true
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
			@new_original_shape = nil
			
			# copy shapes of the rule and initialize them
			new_shapes = Array.new
			@rules[rule_id]['shape_new'].each do |entity|
				# when shape is copied via Ruby, it doesn't copy the dictionary
				new_entity = entity.copy
				dict = new_entity.attribute_dictionary 'IterativeSG', true
				new_shapes << new_entity
				initialize_shape(new_entity)
				new_entity.layer = @solution_layer
			end

			# now transform the group so that it matches
			# original shape transformation
			new_entity = Sketchup.active_model.entities.add_group new_shapes
			
			# Once in group, move the shapes to correct location so we have
			# correct origin when applying transformation! We calculate the
			# distance only when rule is defined!
			if @rules[rule_id]['translation'] != nil
				new_shapes.each do |ent|
					ent.transform! @rules[rule_id]['translation']
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
				@solution_shapes << ent
			end
			
			# now make sure rule application is inside
			# bounds, if not, erase all and return false
			new_shapes.each do |shape|
				if Geometry::inside_boundary?(shape.position, shape.points) == false
					# if rule is outside boundary, base shape shuld be marked
					# so that the rule is not applied anymore
					if mark_rule == true
						original_shape.rules_applied << rule_id
						original_shape.rules_applied.flatten!
					end
					@new_original_shape = original_shape
					new_shapes.each { |shp| remove_shape(shp) }
					return false
				end
			end
			
			# count removed shapes. If the number of removed shapes is identical
			# to the number of new shapes, we know nothing is changed - consider
			# the rule to not be applied
			removed_shapes_count = 0
			new_shapes_count = new_shapes.length
			
			if mark_rule == true
				original_shape.rules_applied << rule_id
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
					remove_shape(ent)
					@new_original_shape = original_shape
					removed_shapes_count += 1
					remove_original_shape = false
					break
				end
			end
			# In any case we should remove original shape
			remove_shape(original_shape) if remove_original_shape == true
			
			# TODO improve search mechanism
			# also make sure there are no other shapes identical to new ones
			# created. If there are, replace them and update rules_applied.
			new_shapes.each do |ent|
				# remove entity from the search using clone, otherwise it is 
				#just a pointer and shape gets removed from @shapes list.
				temp_shapes = @solution_shapes.clone
				# remove compared entity, so it is not matched against itself.
				temp_shapes.delete ent
				temp_shapes.each do |shp|
					# if identical entity is found, erase new one
					if Geometry::identical?(ent, shp)
						remove_shape(ent)
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
			
			return @solution_shapes
		end
		# original_shape = Sketchup.active_model.selection[0]
		# ISGC::apply_rule(false, 'Rule 1', sel, 1, 1)
		
		########################################################################
		# Create design based on specified number of rule applications and rules
		# used.
		# 
		# Accepts:
		# num_of_applications tells controller how many rules should be applied.
		# rules tells ISG which rules should be used.
		# timeout sets how long should the method run (this way we can avoid
		# generations that take too long to compute).
		# 
		# Notes:
		# 
		# Returns:
		# True once generation finishes.
		########################################################################		
		def Controller::generate_design(num_of_applications, rules = @rules.keys, timeout = 20)
			application_counter = num_of_applications
			# remember which rules are used at this generation so we can remove
			# them when they can not be applied anymore
			@temp_rules = rules.clone
			timer = Time.now.to_f
			time = 0
			rules_applied = 0
			until application_counter == 0 do
				# exit generation if there are no more rules which can be applied.
				if @temp_rules.empty?
					puts "Generation finished after #{rules_applied} rules applied."
					break 
				end
				
				# pick random rule
				rule_id = @temp_rules[rand(@temp_rules.length)]
				# find appropriate candidates for specified rule
				candidate_shapes = collect_candidate_shapes(rule_id)
				# exit if there is no candidate for this rule and also remove
				# the rule from list of rules
				if candidate_shapes == nil
					@temp_rules.delete rule_id
					next 
				end

				# pick random candidate
				original_shape = candidate_shapes[rand( candidate_shapes.length)]
				# calculate random reflection (1 or -1)
				mirror_x = rand(2)
				mirror_x = -1 if mirror_x == 0
				mirror_y = rand(2)
				mirror_y = -1 if mirror_y == 0
				
				# now apply the rule
				new_shapes = Controller::apply_rule(false, rule_id, original_shape, mirror_x, mirror_y)
				# if new_shapes is false, it means that rule application did not
				# change the design (all new shapes were identical to some already
				# exising). We therefore reapply it with inverse mirroring
				# and set the mark_rule flag, so it will remember that this rule
				# should not be used on this shape anymore. At the moment this
				# is OK only for shape rules with 1 mirror axis.
				# TODO improve for shapes with no mirror axis or with 2 mirror axis!
				if new_shapes == false and @new_original_shape != nil
					new_shapes = Controller::apply_rule(true, rule_id, @new_original_shape,
						(mirror_x * -1), (mirror_y * -1))
				end
				
				# exit if timeout is reached
				if (Time.now.to_f - timer) > timeout
					# round timeout to two decimals
					application_counter = 0
				end
				# do not count it if rule application didn't create any new shapes...
				next if new_shapes == false
				
				Sketchup.active_model.active_view.refresh
				
				application_counter -= 1
				rules_applied += 1
			end
			completion_time = (((Time.now.to_f - timer)*100).round)/100.0
			puts "Completion time =  #{completion_time}"
			puts "Rules applied = #{rules_applied}"
			additional_info = String.new
			if num_of_applications != rules_applied
				additional_info = "\nGeneration exited early: #{rules_applied} rules were applied."
			end
			UI.messagebox "Shape generation done in #{completion_time} sec.#{additional_info}", MB_OK
			return true
		end
		# IterativeSG::Controller::initialize;   IterativeSG::Controller::generate_design(100)
		# IterativeSG::Controller::generate_design(100)
		
		########################################################################
		# Create ISG rule. This method serves only to remember which entites
		# define Shape Rule.
		# 
		# Accepts:
		# rule_ID - rule identifier
		# mirror_x -  can the rule mirrored in x direction?
		# mirror_y -  can the rule mirrored in y direction?
		# origin - marker to set origin of existing shape
		# shape - existing shape (Group with Face)
		# origin_new -  marker to set origin of new shape.
		# shape_new - array of shapes (Groups with Face) that represent new shape
		# 
		# Notes:
		# shape_new can contain several groups.
		# 
		# 
		# Returns:
		# True when rule definition is sucessful.
		########################################################################	
		def Controller::define_rule(rule_ID, mirror_x = false, mirror_y = false,
				origin = @temp_origin, shape = @temp_shape,
				origin_new = @temp_origin_new, shape_new = @temp_shape_new)
			# setup origin of base shape
			origin_uid = origin.UID
			# setup base shape. If it is alread setup, it will just return its UID
			shape_uid = shape.UID
			# shape.set_attribute rule_ID, 'shape', shape_uid
			
			# setup origin of shape rule application
			origin_new_uid = origin_new.UID
				
			# create shape rule application
			shape_new_uid = Array.new
			shape_new.each do |shp|
				# collect all shape's UIDs so we can store them in dictionary
				shape_new_uid << shp.UID
			end
			
			# TODO add all objects to @rules_layer
			
			# store it in ruby hash
			@rules[rule_ID] = Hash.new
			@rules[rule_ID]['origin'] = origin
			@rules[rule_ID]['shape'] = shape
			@rules[rule_ID]['origin_new'] = origin_new
			@rules[rule_ID]['shape_new'] = shape_new
			@rules[rule_ID]['mirror_x'] = mirror_x
			@rules[rule_ID]['mirror_y'] = mirror_y
			
			# create temporary group so we can calculate origin
			temp_grp = Sketchup.active_model.entities.add_group shape_new
			
			# calculate distance vector from original shape to to its marker
			marker1_position = origin.position
			shape1_position = shape.bounds.min
			marker2_position = origin_new.position
			shape2_position = temp_grp.bounds.min
			distance1_vector = marker1_position.vector_to shape1_position
			distance2_vector = marker2_position.vector_to shape2_position
			distance_vector = distance1_vector - distance2_vector
			if distance_vector != [0,0,0]
				# puts "distance_vector = #{distance_vector}"
				@rules[rule_ID]['translation'] = Geom::Transformation.new distance_vector.reverse
			end
			
			temp_grp.explode
			
			
			# and we also need to remember it so we can load it at some later time...
			# but only store it if it doesn't exist yet
			if @dict_rules[rule_ID] == nil
				  @dict_rules[rule_ID] = [origin_uid, shape_uid, origin_new_uid,
					  shape_new_uid, mirror_x, mirror_y]
			end
			return true
		end
		# IterativeSG::Controller::define_rule(rule_ID, origin, shape, origin_new, shape_new)

		########################################################################
		# Helper method to quickly pick original shape. That is the shape which
		# will be replaced by new shape(s) once rule is applied. This method is
		# intended to be called once user has selected origin marker and shape.
		# 
		# Accepts:
		# If argument is provided, it should an array which contains Origin mark
		# and one Shape. If arguments are not provided this method will pick
		# them up based on selection. In the future we might also accept
		# Sketchup::Face as shape argument and automatically convert it to
		# Group, but for now it is OK.
		# 
		# Notes:
		# 
		# Returns:
		# Marker and Shape, both set up for ISG work.
		########################################################################
		def Controller::pick_original_shape(selection = Sketchup.active_model.selection.to_a)
			if selection.length != 2
				UI.messagebox "Please select one origin marker and one shape. Both should be SketchUp components.", MB_OK
				return false
			end
			marker = selection.select {|ent| ent.definition.name == 'ISG_OriginMarker'}
			shape = selection.select {|ent| ent.definition.name.include? 'Shape'}
			
			# If all is OK, initialize marker
			if marker.length == 1
				initialize_marker(marker[0])
			else
				UI.messagebox "Please make sure you have selected correct marker (Component name = ISG_OriginMarker.", MB_OK
				return false
			end
			
			# If all is OK, initialize shape
			if shape.length == 1
				initialize_shape(shape[0])
			else
				UI.messagebox "Please make sure you have only one Component selected as a basic shape.", MB_OK
			end
			
			@temp_origin = marker[0]
			@temp_shape = shape[0]
			# now return them
			return marker[0], shape[0]
		end
		# IterativeSG::Controller::pick_original_shape
		
		########################################################################
		# Helper method to quickly pick new shape. We need to specify one origin
		# marker (component instance) and at least one shape (group). Of course.
		# shape can also be composed from many shapes. This method is to be used
		# once user selects new origin marker and new shape.
		# 
		# Accepts:
		# If argument is provided, it should an array which contains Origin mark
		# and one Shape. If arguments are not provided this method will pick
		# them up based on selection.
		# 
		# Notes:
		# 
		# Returns:
		# Marker and Shapes array, both set up for ISG work.
		########################################################################
		def Controller::pick_new_shape(selection = Sketchup.active_model.selection.to_a)
			# exit if marker is not picked up correctly
			marker = selection.select {|ent| ent.definition.name == 'ISG_OriginMarker'}
			if marker.length != 1
				UI.messagebox "Please make sure you have selected correct marker (Component name = ISG_OriginMarker.", MB_OK
				return false
			else
				initialize_marker(marker[0])
			end	
			
			
			# filter shapes to groups
			shapes = selection.select {|ent| ent.definition.name.include? 'Shape'}
			# TODO also make sure original shape is not among picked shapes...
			if shapes.length < 1
				UI.messagebox "Please make sure you have at least one SketchUp component selected as a derived shape.", MB_OK
				return false
			else
				shapes.each do |shape|
					initialize_shape(shape)
				end
			end
			@temp_origin_new = marker[0]
			@temp_shape_new = shapes
			return marker[0], shapes
		end

		
		########################################################################
		# Generate new rule name based on the number of already existent rules.
		# Template used: "Rule n" where n is number of rules + 1.
		# 
		# Accepts:
		# Nothing
		# 
		# Notes:
		# 
		# Returns:
		# String with a name of proposed rule (eg. "Rule 1"
		########################################################################
		def Controller::generate_rule_name
			number = @rules.keys.length + 1
			return "Rule #{number}"
		end
		
		########################################################################
		# Prepares empty SketchUp model for work with ISG.
		# 
		# Accepts:
		# initialize_rules specifies if example rule should be initialized or not.
		# 
		# Notes:
		# 
		# Returns:
		# nil
		########################################################################
		def Controller::prepare_model
			# setup model, cleanup all elements
			model = Sketchup.active_model
			entities = model.entities
			# unlock entities prior to erasing
			entities.each do |ent|
				next unless ent.is_a? Sketchup::ComponentInstance
				ent.locked = false if ent.locked? == true
			end
			entities.erase_entities entities.to_a
			
			rubyScriptsPath = File.expand_path(File.dirname(__FILE__))
			isg_lib_path = File.join(rubyScriptsPath, 'ISG_lib')
			
			style_file = File.join(isg_lib_path, 'ISG.style')		
			status = model.styles.add_style style_file, true
			
			# set units to inches
			model.options["UnitsOptions"]["LengthUnit"] = 0
			
			# load template file
			template_file = File.join(isg_lib_path, "ISG_Template.skp")
			template = model.definitions.load template_file
			# place it in the model
			model.entities.add_instance template, [0,0,0]
			template_instance = template.instances
			
			# and explode it
			template_instance[0].explode
			model.definitions.purge_unused
			
			# view it properly
			model.active_view.camera.set( [-160,-300,730], [150,390,-230], [0,0,1])
			model.shadow_info["UseSunForAllShading"] = true
			
			# we know template model rule so create it if needed...
			
			rule = ["ewi05qc058p7i", "2pvcdxzxh9jaz", "mlfhnbw339ng1", ["1cf3rnstfmfpl", "h2nb5gwfwiihl"], true, true]
			dict_rules = model.attribute_dictionary 'ISG_rules', true
			dict_rules['Rule 1'] = rule
			
			# add layers
			self.initialize
			
			return nil
		end
		# ISGC::prepare_model
		
		########################################################################	
		# PRIVATE METHODS BELOW!
		########################################################################	
		private
		
		########################################################################
		# Extend Sketchup::Group with ISG methods. Also initialize it, so it
		# will contain unique ID.
		# 
		# Accepts:
		# A Group with a face that represents a shape.
		# 
		# Notes:
		# 
		# 
		# Returns:
		# UID of new shape
		########################################################################
		def Controller::initialize_shape(entity)
			unless entity.is_a? Sketchup::ComponentInstance
				UI.messagebox "Please select shape Component!", MB_OK
				return false
			end
			# if group is not yet initialized
			unless entity.respond_to? :initialize_ISG_shape
				# extend it with ISG methods
				entity.send(:extend, IterativeSG::ComponentInstance)
				# initialize the shape
				uid = generate_UID
				shp_uid = entity.initialize_ISG_shape(uid)
			end
			shp_uid = entity.UID unless shp_uid
			entity.name = 'ISG_Shape' unless entity.name == 'ISG_Shape'
						
			# maybe user forgot to put shapes inside boundary
			entity.update_shape
			if Geometry::inside_boundary?(entity.position, entity.points) == true
				entity.layer = @solution_layer
			end

			@UIDs << shp_uid
			@entities_by_UID[shp_uid] = entity
			# and add it to list of shapes
			@shapes << entity
			return shp_uid
		end
		
		########################################################################
		# Once we want to delete specific shape from design, we need to cleanup
		# several variables. This method takes care of it.
		# 
		# Accepts:
		# Shape (group)
		# 
		# Notes:
		# 
		# Returns:
		# True once all is cleaned up.
		########################################################################
		def Controller::remove_shape(component_instance)
			@UIDs.delete component_instance.UID
			@entities_by_UID.delete(component_instance.UID)
			@shapes.delete component_instance
			@solution_shapes.delete component_instance
			Sketchup.active_model.entities.erase_entities component_instance
			return true
		end
		
		########################################################################
		# Extend Sketchup::ComponentInstance with ISG methods. Also initialize it,
		# so that it contains unique ID.
		# 
		# Accepts:
		# An ISG_OriginMarker ComponentInstance.
		# 
		# Notes:
		# 
		# 
		# Returns:
		# UID of new marker.
		########################################################################
		def Controller::initialize_marker(component_instance)
			unless component_instance.is_a? Sketchup::ComponentInstance
				UI.messagebox "Please select ISG OriginMarker!", MB_OK
				return false
			end
			# if marker is not yet initialized
			unless component_instance.respond_to? :initialize_ISG_marker
				# extend it with ISG methods
				component_instance.send(:extend, IterativeSG::ComponentInstance)
				# and initialize it
				uid = generate_UID
				uid = component_instance.initialize_ISG_marker(uid)
			end
			uid = component_instance.UID unless uid

			@UIDs << uid
			@entities_by_UID[uid] = component_instance
			return uid
		end
		
		########################################################################
		# Initialize all existing ISG shapes in the model.
		# 
		# Accepts:
		# Nothing, fully automatic.
		# 
		# Notes:
		# 
		# Returns:
		# Array of all initialized shapes (Sketchup::Groups)
		########################################################################
		def Controller::initialize_existing_shapes
			model = Sketchup.active_model
			initialized_shapes = Array.new
			all_components = model.entities.to_a.select {|ent| ent.is_a? Sketchup::ComponentInstance}
			all_shapes = all_components.select {|ent| ent.definition.name.include? 'Shape'}
			all_shapes.each do |component|
				attrdict = component.attribute_dictionary 'IterativeSG'
				next if attrdict == nil
				initialize_shape(component)
				initialized_shapes << component
				# also add group to @solution_shapes
				@solution_shapes << component if component.layer == @solution_layer
			end
			return initialized_shapes
		end
		
		########################################################################
		# Initialize all origin markers in the model.
		# 
		# Accepts:
		# Nothing, fully automatic.
		# 
		# Notes:
		# 
		# Returns:
		# Array of all initialized markers (Sketchup::ComponentInstance)
		########################################################################
		def Controller::initialize_origin_markers
			model = Sketchup.active_model
			initialized_markers = Array.new
			all_components = model.entities.to_a.select {|ent| ent.is_a? Sketchup::ComponentInstance}
			all_markers = all_components.select {|ent| ent.definition.name.include? 'Marker'}
			all_markers.each do |obj|
				attrdict = obj.attribute_dictionary 'IterativeSG'
				next if attrdict == nil
				initialize_marker(obj)
				initialized_markers << obj
			end
			return initialized_markers
		end
		
		########################################################################
		# Define all existing rules, so we can work with objects directly.
		# 
		# Accepts:
		# Nothing, fully automatic.
		# 
		# Notes:
		# 
		# Returns:
		# List of all rules
		########################################################################
		def Controller::initialize_existing_rules
			@dict_rules.each_pair do |name, rules|
				rule_ID = name
				# get objects from their UIDs
				origin = @entities_by_UID[rules[0]] # origin
				shape = @entities_by_UID[rules[1]] # shape
				origin_new = @entities_by_UID[rules[2]] # origin_new		
				shape_new = Array.new
				rules[3].each do |ent| # shape_new
					shape_new << @entities_by_UID[ent]
				end
				mirror_x = rules[4]
				mirror_y = rules[5]
				self.define_rule(rule_ID, mirror_x, mirror_y, origin, shape, origin_new, shape_new)
			end
		end
		#  IterativeSG::Controller::initialize; IterativeSG::Controller.rules
		
		########################################################################
		# Generate unique string of 12 alphanumeric characters.
		# 
		# Accepts:
		# Nothing, fully automatic.
		# 
		# Notes:
		# 
		# Returns:
		# Uniqe IDentifier.
		########################################################################
		def Controller::generate_UID
			uid = rand(2**256).to_s(36).ljust(8,'a')[0..12]
			# make sure no two UIDs are the same by using recursive function.
			if @UIDs.include? uid
				uid = generate_UID
			end
			# add it to list of all UIDs
			return uid
		end
		
		########################################################################
		# Set unique ID to speficied object's dictionary.
		# 
		# Accepts:
		# Sketchup entitiy, to which UID is applied.
		# 
		# Notes:
		# If UID is not present it will be populated with received one. If it is
		# present, but it matches one which is present within UIDs list, it will
		# be replaced with a new one. If it is prsent but not contained within
		# UIDs list, it will just update UIDs list.
		# 
		# Returns:
		# Uniqe IDentifier.
		########################################################################
		def Controller::set_UID(entity, uid)
			current_uid = entity.get_attribute 'IterativeSG', 'UID'
			if current_uid == nil
				entity.set_attribute 'IterativeSG', 'UID', uid
				return uid
			else
				if @UIDs.include? current_uid
					entity.set_attribute 'IterativeSG', 'UID', uid
					return uid
				else
					return current_uid
				end
			end
		end
		
		########################################################################
		# Collect all shapes to which specified rule can be applied.
		# 
		# Accepts:
		# rule_id is a string which represents a rule (eg. 'Rule 1')
		# 
		# Notes:
		# 
		# Returns:
		# List of all shapes to which rule can be applied or nil if no shape
		# can accept specified rule.
		########################################################################	
		def Controller::collect_candidate_shapes(rule_id)
			# limit candidates to instances of correct component definition
			instances = Array.new
			temp_definitions = Array.new
			@rules[rule_id]["shape_new"].each do |ent|
				definition = ent.definition
				# skip adding if this definition is already added
				next if temp_definitions.include? definition
				instances << definition.instances
				temp_definitions << definition
			end
			instances.flatten!
			
			# now collect only those in solution layer
			shapes =  instances.select {|shp| shp.layer == @solution_layer}
			
			# and filter to those, who are not marked with rule. If rule is marked
			# it means it can not be applied anymore
			candidates = shapes.select {|shp| not shp.rules_applied.include? rule_id}

			if candidates.empty?
				return nil
			else
				return candidates
			end
		end
		# ISGC::collect_candidate_shapes("Rule 1")
		
		########################################################################
		# Cleanup all rules where there is some entity missing (origin marker,
		# shape, new shape or new origin marker)
		# 
		# Accepts:
		# Nothing,  fully automatic
		# 
		# Notes:
		# 
		# Returns:
		# List of all rules deleted or nil if no rule was deleted.
		########################################################################	
		def Controller::cleanup_rules
			deleted_rules = Array.new
			@dict_rules.each_pair do |rule_name, rules|
				delete_rule = false
				rules.flatten!
				rules.each do |ent|
					next unless ent.is_a? String
					# if entity doesn't exist, delete rule
					if (@entities_by_UID[ent] == nil) or (@entities_by_UID[ent].deleted?)
						puts 'deleted ent found'
						delete_rule = true
					end
				end
				
				# delete rule from dictionary of rules and @rules
				# variable if some entitiy doesn't exist
				if delete_rule == true
					@dict_rules.delete_key rule_name
					@rules.delete rule_name
					deleted_rules << rule_name
				end
			end
			if deleted_rules.empty?
				return nil 
			else
				return deleted_rules
			end
		end

	end
end

# Once all scripts are loaded, we can add UI
IterativeSG::UI_Menu::create_menu

# Helper methods - remove for public release
ISGC = IterativeSG::Controller
def sel_array; return Sketchup::active_model.selection.to_a; end
def sel; return Sketchup::active_model.selection[0]; end