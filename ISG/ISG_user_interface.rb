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
	module UI_Menu
		########################################################################
		# Create Plugins menu entry for Iterative Shape Grammars methods.
		########################################################################
		########################################################################
		# Create Plugins Menu entry for ISG.
		# 
		# Accepts:
		# Nothing.
		# 
		# Notes:
		# 
		# Returns:
		# Menu object.
		########################################################################
		def UI_Menu::create_menu
			# remember ui entries
			@ui_iterations = 120
			@ui_seconds = 20
			unless @ISG_menu
				tool_menu = UI.menu "Plugins"
				isg_tool_menu = tool_menu.add_submenu("ISG")

				# Open template with all layers, markers, boundaries, ... defined.
				isg_tool_menu.add_item('Open ISG template') do
					ISGC::prepare_model
				end
			
				# add separator ====================================================
				isg_tool_menu.add_separator
			
				isg_tool_menu.add_item('Initialize ISG Controller') do
					Controller::initialize(Sketchup.active_model.selection[0])
				end
				isg_tool_menu.add_item('Generate SG Design') do
					# initialize controller if it is not initialized already
					Controller::initialize unless is_controller_initialized?
					self.generate_sg_design
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
				isg_tool_menu.add_item('Define Replace Rule') do
					# initialize controller if it is not initialized already
					Controller::initialize unless is_controller_initialized?
					prompts = ["Define New Rule Name: ",
						"Mirror in X direction: ", "Mirror in Y direction"]
					defaults = [Controller::generate_rule_name,	false, false]
					input = UI.inputbox prompts, defaults, "Declare New ISG Rule"
					
					if IterativeSG::Controller.rules.keys.include? input[0]
						overload = UI.messagebox "Rule with this name already exists. Do you want to replace it?", MB_YESNO
					end
					
					name = input[0]
					mir_x = input[1]
					mir_y = input[2]
					
					if overload == 7 # 6=YES, 7=NO
						puts "Rule not being created"
					else
						# make sure mirroring info is true boolean, not string
						mirror_x = (mir_x == 'true' or mir_x == 'True' or mir_x == '1')
						mirror_y = (mir_y == 'true' or mir_y == 'True' or mir_y == '1')
						spec_hash = Hash.new
						spec_hash['type'] = 'Replace'
						spec_hash['rule_ID'] = name
						spec_hash['mirror_x'] = mirror_x
						spec_hash['mirror_y'] = mirror_y

						Controller::define_rule(spec_hash)
					end
				end
				# add separator ====================================================
				isg_tool_menu.add_separator
				
				isg_tool_menu.add_item('Define Merge Rule') do
					# initialize controller if it is not initialized already
					Controller::initialize if Controller.rules == nil
					# first check if shape definitions are selected
					shape_definitions = Array.new
					selection = Sketchup.active_model.selection.to_a
					shape_instances = selection.select {|ent| ent.definition.name.include? 'Shape'}
					shape_instances.uniq!
					shape_instances.each { |ent| shape_definitions << ent.definition }
					if shape_definitions.empty?
						UI.messagebox "Please select some shapes to which this rule can be applied.", MB_OK
					else

						prompts = ["Define New Rule Name: ", "Merge in X direction: ",
							 "Merge in Y direction: ", "Shapes to merge: "]
						defaults = [Controller::generate_rule_name,	true, false, 2]
						input = UI.inputbox prompts, defaults, "Declare New ISG Rule"

						if IterativeSG::Controller.rules.keys.include? input[0]
							overload = UI.messagebox "Rule with this name already exists. Do you want to replace it?", MB_YESNO
						end

						merge_in_x = (input[1] == 'true' or input[1] == 'True' or input[1] == '1')
						merge_in_y = (input[2] == 'true' or input[2] == 'True' or input[2] == '1')
						
						spec_hash = Hash.new
						spec_hash['rule_ID'] = input[0]
						spec_hash['merge_in_x'] = merge_in_x
						spec_hash['merge_in_y'] = merge_in_y
						spec_hash['num_of_objects'] = input[3]
						spec_hash['shape_definitions'] = shape_definitions
						spec_hash['type'] = 'Merge'

						Controller::define_rule(spec_hash)
					end
				end
				
				# add separator ====================================================
				isg_tool_menu.add_separator
				isg_tool_menu.add_item('Show ISG Window') do
					UI_Window::initialize
				end
				@ISG_menu = tool_menu
			end
			
			####################################################################
			# Open UI with options to generate design.
			# 
			# Accepts:
			# Nothing.
			# 
			# Notes:
			# 
			# Returns:
			# It returns false when something is wrong, otherwise it initializes
			# generation of design.
			####################################################################
			def UI_Menu::generate_sg_design
				Controller::initialize unless is_controller_initialized?
				prompts = ["Number of rule applicaitons: ", "Rules applied: ","Set timeout timer (in seconds): "]
				controller_rules = Controller.rules.keys
				if controller_rules.empty?
					UI.messagebox "No rules exist in current model. Please define them prior to running ISG.", MB_OK 
					return false
				end
				rules = String.new
				controller_rules.each { |name| rules += "#{name}, "}
				# remove last comma
				rules.chop!.chop!
				# set default text values
				defaults = [@ui_iterations, rules, @ui_seconds]

				input = UI.inputbox prompts, defaults, "Generate Shape Grammar Design"
				# exit if generation was canceled
				return false if input == false
				@ui_iterations = input[0]
				# for rules_used see below
				@ui_seconds = input[2]

				# if no rules are specified, use all rules...
				rules_used = Array.new
				if input[1] == ''
					rules_used = controller_rules
				else
					rules_used = input[1].split ", "
					# also make sure those rules really exist!
					rules_used.each do |rule_name|
						# remove whitespace
						rule_name.lstrip!
						rules_used.delete rule_name unless controller_rules.include? rule_name
					end
				end
				if rules_used.empty?
					UI.messagebox "Please specify correct rule names", MB_OK 
					return false
				end

				Controller::generate_design(@ui_iterations, rules_used, @ui_seconds)
			end

			########################################################################	
			# PRIVATE METHODS BELOW!
			########################################################################	
			private
			
			########################################################################
			# Check if Controller is properly initialized
			# 
			# Accepts:
			# Nothing.
			# 
			# Notes:
			# 
			# Returns:
			# True if all is OK, false otherwise.
			########################################################################
			def UI_Menu::is_controller_initialized?
				return false if Controller.rules == nil
				Controller.shapes.each do |shp|
					return false unless shp.valid?
				end
				return true
			end
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
			
			@@skui_window = SKUI::Window.new(options) unless @@skui_window

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