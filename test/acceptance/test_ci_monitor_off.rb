# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

# An install can run without the CI Monitor: with its six GitHub App settings
# set to "disabled", the CI Monitor page says it is not set up on this server
# and GitHub's webhook address does not exist.
describe 'An install without the CI Monitor' do
  include MainlineDSL

  before do
    setup_team
    add_person(name: 'Alice')
  end

  it 'says the CI Monitor is not set up on this server' do
    with_ci_monitor_off do
      visit_ci_monitor

      assert_shown('ci-monitor-off')
    end
  end

  it 'has no address for GitHub webhooks' do
    with_ci_monitor_off do
      assert_no_such_page { send_github_webhook }
    end
  end

  it 'offers to connect GitHub when the CI Monitor is set up' do
    visit_ci_monitor

    refute_shown('ci-monitor-off')
  end
end
