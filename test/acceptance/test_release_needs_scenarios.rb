# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

# A story's scenarios say what done means, so a story is released only once it
# has at least one and every one is done. One nobody wrote a scenario for can
# still go out, with a reason the team can read later. A scenario that isn't
# done is done, split out into a story of its own, or deleted.
describe 'Releasing a story needs its scenarios done' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    @bob   = add_person(name: 'Bob')
    create_map
    task = create_task('Search', under_activity: create_activity('Browse', for_personas: [create_persona('Shopper')]))
    @story = create_story('Find things', under_task: task)
    assign_person(@story, person: @alice)
    assign_person(@story, person: @bob)
    deploy_story(@story)
  end

  def write_a_scenario(story)
    create_scenario(story, given_text: 'a shopper', when_text: 'they search', then_text: 'they see what matches')
  end

  it 'cannot be released without a scenario' do
    release_story(@story)

    assert_refused_because('no-scenarios')
    assert_equal 'active', status_of(@story)
  end

  it 'is released once its scenario is done' do
    pass_a_scenario(@story)

    release_story(@story)

    assert_equal 'released', status_of(@story)
  end

  it 'cannot be released while a scenario is not done' do
    write_a_scenario(@story)

    release_story(@story)

    assert_refused_because('unverified-scenarios')
    assert_equal 'active', status_of(@story)
  end

  it 'is released without scenarios when someone says why' do
    release_without_scenarios(@story, reason: 'A copy change on the pricing page')

    assert_equal 'released', status_of(@story)
  end

  it 'keeps the reason in the story history' do
    release_without_scenarios(@story, reason: 'A copy change on the pricing page')

    visit_story_history(@story)

    assert(story_history.any? { |entry| entry.include?('A copy change on the pricing page') })
  end

  it 'needs a reason to be released without scenarios' do
    release_without_scenarios(@story, reason: ' ')

    assert_refused_because('reason-needed')
    assert_equal 'active', status_of(@story)
  end

  it 'cannot go out without a scenario it has but has not done' do
    write_a_scenario(@story)

    release_without_scenarios(@story, reason: 'Shipping the rest now')

    assert_refused_because('unverified-scenarios')
    assert_equal 'active', status_of(@story)
  end

  it 'says, where Release would be, that it needs a scenario, and offers to release without one' do
    visit_story_card(@story)

    refute_shown('release-find-things')
    assert_shown('release-needs-scenario')
    assert_shown('release-without-scenarios')
  end

  it 'says the same on the map' do
    visit_map

    assert_shown('release-needs-scenario')
  end

  it 'says, where Release would be, that its scenarios need to be done' do
    write_a_scenario(@story)

    visit_story_card(@story)

    refute_shown('release-find-things')
    refute_shown('release-without-scenarios')
    assert_shown('release-needs-scenarios-done')
  end

  it 'offers Release once every scenario is done' do
    pass_a_scenario(@story)

    visit_story_card(@story)

    assert_shown('release-find-things')
    refute_shown('release-needs-scenario')
  end
end

# An urgent fix often goes out before anyone writes a scenario for it, so an
# urgent story needs none. Any scenario it does have is done first, as on any
# other story.
describe 'Releasing an urgent story' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    @bob   = add_person(name: 'Bob')
    create_map
    task = create_task('Operate', under_activity: create_activity('Run the shop', for_personas: [create_persona('Operator')]))
    @patch = create_story('Operators can rotate the payment key', under_task: task)
    start_as_urgent(@patch, reason: 'The payment key leaked')
    assign_person(@patch, person: @bob)
    deploy_story(@patch)
  end

  it 'needs no scenario' do
    release_story(@patch)

    assert_equal 'released', status_of(@patch)
  end

  it 'offers Release on its card with no scenario' do
    visit_story_card(@patch)

    assert_shown('release-operators-can-rotate-the-payment-key')
    refute_shown('release-needs-scenario')
  end

  it 'still needs any scenario it has done' do
    create_scenario(@patch, given_text: 'a leaked key', when_text: 'an operator rotates it',
      then_text: 'the old key stops working')

    release_story(@patch)

    assert_refused_because('unverified-scenarios')
    assert_equal 'active', status_of(@patch)
  end
end
