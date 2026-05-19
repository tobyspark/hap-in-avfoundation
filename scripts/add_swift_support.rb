#!/usr/bin/env ruby
# Adds Swift support + new Swift sources to HapInAVFoundation.xcodeproj.
# Idempotent: re-running is a no-op once the files are present.

require 'xcodeproj'

PROJ_PATH = File.expand_path('../HapInAVFoundation.xcodeproj', __dir__)
TARGET_NAME = 'HapInAVFoundation'                     # framework target
TOP_GROUP_NAME = 'HapInAVFoundation framework'        # top-level project group
SUB_GROUP_NAME = 'Decode (playback)'                  # where the new files live logically
NEW_FILES = %w[
  HapCodec.swift
  HapManagedTexture.swift
  AVAssetHapAsync.swift
  AVPlayerItemHapMetalOutput.swift
]

REQUIRED_SETTINGS = {
  'SWIFT_VERSION'                    => '5.0',
  'MACOSX_DEPLOYMENT_TARGET'         => '13.0',
  'BUILD_LIBRARY_FOR_DISTRIBUTION'   => 'YES',
  'SWIFT_INSTALL_OBJC_HEADER'        => 'YES',
  'DEFINES_MODULE'                   => 'YES',
  'CLANG_ENABLE_MODULES'             => 'YES',
}

proj = Xcodeproj::Project.open(PROJ_PATH)

target = proj.targets.find { |t| t.name == TARGET_NAME && t.product_type == 'com.apple.product-type.framework' }
abort "target #{TARGET_NAME} (framework) not found" unless target

top_group = proj.main_group.find_subpath(TOP_GROUP_NAME, false)
abort "group #{TOP_GROUP_NAME} not found" unless top_group
group = top_group.children.find { |c|
  c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.display_name == SUB_GROUP_NAME
}
abort "subgroup #{SUB_GROUP_NAME} not found" unless group

existing_paths = group.files.map(&:path).to_set
sources_phase = target.source_build_phase
existing_in_phase = sources_phase.files.map { |bf| bf.file_ref.path }.compact.to_set

added = []
NEW_FILES.each do |name|
  if existing_paths.include?(name) || existing_in_phase.include?(name)
    next
  end
  fref = group.new_reference(name)
  fref.last_known_file_type = 'sourcecode.swift'
  sources_phase.add_file_reference(fref)
  added << name
end

# Apply build settings to the framework target's Debug + Release configs.
target.build_configurations.each do |config|
  REQUIRED_SETTINGS.each do |key, value|
    if config.build_settings[key] != value
      config.build_settings[key] = value
    end
  end
end

proj.save

puts "added files: #{added.inspect}" unless added.empty?
puts "settings applied to configs: #{target.build_configurations.map(&:name).inspect}"
