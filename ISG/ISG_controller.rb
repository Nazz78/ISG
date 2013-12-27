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
		end
		
		########################################################################
		# Initialize ShapeGrammar Controller and set up all needed variables to
		# work with it.
		# Prior to initializing Controller user has to select boundary object
		# which is represented by a SketchUp Component entity. For now this
		# works only in horizontal plane (2D).
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
			# reset initial shape
			@initial_shape = nil
			
			# Setup boundary
			@boundary_component = boundary_component
			Geometry.initialize(boundary_component)
			return true
		end
		# ShapeGrammars::Controller::initialize
	end
end
