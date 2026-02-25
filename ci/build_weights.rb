# frozen_string_literal: true

# Aggregates per-file runtime from RSpec JSON output files.
#
# Usage: ruby ci/build_weights.rb results1.json results2.json ...
# Output: writes ci/spec_weights.json with { "spec/foo_spec.rb" => seconds }

require "json"

if ARGV.empty?
  warn "Usage: ruby ci/build_weights.rb <rspec_results.json> ..."
  exit 1
end

file_times = Hash.new(0.0)

ARGV.each do |path|
  data = JSON.parse(File.read(path))
  data["examples"].each do |ex|
    spec_file = ex["file_path"].delete_prefix("./")
    file_times[spec_file] += ex["run_time"]
  end
end

weights = file_times.sort_by { |_, t| -t }.to_h

File.write(
  File.expand_path("spec_weights.json", __dir__),
  JSON.pretty_generate(weights) + "\n"
)

total = weights.values.sum
puts "Wrote #{weights.size} file weights (total: #{total.round(1)}s)"
weights.first(10).each { |f, t| puts "  #{t.round(1)}s\t#{f}" }
