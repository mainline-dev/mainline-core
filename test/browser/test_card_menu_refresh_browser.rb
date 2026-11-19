# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

# A board stays on screen while its stories change: on the story's own page,
# in another tab, or under a teammate's hands. A card's menu says what can be
# done with the story now, so it asks again each time it is opened.
describe 'A card menu on a board drawn a while ago (browser)' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    @bob = add_person(name: 'Bob')
    create_map
    activity = create_activity('Browse', for_personas: [create_persona('Customer')])
    @story = create_story('Find things', under_task: create_task('Search', under_activity: activity))
    assign_person(@story, person: @alice)
    assign_person(@story, person: @bob)
    deploy_story(@story)
    create_scenario(@story, given_text: 'a full shop', when_text: 'a guest searches', then_text: 'matches are listed')
    use_browser!
    visit_map
  end

  it 'offers the release once the scenario has been done somewhere else' do
    elsewhere(as: @alice) { mark_scenario_done(@story, scenarios_on(@story).last) }

    open_card_menu

    assert_shown('release-find-things')
    refute_shown('release-needs-scenarios-done')
    assert_predicate self, :card_menu_open?
  end

  it 'stops offering the release once a scenario has been added somewhere else' do
    elsewhere(as: @alice) { mark_scenario_done(@story, scenarios_on(@story).last) }
    visit_map
    elsewhere(as: @alice) do
      create_scenario(@story, given_text: 'an empty shop', when_text: 'a guest searches', then_text: 'nothing is listed')
    end

    open_card_menu

    assert_shown('release-needs-scenarios-done')
    refute_shown('release-find-things')
  end
end
