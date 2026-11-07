# test/models/test_event.rb
# frozen_string_literal: true

require 'securerandom'
require_relative '../model_spec_helper'

describe Event do
  cover 'Event*'
  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
  end

  def create_test_event
    Event.create(
      team_id:     @team.id,
      actor_id:    @person.actor_id,
      entity_type: 'persona',
      entity_id:   SecureRandom.uuid,
      action:      'created'
    )
  end

  it 'is append-only - cannot update via model' do
    event = create_test_event
    assert_raises(Sequel::Error) { event.update(action: 'modified') }
  end

  it 'is append-only - cannot update via raw SQL' do
    event = create_test_event
    assert_raises(Sequel::DatabaseError) do
      DB[:events].where(id: event.id).update(action: 'modified')
    end
  end

  it 'is append-only - cannot delete via model' do
    event = create_test_event
    assert_raises(Sequel::Error) { event.destroy }
  end

  it 'is append-only - cannot delete via raw SQL' do
    event = create_test_event
    assert_raises(Sequel::DatabaseError) do
      DB[:events].where(id: event.id).delete
    end
  end

  it 'assigns monotonically increasing event_no' do
    e1 = create_test_event
    e2 = create_test_event

    assert_operator e2.event_no, :>, e1.event_no
  end

  it 'allows delete when app.allow_team_deletion is set' do
    event = create_test_event
    DB.transaction(savepoint: true) do
      DB.run("SELECT set_config('app.allow_team_deletion', 'true', true)")
      DB[:events].where(id: event.id).delete

      assert_equal 0, DB[:events].where(id: event.id).count
    end
  end

  it 'still blocks update even when app.allow_team_deletion is set' do
    event = create_test_event
    assert_raises(Sequel::DatabaseError) do
      DB.transaction(savepoint: true) do
        DB.run("SELECT set_config('app.allow_team_deletion', 'true', true)")
        DB[:events].where(id: event.id).update(action: 'modified')
      end
    end
  end
end
