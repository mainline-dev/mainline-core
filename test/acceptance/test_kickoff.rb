# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

# The kickoff is the second person coming to a story before the work. On a
# story one person works on, that is someone else agreeing its scenarios. It
# is recorded and shown, and nothing waits on it.
describe 'The kickoff on a story one person works on' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    @bob   = add_person(name: 'Bob')
    create_map
    activity = create_activity('Browse', for_personas: [create_persona('Shopper')])
    @story = create_story('Find things', under_task: create_task('Search', under_activity: activity))
    create_scenario(@story, given_text: 'a full shop', when_text: 'a guest searches', then_text: 'matches are listed')
  end

  it 'shows who agreed the scenarios once a second person has' do
    login_as(@bob)
    agree_scenarios(@story)

    assert_equal({ state: 'agreed', people: [@bob.id] }, kickoff_of(@story))
  end

  it 'has not happened while nobody else has agreed the scenarios' do
    assert_equal({ state: 'none', people: [] }, kickoff_of(@story))
  end

  it 'says the scenarios have changed since, once one is edited after the kickoff' do
    login_as(@bob)
    agree_scenarios(@story)
    login_as(@alice)
    update_scenario(@story, Scenario.where(story_id: @story.id).first,
      given_text: 'a full shop', when_text: 'a guest searches', then_text: 'matches are listed by price')

    assert_equal({ state: 'changed', people: [@bob.id] }, kickoff_of(@story))
  end

  it 'leaves the kickoff as it was when a scenario is saved with nothing changed' do
    login_as(@bob)
    agree_scenarios(@story)
    login_as(@alice)
    update_scenario(@story, Scenario.where(story_id: @story.id).first, name: 'matches are listed',
      given_text: 'a full shop', when_text: 'a guest searches', then_text: 'matches are listed')

    assert_equal({ state: 'agreed', people: [@bob.id] }, kickoff_of(@story))
  end

  it 'shows a story two people started as kicked off by the two of them' do
    assign_person(@story, person: @alice)
    assign_person(@story, person: @bob)

    assert_equal 'together', kickoff_of(@story)[:state]
    assert_equal [@alice.id, @bob.id].sort, kickoff_of(@story)[:people].sort
  end

  it 'does not take the person who last changed the scenarios as agreeing them' do
    agree_scenarios(@story)

    assert_equal({ state: 'none', people: [] }, kickoff_of(@story))
  end
end
