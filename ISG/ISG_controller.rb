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
			attr_reader :shapes, :shape_IDs, :shape_UIDs
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
			@dict = model.attribute_dictionary 'IterativeSG', true
			# populate shape_IDs
			@shape_IDs = [1]
			# create shape_IDs
			@shape_UIDs = Array.new
			# Initialize existing shapes
			@shapes = Array.new
			initialize_existing_shapes
		
			# Setup boundary and Geometry module to work with it
			@boundary_component = boundary_component
			Geometry.initialize(boundary_component)
			
			# hash of rules
			@rules = Hash.new
		
			return true
		end
		# IterativeSG::Controller::initialize
		
		
		def Controller::create_rule(rule_ID, orig, shape, orig_new, shape_new)
			# get origin of base shape
			pos_orig = orig.bounds.center
			# get base shape
			pos_shape = shape.bounds.min
			# get origin of shape rule application
			pos_orig_new = orig_new.bounds.center
			# get shape rule application
			new_shape_group = Sketchup.active_model.entities.add_group shape_new
			new_shape_group.name = rule_ID
			pos_shape_new = new_shape_group.bounds.min
			
			# add all to @rules_layer
			
			
			@rules[rule_ID] = [orig, shape, orig_new, shape_new]
			@dict.set_attribute 'IterativeSG', rule_ID, @rules[rule_ID]
			return true
		end
		# IterativeSG::Controller::create_rule(rule_1, orig, shape, orig_new, shape_new)

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
		# True when object creation is sucessful.
		########################################################################
		def Controller::initialize_shape(group)
			unless group.is_a? Sketchup::Group
				UI.messagebox "Please select shape Group!", MB_OK
				return false
			end
			# extend SU Group with ISG methods
			group.send(:extend, IterativeSG::Group)

			# initialize the shape
			# TODO improve shape_ID mechanism.
			uid = generate_UID
			shp_id, shp_uid = group.initialize_ISG_shape(@shape_IDs.last + 1, uid)
			@shape_IDs << shp_id
			@shape_IDs.sort!.uniq!
			@shape_UIDs << shp_uid
			@dict.set_attribute 'IterativeSG', 'shape_IDs', @shape_IDs
			puts @shape_IDs.inspect
			
			# and add it to list of shapes
			@shapes << group
			return true
		end
		# IterativeSG::Controller::initialize_shape(Sketchup.active_model.selection[0])

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
			if @shape_UIDs.include? uid
				uid = generate_UID
			end
			return uid
		end
	end
end