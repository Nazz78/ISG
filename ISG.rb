################################################################################
# Filename: ISG.rb
# Created as a part of "Iterative Shape Grammars" experiment to assess if the
# proposed method can improve traditional SG methods, which tipically defines
# all rules prior to generating design.
# Author: Jernej Vidmar
# Version: 0.1
# Date: December, 2013
################################################################################
require 'sketchup'
require 'extensions'

su_sg_extension = SketchupExtension.new "Controlled Shape Grammars",
  File.join('ISG', 'ISG_controller.rb')

su_sg_extension.creator = 'Jernej Vidmar'
su_sg_extension.copyright = 'Jernej Vidmar, December 2013'
su_sg_extension.version = '0.1'

su_sg_description = 'Iterative Shape Grammars extension is a plugin to test new
 approach to Shape Grammars inside SketchUp.'
su_sg_extension.description = su_sg_description

Sketchup.register_extension su_sg_extension, true