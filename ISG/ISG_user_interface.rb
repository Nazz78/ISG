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
		def UI_Menu::add_menu
			# remember ui entries
			@ui_iterations = 120
			@ui_seconds = 20
			unless @ISG_menu
				tool_menu = UI.menu "Plugins"
				isg_tool_menu = tool_menu.add_submenu("ISG")

				# Open template with all layers, markers, boundaries, ... defined.
				isg_tool_menu.add_item('Open Template') do
					ISGC::prepare_model
				end
			
				# add separator ================================================
				isg_tool_menu.add_separator
			
				isg_tool_menu.add_item('Initialize Controller') do
					Controller::initialize(Sketchup.active_model.selection[0])
				end
				isg_tool_menu.add_item('Generate Design') do
					# initialize controller if it is not initialized already
					self.initialize_controller
					generate_sg_design
				end
				isg_tool_menu.add_item('Apply Rule') do
					# initialize controller if it is not initialized already
					self.initialize_controller
					apply_rule
				end
				isg_tool_menu.add_item('Remove Rule') do
					# initialize controller if it is not initialized already
					self.initialize_controller
					entities = check_for_remove_rule()
					unless entities.empty?
						remove_rule(entities)
					end
				end
				# add separator ================================================
				isg_tool_menu.add_separator
			
				# add rule definition related methods
				isg_tool_menu.add_item('Pick Original Shape') do
					self.initialize_controller
					puts Sketchup.active_model.selection.to_a
					Controller::pick_original_shape
				end
				isg_tool_menu.add_item('Pick New Shape') do
					self.initialize_controller
					Controller::pick_new_shape
				end
				isg_tool_menu.add_item('Define Replace Rule') do
					# initialize controller if it is not initialized already
					self.initialize_controller
					define_replace_rule()
				end
				# add separator ================================================
				isg_tool_menu.add_separator
				
				isg_tool_menu.add_item('Define Merge Rule') do
					# initialize controller if it is not initialized already
					self.initialize_controller
					define_merge_rule()
				end
				
				isg_tool_menu.add_item('Define Stretch Rule') do
					# initialize controller if it is not initialized already
					self.initialize_controller
					define_stretch_rule()
				end
				
				# add separator ================================================
				isg_tool_menu.add_separator
				isg_tool_menu.add_item('Show ISG Window') do
					UI_Window::initialize
				end
				@ISG_menu = tool_menu
			end
		end

		########################################################################
		# Add context menu which shows only methods that can be applied to
		# current selection. This is only example, which should be developed
		# further
		# 
		# Accepts:
		# Nothing
		# 
		# Notes:
		# Each Component has a ID which is persistent when it is copied.
		# 
		# Returns:
		# Nothing, it establishes contex menu handling.
		########################################################################
		def UI_Menu::add_context
			unless @ISG_context
				context_menu = UI.add_context_menu_handler do |menu|
					selection = Sketchup.active_model.selection.to_a
					menu.add_separator
					isg_context_menu = menu.add_submenu('ISG')
					
					# add apply rule to context if some rules can be applied
					candidates_hash = check_for_apply_rule
					unless candidates_hash == false
						isg_context_menu.add_item('Apply Rule') do
							apply_rule
						end
					end
					
					# add remove rule to context if at least on rule can be removed
					entities = check_for_remove_rule
					unless entities.empty?
						isg_context_menu.add_item('Remove Rule') do
							# initialize controller if it is not initialized already
							remove_rule(entities)
						end
					end

				end
				@ISG_menu = context_menu
			end
		end
		########################################################################	
		# PRIVATE METHODS BELOW!
		########################################################################	
		private
		
		########################################################################
		# Check if some rules can be applied to selected shapes. If so, return
		# them, otherwise return false.
		# 
		# 
		# Accepts:
		# selection - optional. By default method itself checks current selection.
		# 
		# Notes:
		# 
		# Returns:
		# Hash of rule-entities pairs to which rules can be applied.
		########################################################################
		def UI_Menu::check_for_apply_rule(selection = Sketchup.active_model.selection.to_a)
			# Make sure controller is properly initialized
			initialize_controller
			if selection.empty?
				return false
			else
				candidates_hash = Controller::find_candidate_rules(selection)
				if candidates_hash == false
					return false
				else
					return candidates_hash
				end
			end
		end
		
		########################################################################
		# Check if some of the selected entities can be reverted to previous
		# state, that is to shapes which generated it by rule application.
		# 
		# 
		# Accepts:
		# selection - optional. By default method itself checks current selection.
		# 
		# Notes:
		# 
		# Returns:
		# Array of entities which can be replaced by original shapes, that is
		# ones from which this shape was generated.
		########################################################################
		def UI_Menu::check_for_remove_rule(selection = Sketchup.active_model.selection.to_a)
			# Make sure controller is properly initialized
			initialize_controller
			# filter to only shapes which have stored erased entities
			filter_1 = selection.select {|ent| ent.respond_to? :receive_erased_entites}
			filter_2 = filter_1.select {|ent| ent.receive_erased_entites != nil }
			return filter_2
		end
		
		########################################################################
		# Open UI with options to generate design. Options include number of
		# rule applications, rules which will be applied and timeout to
		# finish some methods if they would take too long to compute...
		# 
		# Accepts:
		# Nothing.
		# 
		# Notes:
		# 
		# Returns:
		# It returns false when something is wrong, otherwise it initializes
		# generation of design.
		########################################################################
		def UI_Menu::generate_sg_design
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
		# Open UI with options to define Replace rule object. To use this rule
		# just pick some components (in 3D window) between which this rule can
		# be applied and select it from UI.
		# 
		# Accepts:
		# Nothing, rule picks up selected objets upon definition.
		# 
		# Notes:
		# 
		# Returns:
		# It returns new rule object if created or false otherwise.
		########################################################################
		def UI_Menu::define_replace_rule
			prompts = ["Define New Rule Name: ",
				"Mirror in X direction: ", "Mirror in Y direction"]
			defaults = [Controller::generate_rule_name,	false, false]
			input = UI.inputbox prompts, defaults, "Declare New ISG Replace Rule"

			if IterativeSG::Controller.rules.keys.include? input[0]
				overload = UI.messagebox "Rule with this name already exists. Do you want to replace it?", MB_YESNO
			end
				
			if overload == 7 # 6=YES, 7=NO
				puts "Rule not being created"
				return false
			else
				name = input[0]
				mir_x = input[1]
				mir_y = input[2]
				# make sure mirroring info is true boolean, not string
				mirror_x = (mir_x == 'true' or mir_x == 'True' or mir_x == '1')
				mirror_y = (mir_y == 'true' or mir_y == 'True' or mir_y == '1')
				spec_hash = Hash.new
				spec_hash['type'] = 'Replace'
				spec_hash['rule_ID'] = name
				spec_hash['mirror_x'] = mirror_x
				spec_hash['mirror_y'] = mirror_y

				return Controller::define_rule(spec_hash)
			end
		end

		########################################################################
		# Open UI with options to define Merge rule object.
		# 
		# Accepts:
		# Nothing.
		# 
		# Notes:
		# 
		# Returns:
		# It returns new rule object if created or false otherwise.
		########################################################################
		def UI_Menu::define_merge_rule
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
					"Merge in Y direction: ", "Num. of shapes to merge: "]
				defaults = [Controller::generate_rule_name,	true, false, 2]
				input = UI.inputbox prompts, defaults, "Declare New ISG Merge Rule"

				if IterativeSG::Controller.rules.keys.include? input[0]
					overload = UI.messagebox "Rule with this name already exists. Do you want to replace it?", MB_YESNO
				end
				
				if overload == 7 # 6=YES, 7=NO
					puts "Rule not being created"
					return false
				else
					merge_in_x = (input[1] == 'true' or input[1] == 'True' or input[1] == '1')
					merge_in_y = (input[2] == 'true' or input[2] == 'True' or input[2] == '1')

					spec_hash = Hash.new
					spec_hash['rule_ID'] = input[0]
					spec_hash['merge_in_x'] = merge_in_x
					spec_hash['merge_in_y'] = merge_in_y
					spec_hash['num_of_objects'] = input[3]
					spec_hash['shape_definitions'] = shape_definitions
					spec_hash['type'] = 'Merge'

					return Controller::define_rule(spec_hash)
				end
			end
		end
		
		def UI_Menu::define_stretch_rule
			# first check if shape definitions are selected
			shape_definitions = Array.new
			selection = Sketchup.active_model.selection.to_a
			shape_instances = selection.select {|ent| ent.definition.name.include? 'Shape'}
			shape_instances.uniq!
			shape_instances.each { |ent| shape_definitions << ent.definition }
			# set it to nil if no shapes are selected. If so, the rule will
			# be applied to any shape
			shape_definitions == nil if shape_definitions.empty?
			
			prompts = ["Define New Rule Name: ", "Stretch in X direction: ",
				"Stretch in Y direction: ", "Min stretch: ", "Max stretch",
				"Keep connecting shapes together: "]
			
			defaults = [Controller::generate_rule_name,	false, true, 0.5, 1.5, true]
			input = UI.inputbox prompts, defaults, "Declare New ISG Stretch Rule"

				if IterativeSG::Controller.rules.keys.include? input[0]
					overload = UI.messagebox "Rule with this name already exists. Do you want to replace it?", MB_YESNO
				end
				
				if overload == 7 # 6=YES, 7=NO
					puts "Rule not being created"
					return false
				else
					stretch_in_x = (input[1] == 'true' or input[1] == 'True' or input[1] == '1')
					stretch_in_y = (input[2] == 'true' or input[2] == 'True' or input[2] == '1')

					spec_hash = Hash.new
					spec_hash['type'] = 'Stretch'
					spec_hash['rule_ID'] = input[0]
					spec_hash['stretch_in_x'] = stretch_in_x
					spec_hash['stretch_in_y'] = stretch_in_y
					spec_hash['min_stretch'] = input[3]
					spec_hash['max_stretch'] = input[4]
					spec_hash['constrain_connecting'] = input[5]
					spec_hash['shape_definitions'] = shape_definitions

					return Controller::define_rule(spec_hash)
				end
		end
		
		########################################################################
		# Open UI window for applying rule to selected shapes. If more rules
		# can be applied to specific selection, first window asks which rule to
		# apply. User selects it by typing some value into corresponding input
		# text field. If there are many entries, only the first rule in list will 
		# be applied. Once rule is selected, user can specify in which direction
		# to apply it when mirroring option exists in the rule.
		# 
		# Accepts:
		# Nothing.
		# 
		# Notes:
		# Rule selection UI should be improved with dropdown.
		# 
		# Returns:
		# Applies new rule to selection or false when rule can not be applied.
		########################################################################
		def UI_Menu::apply_rule(selection = Sketchup.active_model.selection.to_a)
			if selection.empty?
				UI.messagebox "Please select some shapes to find appropriate rules.", MB_OK
			return false
		end
		candidates_hash = Controller::find_candidate_rules(selection)
		if candidates_hash == false
			UI.messagebox "No rule can be applied to selected shapes.
Also make sure selected shapes are inside boundary.", MB_OK
			return false
		end
			
		# now define rule to be applied.
		# ask user only if more than one rule can be applied...
		rule = nil
		if candidates_hash.length > 1
			candidates_array = candidates_hash.to_a
			candidates_array.sort!

			prompts = Array.new
			# we know that the first item in array is rule_ID
			candidates_hash.each do |candidate|
				# prepare inputbox string
				rule_type = Controller.rules[candidate[0]].isg_type
				prompts << candidate[0]
			end
			# leave defaults empty
			defaults = Array.new
			input = UI.inputbox prompts, defaults, "Apply ISG Rule"
			return false if input == false

			# Now find out which rule was selected, if more rules were defined
			# select the first one
			selected_rule_index = Array.new
			input.each do |indx|
				selected_rule_index << input.index(indx) if indx != ''
			end
			# make sure there are no empty values in array...
			selected_rule_index.compact!

			if selected_rule_index.length > 1
				UI.messagebox "Please select just one rule.", MB_OK
				return false
			elsif selected_rule_index.empty?
				UI.messagebox "Please select rule by inserting some value (eg. 1) in appropriate text field.", MB_OK
				return false
			end

			rule = Controller::rules[prompts[selected_rule_index[0]]]
		else
			rule = Controller::rules[candidates_hash.keys.first]
		end
		shapes = candidates_hash[rule.rule_ID]
			
		# now apply the rule as needed
		resulting_shapes = Array.new
		Sketchup.active_model.start_operation "Apply rule", false, true, false
		case rule
		when IterativeSG::Replace
			prompts = Array.new
			prompts << "Direction in X: " if rule.mirror_x
			prompts << "Direction in Y: " if rule.mirror_y
				
			mir_x = 1
			mir_y = 1
				
			unless prompts.empty?
				# improve defaults declaration
				defaults = [mir_x, mir_y]
				input = UI.inputbox prompts, defaults, "Spec. #{rule.rule_ID} direction"
				# since we are working with only two options, we can simplify
				# a bit - x will always be first input, y last...
				mir_x = input.first if rule.mirror_x
				mir_y = input.last if rule.mirror_y
			end			
				
			resulting_shapes = rule.apply_rule(false, shapes, mir_x, mir_y)
			if resulting_shapes == false
				# inverse directions
				mir_x *= -1
				mir_y *= -1
				rule.apply_rule(true, shapes, mir_x, mir_y)
				UI.messagebox "Rule was applied in oposite direction since specified was already taken...", MB_OK
			end
		when IterativeSG::Merge
			resulting_shapes = rule.apply_rule(shapes)
		end

		Sketchup.active_model.commit_operation
		#rule.send(:apply_rule, false, original_shape_array, mirror_x, mirror_y)
		return resulting_shapes
	end
	########################################################################
	# Replace specified shapes with the ones from which it was generated.
	# Currently only works with Merge family of rules.
	# 
	# Accepts:
	# entities which will be reverted.
	# 
	# Notes:
	# 
	# Returns:
	# Nothing, it just replaces shape with ones which generated it...
	########################################################################
	def UI_Menu::remove_rule(entities)
		# only consider entities which respond to receive_erase_entitie method.
		entities.each do |ent|
			rule_ID = ent.applied_by_rule
			Controller.rules[rule_ID].remove_rule(ent)
		end
	end
	########################################################################
	# Check if Controller is properly initialized, if not, itnitialize it.
	# 
	# Accepts:
	# Nothing.
	# 
	# Notes:
	# 
	# Returns:
	# True if all is OK, false otherwise.
	########################################################################
	def UI_Menu::initialize_controller
		# store current selection and deselect it
		selection = Sketchup.active_model.selection
		current_selection = selection.to_a			
		selection.clear
			
		Controller.initialize if Controller.rules == nil
		Controller.shapes.each do |shp|
			unless shp.valid?
				Controller.initialize
				break
			end
		end
		# now add back selected object
		selection.clear
		selection.add current_selection
	end
end
	
############################################################################
# User interface window for Iterative Shape Grammars.
############################################################################
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