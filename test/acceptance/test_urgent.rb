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
end
