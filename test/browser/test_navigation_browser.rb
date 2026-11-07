# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Team navigation flow (browser)' do
  include MainlineDSL

  before do
    setup_team(name: 'Acme')
    @alice = add_person(name: 'Alice')
    @bob   = add_person(name: 'Bob')
    create_map(name: 'Onboarding')
    persona  = create_persona('Customer')
    activity = create_activity('Browse', for_personas: [persona])
    task     = create_task('Search', under_activity: activity)
    story    = create_story('Find things', under_task: task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)
  end

  it 'navigates team → map → team → teamwork' do
    use_browser!

    driver.visit_team_dashboard(@team)

    assert_text 'Acme'
    assert_text 'Onboarding'

    find('[data-test-id="map-onboarding"]').click

    assert_selector '.nav-breadcrumb', text: 'Onboarding'

    click_on 'Acme'

    assert_text 'Acme'

    find('.nav-dropdown-trigger', text: 'Teamwork').hover
    click_on 'Pairing Matrix'

    assert_selector '.nav-breadcrumb', text: 'Teamwork'
    assert_text 'Alice'
    assert_text 'Bob'
  end
end
