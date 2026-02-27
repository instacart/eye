#!/usr/bin/env rake

require 'bundler/gem_tasks'

task default: :spec

desc 'run specs'
task :spec do
  abort unless system('bundle exec rspec spec')
end

task :remove_coverage do
  require 'fileutils'
  FileUtils.rm_rf(File.expand_path(File.join(File.dirname(__FILE__), %w[coverage])))
end

task :env do
  require 'bundler/setup'
  require 'eye'
  Eye::Controller
  Eye::Process
end

desc 'graph'
task graph: :env do
  StateMachine::Machine.draw('Eye::Process')
end
