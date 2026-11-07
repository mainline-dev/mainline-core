# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/ci_monitor_dsl'

describe 'CI Monitor keyboard shortcut (browser)' do
  include MainlineDSL
  include CIMonitorDSL

  before do
    setup_team(name: 'Acme')
    add_person(name: 'Alice')
    create_map(name: 'Onboarding')
  end

  it 'goes to the monitor with g c' do
    use_browser!

    visit_map
    press_shortcut('g', 'c')

    assert_on_monitor
  end
end
