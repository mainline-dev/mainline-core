# frozen_string_literal: true

require_relative '../model_spec_helper'

class TestConnectionPinning < Minitest::Test
  def setup
    @superuser = Sequel.connect('postgres://mainline:password@db:5432/mainline_test')
    @team_id = @superuser[:teams].insert(
      id: Sequel.lit('gen_random_uuid()'), name: 'Pin Test',
      created_at: Time.now, updated_at: Time.now
    )
    @superuser[:maps].insert(
      id: Sequel.lit('gen_random_uuid()'), team_id: @team_id,
      name: 'Pinned Map', position: 1000
    )
  end

  def teardown
    @superuser[:maps].where(team_id: @team_id).delete
    @superuser[:teams].where(id: @team_id).delete
    @superuser.disconnect
  end

  def test_unpinned_connection_loses_team_context
    app_url = 'postgres://mainline_app:app_password@db:5432/mainline_test'
    db = Sequel.connect(app_url, max_connections: 2)

    db.run("SELECT set_config('app.current_team_id', '#{@team_id}', false)")

    held = Queue.new
    release = Queue.new
    t = Thread.new do
      db.synchronize do
        held.push(true)
        release.pop
      end
    end
    held.pop

    result = db[:maps].where(team_id: @team_id).all
    release.push(true)
    t.join
    db.disconnect

    assert_empty result, 'unpinned pool must lose team context on a different connection'
  end

  def test_pinned_connection_keeps_team_context
    app_url = 'postgres://mainline_app:app_password@db:5432/mainline_test'
    db = Sequel.connect(app_url, max_connections: 2)

    db.synchronize do
      db.run("SELECT set_config('app.current_team_id', '#{@team_id}', false)")
      result = db[:maps].where(team_id: @team_id).all

      refute_empty result, 'pinned pool must keep team context on the same connection'
    end
    db.disconnect
  end
end
