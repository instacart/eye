# frozen_string_literal: true

# Splits spec files into balanced groups for parallel CI.
#
# Reads GROUP (1-based) and TOTAL_GROUPS from environment.
# If ci/spec_weights.json exists, uses greedy bin-packing by runtime.
# Otherwise falls back to round-robin.
#
# Usage: ruby ci/split_specs.rb
# Output: space-separated list of spec files for this group

require "json"

WEIGHTS_FILE = File.expand_path("spec_weights.json", __dir__)

group = Integer(ENV.fetch("GROUP"))
total = Integer(ENV.fetch("TOTAL_GROUPS"))

spec_files = Dir.glob("spec/**/*_spec.rb")
  .reject { |f| f.start_with?("spec/support/", "spec/example/", "spec/fixtures/") }
  .sort

if File.exist?(WEIGHTS_FILE)
  weights = JSON.parse(File.read(WEIGHTS_FILE))

  # Greedy bin-packing: assign heaviest files first to the lightest bucket
  sorted = spec_files.sort_by { |f| -(weights[f] || 1.0) }
  buckets = Array.new(total) { [] }
  bucket_times = Array.new(total, 0.0)

  sorted.each do |file|
    lightest = bucket_times.each_with_index.min_by(&:first).last
    buckets[lightest] << file
    bucket_times[lightest] += (weights[file] || 1.0)
  end

  puts buckets[group - 1].join(" ")
else
  # Round-robin fallback
  my_files = spec_files.each_with_index
    .select { |_, i| i % total == (group - 1) }
    .map(&:first)

  puts my_files.join(" ")
end
