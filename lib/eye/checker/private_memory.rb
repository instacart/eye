require_relative 'smaps_memory'

class Eye::Checker::PrivateMemory < Eye::Checker::Measure

  # check :private_memory, :below => 256.megabytes, :every => 20.seconds
  #
  # Reads Private_Dirty from /proc/{pid}/smaps_rollup. This measures only
  # pages the process has written to privately — the right metric for
  # fork-based workers (Puma, Sidekiq) where RSS double-counts shared
  # copy-on-write pages.

  include Eye::Checker::SmapsMemory
  smaps_field 'Private_Dirty:'

end
