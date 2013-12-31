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
			attr_reader :rules, :boundary_component
			attr_reader :shapes, :shape_IDs, :UIDs, :entites_by_UID
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
			unless boundary_component.is_a? Sketchup::ComponentInstance
				UI.messagebox "Please select boundary Component!", MB_OK
				return false
			end
			
			# create new controller if it does not exist yet
			@@controller = new unless @@controller
			
			# setup layers
			model = Sketchup.active_model
			layers = model.layers
			@rules_layer = layers.add "SG Rules Layer"
			@solution_layer = layers.add "SG Solution Layer"
			# create dictionary to store values that need to be saved...
			@dict_shapes = model.attribute_dictionary 'ISG_shapes', true
			@dict_rules = model.attribute_dictionary 'ISG_rules', true
			# populate shape_IDs
			@shape_IDs = [1]
			# create shape_IDs
			@UIDs = Array.new
			# Initialize existing shapes
			@shapes = Array.new
			# hash of rules
			@rules = Hash.new
			# entities by UID enable us to quickly call entity by its UID
			@entites_by_UID = Hash.new
			# now we can initialize all existing shapes and markers
			initialize_existing_shapes	
			initialize_origin_markers
			
			# we can now initialize existing rules
			initialize_existing_rules
			
			# Setup boundary and Geometry module to work with it
			@boundary_component = boundary_component
			Geometry.initialize(boundary_component)
		
			return true
		end
		# IterativeSG::Controller::initialize
		
		########################################################################
		# Apply specified rule to speficied shape.
		# 
		# Accepts:
		# Rule id to set the rule which will be applied
		# Original shape is the actual shape to which rule will be applied. This
		# shape will then be substituted (erased) with those defined by the rule.
		# 
		# Notes:
		# Component that represents shape boundary should only contain one face
		# which can be convex.
		# 
		# Returns:
		# New shapes which are result of rule application.
		########################################################################
		def Controller::apply_rule(rule_id, original_shape)
			# get position of original shape
			original_transformation = original_shape.transformation
			
			# copy shapes of the rule and initialize them
			new_shapes = Array.new
			@rules[rule_id][3].each do |group|
				# when shape is copied via Ruby, it doesn't copy the dictionary
				new_group = group.copy
				dict = new_group.attribute_dictionary 'IterativeSG', true
				dict.set_attribute 'IterativeSG', 'shape_ID', group.shape_ID
				new_shapes << new_group
				new_group.layer = @solution_layer
				self.initialize_shape(new_group)
			end

			# now transform the group so that it matches original shape
			# transformation
			new_group = Sketchup.active_model.entities.add_group new_shapes
			new_group.transformation = original_transformation

			# calculate distance vector from original shape to to its marker
			marker_position = @rules[rule_id][0].bounds.center
			shape_position = @rules[rule_id][1].bounds.center
			distance_vector = marker_position.vector_to shape_position
			if distance_vector.length != 0
				translation = Geom::Transformation.new distance_vector
				new_group.transform! translation
			end	

			shapes = new_group.explode.select {|ent| ent.is_a? Sketchup::Group}
			previous_shape_replacement = nil
			shapes.each do |ent|			
				# now find out which shape replaces previous one and mark it
				# TODO we should define this by the rule itself!
				if Geometry::identical?(ent, original_shape)
					original_rules = original_shape.rules_applied
					ent.rules_applied << rule_id
					ent.rules_applied << original_rules
					ent.rules_applied.flatten!
					break
				end
			end
			
			@shapes.delete original_shape
			@UIDs.delete original_shape.UID
			@entites_by_UID.delete original_shape.UID
			Sketchup.active_model.entities.erase_entities original_shape
			
			return shapes
		end
		# original_shape = Sketchup.active_model.selection[0]
		# IterativeSG::Controller::apply_rule('rule_001', Sketchup.active_model.selection[0])
		
		########################################################################
		# Create design based on specified number of rule applications and rules
		# used.
		# 
		# Accepts:
		# num_of_applications tells controller how many rules should be applied.
		# rules tells ISG which rules should be used.
		# 
		# Notes:
		# 
		# Returns:
		# True once generation finishes.
		########################################################################		
		def Controller::generate_design(num_of_applications, rules = @rules.keys)
			until num_of_applications == 0 do
				@shapes.each do |shape|
					unless shape.valid?
						@shapes.delete shape
					end
				end
				
				# pick random rule
				rule_id = rules[rand(rules.length)]
				# define original shape
				solution_shapes = @shapes.select {|shp| shp.layer == @solution_layer}
				
				# find appropriate candidate
				candidate_found = false
				original_shape = nil
				while candidate_found == false
					length = solution_shapes.length
					original_shape = solution_shapes[rand(length)]
					if original_shape.rules_applied.include? rule_id
						# make sure we do not search it anymore
						solution_shapes.delete(original_shape)
						@shapes.delete(original_shape)
					else
						candidate_found = true
					end
				end
				
				# check that new shapes are inside boundary
				new_shapes = Controller::apply_rule(rule_id, original_shape)
				new_shapes.each do |shape|
					if Geometry::inside_boundary?(shape) == false
						Sketchup.active_model.entities.erase_entities shape
						solution_shapes.delete new_shapes
						@shapes.delete(new_shapes)
						break
					end
				end
				
				Sketchup.active_model.active_view.refresh
				
				num_of_applications -= 1
			end
			return true
		end
		# IterativeSG::Controller::initialize
		# IterativeSG::Controller::generate_design(100)

		########################################################################
		# Create ISG rule. This method serves only to remember which entites
		# define Shape Rule.
		# 
		# Accepts:
		# rule_ID - rule identifier
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
		def Controller::define_rule(rule_ID, origin, shape, origin_new, shape_new)
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
			@rules[rule_ID] = [origin, shape, origin_new, shape_new]
			# and we also need to remember it so we can load it at some later time...
			@dict_rules[rule_ID] = [origin_uid, shape_uid, origin_new_uid, shape_new_uid]
			return true
		end
		# IterativeSG::Controller::define_rule(rule_ID, origin, shape, origin_new, shape_new)


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
		def Controller::initialize_shape(group)
			unless group.is_a? Sketchup::Group
				UI.messagebox "Please select shape Group!", MB_OK
				return false
			end
			# if group is not yet initialized
			unless group.respond_to? :initialize_ISG_shape
				# extend it with ISG methods
				group.send(:extend, IterativeSG::Group)
				# initialize the shape
				# TODO improve shape_ID mechanism.
				uid = generate_UID
				shp_id, shp_uid = group.initialize_ISG_shape(@shape_IDs.last + 1, uid)
			end
			shp_id = group.shape_ID unless shp_id
			shp_uid = group.UID unless shp_uid

			@shape_IDs << shp_id
			@shape_IDs.sort!.uniq!
			@UIDs << shp_uid
			@dict_shapes['shape_IDs'] = @shape_IDs
			@entites_by_UID[shp_uid] = group
			# and add it to list of shapes
			@shapes << group
			return shp_uid
		end
		
		########################################################################
		# Extend Sketchup::ComponentInstance with ISG methods. Also initialize it,
		# so that it contains unique ID.
		# 
		# Accepts:
		# An Origin Marker ComponentInstance.
		# 
		# Notes:
		# 
		# 
		# Returns:
		# UID of new marker.
		########################################################################
		def Controller::initialize_marker(component_instance)
			unless component_instance.is_a? Sketchup::ComponentInstance
				UI.messagebox "Please select Origin Marker!", MB_OK
				return false
			end
			# if marker is not yet initialized
			unless component_instance.respond_to? :initialize_ISG_marker
				# extend it with ISG methods
				component_instance.send(:extend, IterativeSG::ComponentInstance)
				# and initialize it
				# TODO improve shape_ID mechanism.
				uid = generate_UID
				uid = component_instance.initialize_ISG_marker(uid)
			end
			uid = component_instance.UID unless uid

			@UIDs << uid
			@entites_by_UID[uid] = component_instance
			return uid
		end
		
		########################################################################	
		# PRIVATE METHODS BELOW!
		########################################################################	
		private
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
			all_groups = model.entities.to_a.select {|ent| ent.is_a? Sketchup::Group}
			all_groups.each do |group|
				attrdict = group.attribute_dictionary 'IterativeSG'
				next if attrdict == nil
				self.initialize_shape(group)
				initialized_shapes << group
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
			all_markers = all_components.select {|ent| ent.name == 'Origin'}
			all_markers.each do |obj|
				attrdict = obj.attribute_dictionary 'IterativeSG'
				next if attrdict == nil
				self.initialize_marker(obj)
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
				origin = @entites_by_UID[rules[0]]
				shape = @entites_by_UID[rules[1]]
				origin_new = @entites_by_UID[rules[2]]
				shape_new = Array.new
				rules[3].each do |ent|
					shape_new << @entites_by_UID[ent]
				end
				self.define_rule(rule_ID, origin, shape, origin_new, shape_new)
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
	end
end