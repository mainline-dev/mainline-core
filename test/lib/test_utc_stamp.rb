# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/utc_stamp'

describe UtcStamp do
  cover 'UtcStamp*'

  it 'writes a moment in UTC and says so, whatever zone it was given in, with the exact moment for anything reading the page' do
    evening = Time.new(2026, 11, 18, 22, 45, 30, '+11:00')

    assert_equal '<time datetime="2026-11-18T11:45:30Z">2026-11-18 11:45 UTC</time>', UtcStamp.html(evening)
  end
end
