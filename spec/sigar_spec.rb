require File.dirname(__FILE__) + '/spec_helper'
require 'tmpdir'
require 'fileutils'

# rubocop:disable Metrics/BlockLength, Metrics/ParameterLists
describe Sigar do
  let(:proc_root) { Dir.mktmpdir('fake_proc') }
  let(:boot_time) { 1_700_000_000 }

  after(:each) { FileUtils.rm_rf(proc_root) }

  def write_proc_file(path, content)
    full = File.join(proc_root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end

  def setup_proc_stat
    write_proc_file('stat', "cpu  123 456 789\nbtime #{boot_time}\n")
  end

  # Build a /proc/[pid]/stat line with the standard 44-field format.
  def build_stat_line(pid:, comm: 'ruby', ppid: 1, utime: 500, stime: 200, starttime: 100_000)
    fields_after_comm = "S #{ppid} #{pid} #{pid} 0 -1 0 0 0 0 0 " \
                        "#{utime} #{stime} 0 0 20 0 1 0 #{starttime} " \
                        '0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0'
    "#{pid} (#{comm}) #{fields_after_comm}"
  end

  def setup_process(pid, comm: 'ruby', ppid: 1, utime: 500, stime: 200, starttime: 100_000,
                    statm_resident: 10_000, cmdline: "ruby\0script.rb\0--verbose")
    write_proc_file("#{pid}/stat", build_stat_line(pid: pid, comm: comm, ppid: ppid,
                                                   utime: utime, stime: stime, starttime: starttime))
    write_proc_file("#{pid}/statm", "50000 #{statm_resident} 5000 1000 0 8000 0")
    write_proc_file("#{pid}/cmdline", cmdline)
  end

  describe '#proc_mem' do
    before(:each) { setup_proc_stat }

    it 'returns resident memory in bytes from statm' do
      setup_process(42, statm_resident: 12_345)
      sigar = Sigar.new(proc_root: proc_root)

      mem = sigar.proc_mem(42)
      mem.resident.should == 12_345 * 4096
    end

    it 'returns a ProcMem struct' do
      setup_process(42)
      sigar = Sigar.new(proc_root: proc_root)

      sigar.proc_mem(42).should be_a(Sigar::ProcMem)
    end

    it 'raises ArgumentError for nonexistent PID' do
      sigar = Sigar.new(proc_root: proc_root)

      expect { sigar.proc_mem(99_999) }.to raise_error(ArgumentError)
    end
  end

  describe '#proc_cpu' do
    before(:each) { setup_proc_stat }

    it 'returns percent 0.0 on first call' do
      setup_process(42, utime: 500, stime: 200)
      sigar = Sigar.new(proc_root: proc_root)

      sigar.proc_cpu(42).percent.should == 0.0
    end

    it 'returns a delta-based percent on subsequent calls' do
      setup_process(42, utime: 500, stime: 200)
      sigar = Sigar.new(proc_root: proc_root)

      sigar.proc_cpu(42)
      sleep 0.05

      write_proc_file('42/stat', build_stat_line(pid: 42, utime: 600, stime: 250))

      sigar.proc_cpu(42).percent.should > 0.0
    end

    it 'resets to 0.0 when total goes backwards (PID reuse)' do
      setup_process(42, utime: 500, stime: 200)
      sigar = Sigar.new(proc_root: proc_root)

      sigar.proc_cpu(42)
      sleep 0.01

      write_proc_file('42/stat', build_stat_line(pid: 42, utime: 10, stime: 5))

      sigar.proc_cpu(42).percent.should == 0.0
    end

    it 'converts start_time from ticks to milliseconds since epoch' do
      setup_process(42, starttime: 100_000)
      sigar = Sigar.new(proc_root: proc_root)

      cpu = sigar.proc_cpu(42)
      expected_ms = (boot_time * 1000) + (100_000 * 1000 / 100)
      cpu.start_time.should == expected_ms
    end

    it 'converts utime and stime ticks to milliseconds' do
      setup_process(42, utime: 500, stime: 200)
      sigar = Sigar.new(proc_root: proc_root)

      cpu = sigar.proc_cpu(42)
      expect(cpu.total).to eq(7000)
      expect(cpu.user).to eq(5000)
      expect(cpu.sys).to eq(2000)
    end

    it 'returns a ProcCpu struct' do
      setup_process(42)
      sigar = Sigar.new(proc_root: proc_root)

      sigar.proc_cpu(42).should be_a(Sigar::ProcCpu)
    end

    it 'raises ArgumentError for nonexistent PID' do
      sigar = Sigar.new(proc_root: proc_root)

      expect { sigar.proc_cpu(99_999) }.to raise_error(ArgumentError)
    end
  end

  describe '#proc_args' do
    before(:each) { setup_proc_stat }

    it 'splits cmdline on null bytes' do
      setup_process(42, cmdline: "ruby\0script.rb\0--verbose")
      sigar = Sigar.new(proc_root: proc_root)

      sigar.proc_args(42).should == ['ruby', 'script.rb', '--verbose']
    end

    it 'handles single-arg commands' do
      setup_process(42, cmdline: "sleep\0")
      sigar = Sigar.new(proc_root: proc_root)

      sigar.proc_args(42).should == ['sleep']
    end

    it 'returns empty string array for zombie processes' do
      setup_process(42, cmdline: '')
      sigar = Sigar.new(proc_root: proc_root)

      sigar.proc_args(42).should == ['']
    end

    it 'raises ArgumentError for nonexistent PID' do
      sigar = Sigar.new(proc_root: proc_root)

      expect { sigar.proc_args(99_999) }.to raise_error(ArgumentError)
    end
  end

  describe '#proc_list' do
    before(:each) { setup_proc_stat }

    it 'finds child PIDs by parent PID' do
      setup_process(100, ppid: 1)
      setup_process(200, ppid: 42)
      setup_process(300, ppid: 42)
      setup_process(400, ppid: 99)
      sigar = Sigar.new(proc_root: proc_root)

      sigar.proc_list('State.Ppid.eq=42').sort.should == [200, 300]
    end

    it 'returns empty array when no children found' do
      setup_process(100, ppid: 1)
      sigar = Sigar.new(proc_root: proc_root)

      sigar.proc_list('State.Ppid.eq=99999').should == []
    end

    it 'returns empty array for nil query' do
      sigar = Sigar.new(proc_root: proc_root)

      sigar.proc_list(nil).should == []
    end
  end

  describe 'parse_stat_line edge cases' do
    before(:each) { setup_proc_stat }

    it 'handles comm with spaces' do
      setup_process(42, comm: 'Web Content')
      sigar = Sigar.new(proc_root: proc_root)

      sigar.proc_cpu(42).should be_a(Sigar::ProcCpu)
    end

    it 'handles comm with nested parentheses' do
      setup_process(42, comm: '(sd-pam)')
      sigar = Sigar.new(proc_root: proc_root)

      sigar.proc_cpu(42).should be_a(Sigar::ProcCpu)
    end

    it 'handles comm with special characters' do
      setup_process(42, comm: 'kworker/0:1-events')
      sigar = Sigar.new(proc_root: proc_root)

      sigar.proc_cpu(42).should be_a(Sigar::ProcCpu)
    end
  end

  describe 'thread safety' do
    before(:each) { setup_proc_stat }

    it 'handles concurrent proc_cpu calls' do
      setup_process(42, utime: 100, stime: 50)
      sigar = Sigar.new(proc_root: proc_root)

      threads = Array.new(4) do
        Thread.new { sigar.proc_cpu(42) }
      end

      results = threads.map(&:value)
      results.each { |r| r.should be_a(Sigar::ProcCpu) }
    end
  end
end
# rubocop:enable Metrics/BlockLength, Metrics/ParameterLists
