# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/ci_monitor_dsl'

describe 'CI Monitor in the team nav' do
  include MainlineDSL
  include CIMonitorDSL

  before do
    setup_team(name: 'Acme')
    add_person(name: 'Alice', email: 'alice@acme.co')
    create_map
    visit_map
  end

  it 'links to the monitor from the team nav' do
    assert_monitor_in_nav
  end

  it 'lists its g c shortcut in the cheatsheet' do
    assert_monitor_shortcut_listed(key: 'c')
  end
end
