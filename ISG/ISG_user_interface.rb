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
			
			@ISG_menu = tool_menu
		end
	end
end