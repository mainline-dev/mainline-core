# frozen_string_literal: true

require 'json'

# Builds a Mainline import file the way a model would write one from a
# specification: version 1, with each entry a hash of overrides on a plain
# proposed story. Anything else passed (map, personas, activities) goes in at
# the top of the file.
module MainlineFileFixture
  ENTRY = {
    key: 'RB-1', title: 'Two people change the same item at the same moment',
    source: 'Research report, section on racing saves'
  }.freeze

  def self.json(*entries, **top)
    JSON.generate({ mainline: 1, entries: entries.map { |entry| ENTRY.merge(entry).compact } }.merge(top).compact)
  end
end
