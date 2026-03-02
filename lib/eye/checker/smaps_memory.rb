# Base module for memory checkers that read /proc/{pid}/smaps_rollup.
#
# On Linux, opens smaps_rollup once and uses pread for minimal I/O on
# subsequent checks. On macOS, falls back to `ps -o rss=` (returns RSS
# regardless of the requested field — accurate values require Linux).
#
# Usage:
#   class Eye::Checker::PrivateMemory < Eye::Checker::Measure
#     include Eye::Checker::SmapsMemory
#     smaps_field 'Private_Dirty:'
#   end

module Eye::Checker::SmapsMemory

  def self.included(base)
    base.extend(ClassMethods)
    base.register(base)
  end

  module ClassMethods

    def smaps_field(name)
      @smaps_field_name = name
    end

    def smaps_field_name
      @smaps_field_name
    end

  end

  def initialize(*)
    super
    @smaps_buf = +''
    smaps_open_file
  end

  def check_name
    @check_name ||= "#{@type}(#{measure_str})"
  end

  def good?(*)
    return false unless smaps_available?

    super
  end

  def get_value
    return rss_fallback unless smaps_available?

    @smaps_file.pread(@smaps_field_size, @smaps_field_offset, @smaps_buf).to_i.kilobytes
  rescue Errno::ESRCH
    0
  end

  def human_value(value)
    "#{value.to_i / 1.megabyte}Mb"
  end

private

  def smaps_available?
    return true if @smaps_field_size

    smaps_open_file
    !!@smaps_field_size
  end

  def smaps_open_file
    filename = "/proc/#{@pid}/smaps_rollup"
    return unless File.exist?(filename)

    @smaps_file = File.open(filename)
    contents = @smaps_file.read
    @smaps_file.rewind
    return unless contents

    field_name = self.class.smaps_field_name
    idx = contents.index(field_name)
    return unless idx

    @smaps_field_offset = idx + field_name.size
    @smaps_field_size = contents.index('kB', @smaps_field_offset) - @smaps_field_offset
  rescue Errno::ENOENT, Errno::EACCES, Errno::ESRCH
    nil
  end

  def rss_fallback
    output = `ps -o rss= -p #{@pid.to_i} 2>/dev/null`.strip
    return 0 if output.empty?

    output.to_i * 1024
  end

end
