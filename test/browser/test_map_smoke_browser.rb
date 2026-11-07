# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Map smoke (browser)' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice', email: 'alice@acme.co')
    create_map
    @persona  = create_persona('Customer')
    @activity = create_activity('Onboarding', for_personas: [@persona])
    @task     = create_task('Sign up', under_activity: @activity)
    @story    = create_story('Fill in registration form', under_task: @task)
  end

  it 'renders the map with activities, tasks, and stories' do
    use_browser!
    driver.visit_map(@map)

    assert_selector '.map-grid'
    assert_selector '.activity-header', text: /Onboarding/i
    assert_selector '.persona-badge',   text: 'Customer'
    assert_selector '.task-col',        text: 'Sign up'
    assert_selector '.story-card'
    assert_selector '.card-body', text: 'Fill in registration form'
    assert_selector '.state-label.state-planned', text: 'PLAN'
  end
end
