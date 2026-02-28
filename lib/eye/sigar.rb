# Pure-Ruby replacement for kostya-sigar.
# Reads /proc directly on Linux, falls back to ps/pgrep on macOS.

class Sigar

  ProcMem = Struct.new(:vsize, :resident, :share, :minor_faults, :major_faults, :page_faults)
  ProcCpu = Struct.new(:percent, :start_time, :total, :user, :sys, :last_time)

  CLK_TCK = 100
  PAGE_SIZE = 4096

  def initialize(proc_root: '/proc')
    @proc_root = proc_root
    @cpu_cache = {}
    @cpu_mutex = Mutex.new
    @linux = File.directory?(@proc_root) && File.exist?(File.join(@proc_root, 'stat'))

    @boot_time = read_boot_time if @linux
  end

  def proc_mem(pid)
    @linux ? proc_mem_linux(pid) : proc_mem_fallback(pid)
  rescue Errno::ENOENT, Errno::ESRCH, Errno::EACCES
    raise ArgumentError, "No such process: #{pid}"
  end

  def proc_cpu(pid)
    @linux ? proc_cpu_linux(pid) : proc_cpu_fallback(pid)
  rescue Errno::ENOENT, Errno::ESRCH, Errno::EACCES
    raise ArgumentError, "No such process: #{pid}"
  end

  def proc_args(pid)
    @linux ? proc_args_linux(pid) : proc_args_fallback(pid)
  rescue Errno::ENOENT, Errno::ESRCH, Errno::EACCES
    raise ArgumentError, "No such process: #{pid}"
  end

  def proc_list(query = nil)
    @linux ? proc_list_linux(query) : proc_list_fallback(query)
  end

private

  # ---- Linux /proc implementations ----

  def proc_mem_linux(pid)
    data = File.read(File.join(@proc_root, pid.to_s, 'statm'))
    fields = data.split
    resident_pages = fields[1].to_i
    ProcMem.new(0, resident_pages * PAGE_SIZE, 0, 0, 0, 0)
  end

  def proc_cpu_linux(pid)
    stat = read_proc_stat(pid)

    user_ms = ticks_to_ms(stat[:utime])
    sys_ms = ticks_to_ms(stat[:stime])
    total_ms = user_ms + sys_ms
    start_time_ms = (@boot_time * 1000) + ticks_to_ms(stat[:starttime])

    percent = calculate_cpu_percent(pid, total_ms)

    ProcCpu.new(percent, start_time_ms, total_ms, user_ms, sys_ms, 0)
  end

  def proc_args_linux(pid)
    cmdline = File.read(File.join(@proc_root, pid.to_s, 'cmdline'))
    return [''] if cmdline.empty?

    cmdline.split("\0")
  end

  def proc_list_linux(query)
    ppid = parse_ppid_query(query)
    return [] unless ppid

    children = []
    Dir.glob(File.join(@proc_root, '[0-9]*', 'stat')).each do |stat_path|
      line = File.read(stat_path)
      stat = parse_stat_line(line)
      children << stat[:pid] if stat[:ppid] == ppid
    rescue Errno::ENOENT, Errno::ESRCH, Errno::EACCES
      # Process disappeared while scanning
    end
    children
  end

  # ---- macOS/fallback implementations ----

  def proc_mem_fallback(pid)
    output = `ps -o rss= -p #{pid.to_i} 2>/dev/null`.strip
    raise ArgumentError, "No such process: #{pid}" if output.empty?

    resident_bytes = output.to_i * 1024
    ProcMem.new(0, resident_bytes, 0, 0, 0, 0)
  end

  def proc_cpu_fallback(pid)
    output = `ps -o %cpu=,lstart= -p #{pid.to_i} 2>/dev/null`.strip
    raise ArgumentError, "No such process: #{pid}" if output.empty?

    parts = output.split(nil, 2)
    cpu_ratio = parts[0].to_f / 100.0

    start_time_ms = 0
    if parts[1]
      require 'time'
      start_time_ms = (Time.parse(parts[1]).to_f * 1000).to_i rescue 0
    end

    total_ms = cpu_total_fallback(pid)

    ProcCpu.new(cpu_ratio, start_time_ms, total_ms, total_ms, 0, 0)
  end

  def proc_args_fallback(pid)
    output = `ps -o args= -p #{pid.to_i} 2>/dev/null`.strip
    raise ArgumentError, "No such process: #{pid}" if output.empty?

    [output]
  end

  def proc_list_fallback(query)
    ppid = parse_ppid_query(query)
    return [] unless ppid

    output = `pgrep -P #{ppid.to_i} 2>/dev/null`.strip
    return [] if output.empty?

    output.split("\n").map(&:to_i)
  end

  # ---- Shared helpers ----

  def read_boot_time
    File.readlines(File.join(@proc_root, 'stat')).each do |line|
      return line.split[1].to_i if line.start_with?('btime ')
    end
    0
  end

  def read_proc_stat(pid)
    parse_stat_line(File.read(File.join(@proc_root, pid.to_s, 'stat')))
  end

  # Parse /proc/[pid]/stat, handling comm fields with spaces and parens.
  # Format: pid (comm) state ppid ... utime(14) stime(15) ... starttime(22) ...
  # The comm field can contain anything, so we find the last ')' first.
  def parse_stat_line(line)
    rparen = line.rindex(')')
    raise ArgumentError, 'Invalid stat line' unless rparen

    pid = line[0...line.index('(')].strip.to_i
    fields = line[(rparen + 2)..].split

    # fields[0]=state(3), [1]=ppid(4), ..., [11]=utime(14), [12]=stime(15), ..., [19]=starttime(22)
    {
      pid: pid,
      ppid: fields[1].to_i,
      utime: fields[11].to_i,
      stime: fields[12].to_i,
      starttime: fields[19].to_i
    }
  end

  def ticks_to_ms(ticks)
    (ticks * 1000) / CLK_TCK
  end

  # Stateful CPU percent calculation matching sigar's delta-based approach.
  # First call for a PID returns 0.0; subsequent calls return the delta.
  def calculate_cpu_percent(pid, total_ms)
    now_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i

    @cpu_mutex.synchronize do
      cached = @cpu_cache[pid]

      if cached.nil? || total_ms < cached[:total_ms]
        @cpu_cache[pid] = { total_ms: total_ms, wall_ms: now_ms }
        return 0.0
      end

      wall_delta = now_ms - cached[:wall_ms]
      return cached[:percent] || 0.0 if wall_delta <= 0

      total_delta = total_ms - cached[:total_ms]
      percent = total_delta.to_f / wall_delta

      @cpu_cache[pid] = { total_ms: total_ms, wall_ms: now_ms, percent: percent }
      percent
    end
  end

  # On macOS, use Process.times for current process, 0 for others.
  def cpu_total_fallback(pid)
    if pid == Process.pid
      usage = Process.times
      ((usage.utime + usage.stime) * 1000).to_i
    else
      0
    end
  end

  def parse_ppid_query(query)
    return nil unless query

    ::Regexp.last_match(1).to_i if query =~ %r[State\.Ppid\.eq=(\d+)]
  end

end

Eye::Sigar = Sigar.new
