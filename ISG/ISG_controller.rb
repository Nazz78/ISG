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
Sketchup.load(File.join(rubyScriptsPath, 'ISG_rules'))
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
			attr_reader :rules, :boundary_component, :dict_rules
			attr_reader :shapes, :UIDs, :entities_by_UID
			attr_accessor :temp_original_shape, :solution_shapes
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
			puts "initializing controller"
			if boundary_component.is_a? Sketchup::ComponentInstance and
				  boundary_component.definition.name.include? 'Boundary'
				# do nothing, all seems OK
				# if boundary component is not selected, try to guess it
			else
				components = Sketchup.active_model.entities.select { |ent|
					ent.is_a? Sketchup::ComponentInstance }
				boundaries = components.select { |ent|
					ent.definition.name.include? 'Boundary' }
				if boundaries.length != 1
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
		# Create design based on specified number of rule applications and rules
		# used.
		# 
		# Accepts:
		# num_of_applications - how many rules should be applied.
		# rules - tell ISG which rules should be used for design generation.
		# timeout - how long should the method run before forcing it to exit
		# (this way we can avoid generations that take too long to compute).
		# 
		# Notes:
		# 
		# Returns:
		# True once generation finishes.
		########################################################################		
		def Controller::generate_design(num_of_applications,
				rules = @rules.keys, timeout = 20)
			begin
				Sketchup.active_model.start_operation 'Generate design', false, false, false
			rescue
				Sketchup.active_model.start_operation 'Generate design'
			end
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
				rule = @rules[rule_id]
				
				case rule
				when IterativeSG::Replace
					# find appropriate candidates for specified rule
					original_shape_array = rule.collect_candidate_shapes
					# exit if there is no candidate for this rule
					# and also remove the rule from list of rules
					if original_shape_array == nil
						@temp_rules.delete rule_id
						next 
					end

					# calculate random reflection (1 or -1)
					mirror_x = rand(2)
					mirror_x = -1 if mirror_x == 0
					mirror_y = rand(2)
					mirror_y = -1 if mirror_y == 0

					# now apply the rule
					new_shapes = rule.send(:apply_rule, false,
						original_shape_array, mirror_x, mirror_y)
					# if new_shapes is false, it means that rule application
					# did not change the design (all new shapes were identical
					# to some already\ exising). We therefore reapply it with
					# inverse mirroring and set the mark_rule flag, so it will
					# remember that this rule should not be used on this shape
					# anymore. At the moment this is OK only for shape rules
					# with 1 mirror axis. TODO improve for shapes with no
					# mirror axis or with 2 mirror axis!
					if new_shapes == false and @temp_original_shape != nil
						new_shapes = rule.send(:apply_rule, true, 
							@temp_original_shape, (mirror_x * -1), (mirror_y * -1))
					end
					# exit if timeout is reached
					if (Time.now.to_f - timer) > timeout
						# round timeout to two decimals
						application_counter = 0
					end
					# do not count it if rule application didn't create any new shapes...
					next if new_shapes == false
				when IterativeSG::Merge
					shapes_to_merge = rule.collect_candidate_shapes
					
					# exit if timeout is reached
					if (Time.now.to_f - timer) > timeout
						# round timeout to two decimals
						application_counter = 0
					end
					
					# next if shapes_to_merge.empty?
					if shapes_to_merge == nil
						application_counter = 0
						next
					end

					new_shapes = rule.send(:apply_rule, shapes_to_merge)
				end
				
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
			Sketchup.active_model.commit_operation
			UI.messagebox "Shape generation done in #{completion_time} sec.#{additional_info}", MB_OK
			return true
		end
		# IterativeSG::Controller::initialize;   IterativeSG::Controller::generate_design(100)
		# IterativeSG::Controller::generate_design(100)
		
		########################################################################
		# Create new ISG rule object and add it to list of @rules.
		# 
		# Accepts:
		# spec_hash - hash of all information needed to create new object. See
		# each Rule object what they expect.
		# 
		# Notes: 
		# 
		# Returns:
		# New rule object.
		########################################################################	
		def Controller::define_rule(spec_hash)
			case spec_hash['type']
			when 'Replace'
				spec_hash['origin'] = @temp_origin if spec_hash['origin'] == nil
				spec_hash['shape'] = @temp_shape if spec_hash['shape'] == nil
				spec_hash['origin_new'] = @temp_origin_new if spec_hash['origin_new'] == nil
				spec_hash['shape_new'] = @temp_shape_new if spec_hash['shape_new'] == nil
				@rules[spec_hash['rule_ID']] = Replace.new(spec_hash)
				# puts shapes to rules layer
				spec_hash['origin'].layer = @rules_layer
				spec_hash['shape'].each {|comp| comp.layer = @rules_layer}
				spec_hash['origin_new'].layer = @rules_layer
				spec_hash['shape_new'].each {|comp| comp.layer = @rules_layer}
			when 'Merge'
				@rules[spec_hash['rule_ID']] = Merge.new(spec_hash)
			end
			return @rules[spec_hash['rule_ID']]
		end

		########################################################################
		# Helper method to quickly pick original shape. That is the shape which
		# will be replaced by new shape(s) once rule is applied. This method is
		# intended to be called once user has selected origin marker and shape.
		# 
		# Accepts:
		# selection - an array which contains Origin mark and Shape(s). If
		# arguments are not provided this method will pick them up based on
		# selection.
		# TODO In the future we might also accept Sketchup::Face as shape
		# argument and automatically convert it to ComponentInstance, but for
		# this is OK.
		# 
		# Notes:
		# 
		# Returns:
		# Marker and Shape, both set up for ISG work.
		########################################################################
		def Controller::pick_original_shape(selection = Sketchup.active_model.selection.to_a)
			marker = selection.select {|ent| ent.definition.name == 'ISG_OriginMarker'}
			shapes = selection.select {|ent| ent.definition.name.include? 'Shape'}
			
			# If all is OK, initialize marker
			if marker.length == 1
				initialize_marker(marker[0])
			else
				UI.messagebox "Please make sure you have selected correct marker (Component name = ISG_OriginMarker.", MB_OK
				return false
			end
			
			# If all is OK, initialize shape
			shapes.each { |shape| initialize_shape(shape)}
			
			@temp_origin = marker[0]
			@temp_shape = shapes
			# now return them
			return marker[0], shapes
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
		# and Shape(s). If arguments are not provided this method will pick
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
			number = @rules.length + 1
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
			# also cleanup dictionary
			unless @dict_rules == nil
				@dict_rules.keys.each {|k| @dict_rules.delete_key k}
			end
			
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
			
			rule = [["type", "Replace"], ["origin_uid", "ewi05qc058p7i"], ["shape_uid", ["2pvcdxzxh9jaz"]], ["origin_new_uid", "mlfhnbw339ng1"], ["shape_new_uid", ["1cf3rnstfmfpl", "h2nb5gwfwiihl"]], ["mirror_x", true], ["mirror_y", true]]
			dict_rules = model.attribute_dictionary 'ISG_rules', true
			dict_rules['Rule 1'] = rule
			
			# add layers
			self.initialize
			
			return nil
		end
		# ISGC::prepare_model

		########################################################################
		# Find rules which can be applied to selected shapes.
		# 
		# Accepts:
		# selection - is an array of shape objects.
		# 
		# Notes:
		# 
		# Returns:
		# Hash of rule - shape pairs to which rule can be applied or false
		# when no suitable rules can be found.
		########################################################################
		def Controller::find_candidate_rules(selection = Sketchup.active_model.selection.to_a)
			selection.delete @boundary_component
			# filter current selection to appropriate shapes
			rule_selection_hash = Hash.new
			@rules.each_pair do |rule_ID, rule_object|
				# next if selection doesn't match
				shapes = rule_object.check_rule(selection)
				rule_selection_hash[rule_ID] = shapes unless shapes == false
			end
			if rule_selection_hash.empty?
				return false
			else
				return rule_selection_hash
			end
		end
		
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
		# component_instance - shape ComponentInstance to be removed.
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
		# origin_marker - ISG_OriginMarker ComponentInstance.
		# 
		# Notes:
		# 
		# 
		# Returns:
		# UID of new marker.
		########################################################################
		def Controller::initialize_marker(origin_marker)
			unless origin_marker.is_a? Sketchup::ComponentInstance
				UI.messagebox "Please select ISG OriginMarker!", MB_OK
				return false
			end
			# if marker is not yet initialized
			unless origin_marker.respond_to? :initialize_ISG_marker
				# extend it with ISG methods
				origin_marker.send(:extend, IterativeSG::ComponentInstance)
				# and initialize it
				uid = generate_UID
				uid = origin_marker.initialize_ISG_marker(uid)
			end
			uid = origin_marker.UID unless uid

			@UIDs << uid
			@entities_by_UID[uid] = origin_marker
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
		def Controller::initialize_existing_shapes()
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
		def Controller::initialize_origin_markers()
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
		# List of all rules generated.
		########################################################################
		def Controller::initialize_existing_rules()
			@dict_rules.each_pair do |name, rules|
				rules_hash = dict_rules_to_hash(name)
				rules_hash['rule_ID'] = name
				# get objects from their UIDs
				rules_hash.each_pair do |key, value|
					if key.include? '_uid'
						if value.is_a? Array
							values = Array.new
							value.each { |uid| values << @entities_by_UID[uid] }
							# real usage does not have _uid postfix
							new_name = key.gsub('_uid','')
							rules_hash[new_name] = values
						else
							new_name = key.gsub('_uid','')
							rules_hash[new_name] = @entities_by_UID[value]
						end
					elsif key.include? 'shape_definitions_names'
						values = Array.new
						defs = Sketchup.active_model.definitions
						values = defs.select { |d| value.include?(d.name)}
						rules_hash['shape_definitions'] = values
					end
				end
				self.define_rule(rules_hash)
			end
			return @rules
		end
		#  IterativeSG::Controller::initialize; IterativeSG::Controller.rules

		########################################################################
		# Convert Rule values stored in Dictionary to Hash, so we can use it
		# when redefining rules. This is needed since SketchUp Dictionary can
		# not store hashes...
		# 
		# Accepts:
		# rule_ID of rule in question
		# 
		# Notes:
		# 
		# Returns:
		# Hash of all rule related values.
		########################################################################
		def Controller::dict_rules_to_hash(rule_ID)
			hash = Hash.new
			@dict_rules[rule_ID].each do |array_element|
				# get first element in array and remove it
				name = array_element.shift
				# get its values
				value = array_element[0]
				hash[name] = value
			end
			# puts hash.inspect
			return hash
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
		def Controller::generate_UID()
			uid = rand(2**256).to_s(36).ljust(8,'a')[0..12]
			# make sure no two UIDs are the same by using recursive function.
			if @UIDs.include? uid
				uid = generate_UID
			end
			# add it to list of all UIDs
			return uid
		end

		########################################################################
		# Generate new shape name.
		# 
		# Accepts:
		# Nothing, fully automatic.
		# 
		# Notes:
		# 
		# Returns:
		# String with new shape name (eg. Shape 5)
		########################################################################
		def Controller::generate_shape_ID()
			components = Sketchup.active_model.definitions.to_a
			shapes = components.select {|ent| ent.name.include? 'Shape'}
			# make sure no two UIDs are the same by using recursive function.
			return "Shape #{shapes.length + 1}"
		end
		
		########################################################################
		# Set unique ID to speficied object's dictionary.
		# 
		# Accepts:
		# entity - shape ComponentInstance to which UID is applied.
		# uid - uniqe identifier.
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
		def Controller::cleanup_rules()
			deleted_rules = Array.new
			@dict_rules.each_pair do |rule_name, double_arrays|
				delete_rule = false

				double_arrays.each do |spec|
					next unless spec[0].include? '_uid'
					if spec[1].is_a? Array
						# if entity doesn't exist, delete rule
						spec[1].each do |ent|
							if (@entities_by_UID[ent] == nil) or (@entities_by_UID[ent].deleted?)
								# puts 'deleted ent found'
								delete_rule = true
							end
						end
					else
						if (@entities_by_UID[spec[1]] == nil) or (@entities_by_UID[spec[1]].deleted?)
							# puts 'deleted ent found'
							delete_rule = true
						end
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
				puts 'deleted rules!'
				return deleted_rules
			end
		end

	end
end

# Once all scripts are loaded, we can add controller and UI
IterativeSG::UI_Menu::create_menu