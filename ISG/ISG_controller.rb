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
			# entities by UID enable us to quickly call entity by its UID
			@entites_by_UID = Hash.new
			# now we can initialize all existing shapes and markers
			initialize_existing_shapes	
			initialize_origin_markers
			
			# Setup boundary and Geometry module to work with it
			@boundary_component = boundary_component
			Geometry.initialize(boundary_component)
			
			# hash of rules
			@rules = Hash.new
		
			return true
		end
		# IterativeSG::Controller::initialize
		
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
			origin_uid = initialize_marker(origin)
			
			# setup base shape. If it is alread setup, it will just return its UID
			shape_uid = initialize_shape(shape)
			# shape.set_attribute rule_ID, 'shape', shape_uid
			
			# setup origin of shape rule application
			origin_new_uid = initialize_marker(origin_new)
				
			# create shape rule application
			shape_new_uid = Array.new
			shape_new.each do |shape|
				shape_new_uid << initialize_shape(shape)
			end
			
			# add all objects to @rules_layer
			
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
			# if group is already initialized
			if group.respond_to? :initialize_ISG_shape
				return group.UID
			end
			# extend SU Group with ISG methods
			group.send(:extend, IterativeSG::Group)

			# initialize the shape
			# TODO improve shape_ID mechanism.
			uid = generate_UID
			shp_id, shp_uid = group.initialize_ISG_shape(@shape_IDs.last + 1, uid)
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
			# if marker is already initialized
			if component_instance.respond_to? :initialize_ISG_marker
				return component_instance.UID
			end
			
			# extend SU Group with ISG methods
			component_instance.send(:extend, IterativeSG::ComponentInstance)

			# initialize the shape
			# TODO improve shape_ID mechanism.
			uid = generate_UID
			uid = component_instance.initialize_ISG_marker(uid)
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