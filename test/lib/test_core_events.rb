# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/core_events'

# Core announces what happened; code in its own files subscribes. Subscribers
# run straight away, in the order they subscribed.
describe CoreEvents do
  before { @subscriptions = [] }
  after { @subscriptions.each { |sub| CoreEvents.unsubscribe(sub) } }

  def listen(event, &)
    @subscriptions << CoreEvents.subscribe(event, &)
  end

  it 'does nothing when nobody listens' do
    CoreEvents.publish(:nobody_listens, team_id: 'team-1')
  end

  it 'hands each subscriber the payload of the event it listens for' do
    heard = []
    listen(:thing_happened) { |payload| heard << payload }
    listen(:other_thing_happened) { |payload| heard << [:wrong, payload] }

    CoreEvents.publish(:thing_happened, team_id: 'team-1')

    assert_equal [{ team_id: 'team-1' }], heard
  end

  it 'runs subscribers in the order they subscribed' do
    heard = []
    listen(:thing_happened) { |_| heard << :first }
    listen(:thing_happened) { |_| heard << :second }

    CoreEvents.publish(:thing_happened, team_id: 'team-1')

    assert_equal %i[first second], heard
  end

  it 'stops telling a subscriber once it unsubscribes' do
    heard = []
    sub = CoreEvents.subscribe(:thing_happened) { |payload| heard << payload }
    CoreEvents.unsubscribe(sub)

    CoreEvents.publish(:thing_happened, team_id: 'team-1')

    assert_empty heard
  end
end
