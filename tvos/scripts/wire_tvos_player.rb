#!/usr/bin/env ruby
require 'xcodeproj'

project_dir = File.expand_path(File.join(__dir__, '..'))
project_path = File.join(project_dir, 'Runner.xcodeproj')
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'Runner' } or abort('Runner target not found')

playback_group = project.main_group.find_subpath('Runner/Playback', true)
playback_group.set_source_tree('SOURCE_ROOT')
playback_group.set_path('Runner/Playback')

source_exts = %w[.swift .c .m .mm]
abs_files = Dir.glob(File.join(project_dir, 'Runner/Playback/*'))
  .select { |f| source_exts.include?(File.extname(f)) }.sort
basenames = abs_files.map { |f| File.basename(f) }

project.files.select { |f| basenames.include?(File.basename(f.path.to_s)) }.each do |f|
  f.referrers.grep(Xcodeproj::Project::Object::PBXBuildFile).each(&:remove_from_project)
  f.remove_from_project
end

abs_files.each do |abs|
  ref = playback_group.new_reference(abs)
  target.add_file_references([ref]) unless File.extname(abs) == '.h'
  puts "added source: #{File.basename(abs)}"
end

mpvkit_url = 'https://github.com/mpvkit/MPVKit'
pkg = project.root_object.package_references.find do |p|
  p.respond_to?(:repositoryURL) && p.repositoryURL == mpvkit_url
end
unless pkg
  pkg = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  pkg.repositoryURL = mpvkit_url
  pkg.requirement = { 'kind' => 'upToNextMajorVersion', 'minimumVersion' => '0.41.0' }
  project.root_object.package_references << pkg
  puts 'added MPVKit package reference'
end

unless target.package_product_dependencies.any? { |d| d.product_name == 'MPVKit' }
  dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dep.package = pkg
  dep.product_name = 'MPVKit'
  target.package_product_dependencies << dep
  bf = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  bf.product_ref = dep
  target.frameworks_build_phase.files << bf
  puts 'linked MPVKit product'
end

patch_name = 'Patch MPVKit Module Maps'
unless target.build_phases.any? { |p| p.respond_to?(:name) && p.name == patch_name }
  phase = target.new_shell_script_build_phase(patch_name)
  phase.shell_script = '"${SRCROOT}/scripts/patch-modulemaps.sh"'
  phase.run_only_for_deployment_postprocessing = '0'
  target.build_phases.delete(phase)
  target.build_phases.unshift(phase)
  puts 'added module-map patch pre-build phase'
end

target.build_configurations.each do |config|
  config.build_settings['SWIFT_OBJC_BRIDGING_HEADER'] ||= 'Runner/Runner-Bridging-Header.h'
  config.build_settings['TVOS_DEPLOYMENT_TARGET'] = '16.0'
end

project.build_configurations.each do |config|
  config.build_settings['TVOS_DEPLOYMENT_TARGET'] = '16.0'
end

project.save
puts 'saved project'
