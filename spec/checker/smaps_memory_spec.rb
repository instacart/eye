require File.dirname(__FILE__) + '/../spec_helper'
require 'tmpdir'
require 'fileutils'

# rubocop:disable Metrics/BlockLength
describe 'SmapsMemory checkers' do
  # Minimal smaps_rollup fixture matching the kernel format
  SMAPS_CONTENT = <<~SMAPS
    00000000-ffffffff ---p 00000000 00:00 0                          [rollup]
    Rss:               51200 kB
    Pss:               42000 kB
    Shared_Clean:       8000 kB
    Shared_Dirty:       1200 kB
    Private_Clean:      2000 kB
    Private_Dirty:     40000 kB
    Referenced:        50000 kB
    Anonymous:         45000 kB
    Swap:                  0 kB
  SMAPS

  let(:tmpdir) { Dir.mktmpdir('smaps_test') }
  let(:smaps_path) { File.join(tmpdir, 'smaps_rollup') }

  before(:each) do
    File.write(smaps_path, SMAPS_CONTENT)
  end

  after(:each) { FileUtils.rm_rf(tmpdir) }

  describe Eye::Checker::PrivateMemory do
    it 'reads Private_Dirty from smaps_rollup' do
      checker = Eye::Checker::PrivateMemory.new(123, { type: :private_memory, every: 5, below: 100.megabytes })

      # Point at our fixture file instead of /proc/{pid}/smaps_rollup
      checker.instance_variable_set(:@smaps_file, File.open(smaps_path))
      contents = File.read(smaps_path)
      field_name = 'Private_Dirty:'
      idx = contents.index(field_name) + field_name.size
      checker.instance_variable_set(:@smaps_field_offset, idx)
      checker.instance_variable_set(:@smaps_field_size, contents.index('kB', idx) - idx)

      value = checker.get_value
      value.should == 40_000.kilobytes
    end
  end

  describe Eye::Checker::SharedMemory do
    it 'reads Shared_Dirty from smaps_rollup' do
      checker = Eye::Checker::SharedMemory.new(123, { type: :shared_memory, every: 5, below: 100.megabytes })

      checker.instance_variable_set(:@smaps_file, File.open(smaps_path))
      contents = File.read(smaps_path)
      field_name = 'Shared_Dirty:'
      idx = contents.index(field_name) + field_name.size
      checker.instance_variable_set(:@smaps_field_offset, idx)
      checker.instance_variable_set(:@smaps_field_size, contents.index('kB', idx) - idx)

      value = checker.get_value
      value.should == 1_200.kilobytes
    end
  end

  describe 'human_value' do
    it 'formats bytes as megabytes' do
      checker = Eye::Checker::PrivateMemory.new(123, { type: :private_memory, every: 5, below: 100.megabytes })
      checker.human_value(256.megabytes).should == '256Mb'
    end
  end

  describe 'macOS fallback' do
    it 'falls back to ps when smaps_rollup is not available' do
      checker = Eye::Checker::PrivateMemory.new($$, { type: :private_memory, every: 5, below: 500.megabytes })

      # Ensure smaps state is nil (simulates macOS / no smaps_rollup)
      checker.instance_variable_set(:@smaps_file, nil)
      checker.instance_variable_set(:@smaps_field_size, nil)

      value = checker.get_value
      value.should > 0
      value.should < 500.megabytes
    end
  end

  describe 'DSL integration' do
    it 'private_memory is recognized in DSL' do
      conf = <<-E
        Eye.application("bla") do
          process("1") do
            pid_file "1.pid"
            checks :private_memory, :below => 256.megabytes, :every => 20.seconds
          end
        end
      E
      result = Eye::Dsl.parse_apps(conf)
      checks = result['bla'][:groups]['__default__'][:processes]['1'][:checks]
      checks[:private_memory].should == { below: 256.megabytes, every: 20, type: :private_memory }
    end

    it 'shared_memory is recognized in DSL' do
      conf = <<-E
        Eye.application("bla") do
          process("1") do
            pid_file "1.pid"
            checks :shared_memory, :below => 1024.megabytes, :every => 60.seconds
          end
        end
      E
      result = Eye::Dsl.parse_apps(conf)
      checks = result['bla'][:groups]['__default__'][:processes]['1'][:checks]
      checks[:shared_memory].should == { below: 1024.megabytes, every: 60, type: :shared_memory }
    end
  end
end
# rubocop:enable Metrics/BlockLength
