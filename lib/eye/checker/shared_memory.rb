require_relative 'smaps_memory'

class Eye::Checker::SharedMemory < Eye::Checker::Measure

  # check :shared_memory, :below => 1024.megabytes, :every => 60.seconds
  #
  # Reads Shared_Dirty from /proc/{pid}/smaps_rollup. Useful for
  # monitoring cluster parents where shared memory growth indicates
  # a problem with the copy-on-write pool.

  include Eye::Checker::SmapsMemory
  smaps_field 'Shared_Dirty:'

end
