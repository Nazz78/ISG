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
	def IterativeSG::create_menu
		unless @ISG_menu
			tool_menu = UI.menu "Plugins"
			isg_tool_menu = tool_menu.add_submenu("ISG")
			isg_tool_menu.add_item('Initialize ISG Controller') do
				Controller::initialize(Sketchup.active_model.selection[0])
			end
			isg_tool_menu.add_item('Generate SG Design') do
				prompts = ["Number of rule applicaitons:"]
				defaults = [100]
				input = UI.inputbox prompts, defaults, "Generate Shape Grammar Design"
				Controller::generate_design(input[0])
			end
			# add separator
			isg_tool_menu.add_separator
			# add rule definition related methods
			isg_tool_menu.add_item('Pick Original Shape') do
				Controller::pick_original_shape
			end
			isg_tool_menu.add_item('Pick New Shape') do
				Controller::pick_new_shape
			end
			isg_tool_menu.add_item('Declare New Rule') do
				prompts = ["Define Rule Name"]
				defaults = ['rule_001']
				#TODO rules should be checked if they alreay exist!!!
				input = UI.inputbox prompts, defaults, "Define ISG Rule"
				if IterativeSG::Controller.rules.keys.include? input[0]
					overload = UI.messagebox "Rule with this name already exists. Do you want to replace it?", MB_YESNO
					return false if overload == 7 # 6=YES, 7=NO
				end
				Controller::define_rule(input[0])
			end
			@ISG_menu = tool_menu
		end
	end
end