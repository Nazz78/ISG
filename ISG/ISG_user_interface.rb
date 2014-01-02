################################################################################
# Filename: ISG_controller.rb
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
	# Create Plugins menu entry for Iterative Shape Grammars methods.
	############################################################################
	def IterativeSG::create_menu
		unless @ISG_menu
			tool_menu = UI.menu "Plugins"
			isg_tool_menu = tool_menu.add_submenu("ISG")
			isg_tool_menu.add_item('Show ISG Window') do
				UI_Window::initialize
			end
			
			# add separator ====================================================
			isg_tool_menu.add_separator
			
			isg_tool_menu.add_item('Initialize ISG Controller') do
				Controller::initialize(Sketchup.active_model.selection[0])
			end
			isg_tool_menu.add_item('Generate SG Design') do
				# Make sure Controller is properly initialized
				Controller::initialize(Sketchup.active_model.selection[0])
				prompts = ["Number of rule applicaitons:"]
				defaults = [100]
				input = UI.inputbox prompts, defaults, "Generate Shape Grammar Design"
				Controller::generate_design(input[0])
			end
			
			# add separator ====================================================
			isg_tool_menu.add_separator
			
			# add rule definition related methods
			isg_tool_menu.add_item('Pick Original Shape') do
				Controller::pick_original_shape
			end
			isg_tool_menu.add_item('Pick New Shape') do
				Controller::pick_new_shape
			end
			isg_tool_menu.add_item('Declare New ISG Rule') do
				prompts = ["Define New Rule Name: "]
				defaults = [Controller::generate_rule_name]
				input = UI.inputbox prompts, defaults, "Declare New ISG Rule"
				if IterativeSG::Controller.rules.keys.include? input[0]
					overload = UI.messagebox "Rule with this name already exists. Do you want to replace it?", MB_YESNO
				end
				if overload == 7 # 6=YES, 7=NO
					puts "Rule not being created"
				else
					Controller::define_rule(input[0])
				end
			end
			@ISG_menu = tool_menu
		end
	end
	################################################################################
	# User interface window for Iterative Shape Grammars.
	################################################################################
	class UI_Window
		# make it singleton, so it is not repeated.
		private_class_method :new
		@@window = nil
		@@skui_window = nil
		
		########################################################################
		# Initialize ISG UI window.
		# 
		# Accepts:
		# Nothing.
		# 
		# Notes:
		# 
		# Returns:
		# UI_Window object.
		########################################################################
		def UI_Window::initialize
			@@window = new unless @@window
			
			show_ui
			return @@window
		end
		########################################################################	
		# PRIVATE METHODS BELOW!
		########################################################################	
		private
		
		########################################################################
		# Set up and show ISG UI window.
		# 
		# Accepts:
		# Nothing.
		# 
		# Notes:
		# 
		# Returns:
		# UI_Window object.
		########################################################################
		def UI_Window::show_ui
			options = {
				:title           => 'Iterative Shape Grammars',
				:width           => 300,
				:height          => 500,
				:resizable        => true,
				:theme            => SKUI::Window::THEME_GRAPHITE
			  }
			
			@@skui_window = SKUI::Window.new (options) unless @@skui_window

			b = SKUI::Button.new( 'Hello' ) { puts 'World! :)' }
			b.position( 10, 5 )
			@@skui_window.add_control( b )
			
			
			#  now show it
			@@skui_window.show
			return @@window
		end
		# IterativeSG::UI_Window::show_ui
	end
end