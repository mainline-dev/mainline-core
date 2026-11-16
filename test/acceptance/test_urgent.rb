# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

# A team can have one urgent story at a time: a security patch, a broken
# build, a rotated key. Anyone can start it, giving a reason, even while on
# another story, and anyone can join it whatever their WIP. It is still a
# story on the map.
describe 'The urgent story' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    @bob   = add_person(name: 'Bob')
    @carol = add_person(name: 'Carol')
    @dan   = add_person(name: 'Dan')
    create_map
    task = create_task('Operate', under_activity: create_activity('Run the shop', for_personas: [create_persona('Operator')]))
    @busy = create_story('Shoppers can save a card', under_task: task)
    assign_person(@busy, person: @alice)
    assign_person(@busy, person: @bob)
    @patch = create_story('Operators can rotate the payment key', under_task: task)
    @later = create_story('Operators can see failed payments', under_task: task)
  end

  it 'is started by someone already on a story, who goes on it, giving a reason' do
    start_as_urgent(@patch, reason: 'The payment key leaked')

    assert_equal 'active', status_of(@patch)
    assert_equal ['Alice'], people_on(@patch)
  end

  it 'needs a reason' do
    start_as_urgent(@patch, reason: ' ')

    assert_refused_because('reason-needed')
    assert_equal 'planned', status_of(@patch)
  end

  it 'is one at a time for the team' do
    start_as_urgent(@patch, reason: 'The payment key leaked')

    start_as_urgent(@later, reason: 'Payments are failing')

    assert_refused_because('urgent-taken')
    assert_equal 'planned', status_of(@later)
  end

  it 'takes anyone who joins, whatever their WIP' do
    start_as_urgent(@patch, reason: 'The payment key leaked')

    assign_person(@patch, person: @bob)

    assert_equal %w[Alice Bob], people_on(@patch)
  end

  it 'does not count against the one story of the people on it' do
    login_as(@carol)
    start_as_urgent(@patch, reason: 'The payment key leaked')

    assign_person(@later, person: @carol)
    assign_person(@later, person: @dan)

    assert_equal 'active', status_of(@later)
    assert_equal %w[Carol Dan], people_on(@later)
  end

  it 'has a red bar above the map, linking to it' do
    start_as_urgent(@patch, reason: 'The payment key leaked')

    visit_map

    assert_equal @patch.id, urgent_bar_story
    assert_equal "/maps/#{@map.id}/stories/#{@patch.id}/edit", urgent_bar_link
  end

  it 'has the bar on every map of the team, linking to the map it is on' do
    start_as_urgent(@patch, reason: 'The payment key leaked')
    first_map = @map
    create_map(name: 'Back office')

    visit_map

    assert_equal "/maps/#{first_map.id}/stories/#{@patch.id}/edit", urgent_bar_link
  end

  it 'has no bar while the team has no urgent story' do
    visit_map

    refute_shown('urgent-bar')
  end

  it 'has no bar once the urgent story is released' do
    start_as_urgent(@patch, reason: 'The payment key leaked')
    assign_person(@patch, person: @carol)
    deploy_story(@patch)
    release_story(@patch)

    visit_map

    refute_shown('urgent-bar')
  end

  it 'has a red card' do
    start_as_urgent(@patch, reason: 'The payment key leaked')

    visit_story_card(@patch)

    assert_shown('urgent-card')
  end

  it 'has an ordinary card once it is released' do
    start_as_urgent(@patch, reason: 'The payment key leaked')
    assign_person(@patch, person: @carol)
    deploy_story(@patch)
    release_story(@patch)

    visit_story_card(@patch)

    refute_shown('urgent-card')
  end
end

# An urgent fix is often live as soon as it deploys, so an urgent story one
# person worked on can be released before its walkthrough, and walked after.
describe 'An urgent story released before its walkthrough' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    @bob   = add_person(name: 'Bob')
    create_map
    task = create_task('Operate', under_activity: create_activity('Run the shop', for_personas: [create_persona('Operator')]))
    @patch = create_story('Operators can rotate the payment key', under_task: task)
    start_as_urgent(@patch, reason: 'The payment key leaked')
    deploy_story(@patch)
  end

  it 'can be released with one person on it and no walkthrough' do
    release_story(@patch)

    assert_equal 'released', status_of(@patch)
  end

  it 'offers Release on its card, where an ordinary story would need its walkthrough first' do
    visit_story_card(@patch)

    assert_shown('release-operators-can-rotate-the-payment-key')
    refute_shown('release-needs-walkthrough')
  end

  it 'waits on the Walkthroughs page to be walked afterwards' do
    release_story(@patch)

    visit_walkthroughs

    assert_equal [@patch.id], walk_afterwards
  end

  it 'counts against the walkthrough limit until it is walked' do
    release_story(@patch)

    visit_walkthroughs

    assert_equal 'released', status_of(@patch)

    assert_equal '1', walkthroughs_against_limit[:waiting]
  end

  it 'leaves the page once it is walked through' do
    release_story(@patch)
    record_walkthrough(@patch, attended_by: [@bob])

    visit_walkthroughs

    assert_equal 'released', status_of(@patch)

    assert_empty walk_afterwards
    assert_equal '0', walkthroughs_against_limit[:waiting]
  end
end
