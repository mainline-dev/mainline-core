# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

# The cross on a scenario asks before it deletes. The way to keep the scenario
# sits where the cross was, so a second click on the same spot keeps it.
describe 'Deleting a scenario (browser)' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    create_map
    activity = create_activity('Browse', for_personas: [create_persona('Customer')])
    @story = create_story('Find things', under_task: create_task('Search', under_activity: activity))
    create_scenario(@story, given_text: 'a full shop', when_text: 'a guest searches', then_text: 'matches are listed')
    use_browser!
    visit_edit_story(@story)
  end

  it 'asks first, with a way to delete and a way to keep' do
    press_scenario_cross

    assert_shown('scenario-delete-ask')
    assert_shown('scenario-delete-yes')
    assert_shown('scenario-keep')
    assert_shown('scenario-name')
  end

  it 'keeps the scenario when the same spot is clicked a second time' do
    spot = where_the_scenario_cross_is
    click_at(spot)

    assert_shown('scenario-keep')
    click_at(spot)

    refute_shown('scenario-keep')
    assert_shown('scenario-delete')
    assert_shown('scenario-name')
  end

  it 'goes on asking until someone answers' do
    press_scenario_cross
    sleep 3.2

    assert_shown('scenario-keep')
    assert_shown('scenario-name')
  end

  it 'deletes the scenario on Delete' do
    press_scenario_cross
    confirm_scenario_delete

    refute_shown('scenario-name')
  end
end
