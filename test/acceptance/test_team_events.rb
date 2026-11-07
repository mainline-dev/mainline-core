# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

# Core announces when a team is created or deleted, so code that keeps its
# own records per team can follow along.
describe 'Team events' do
  include MainlineDSL

  before do
    @heard = []
    @subscriptions = %i[team_created team_deleted].map { |event|
      CoreEvents.subscribe(event) { |payload| @heard << [event, payload] }
    }
    @alice = Person.create(name: 'Alice', email: 'alice@acme.co', email_verified_at: Time.now)
    login_as(@alice)
  end

  after { @subscriptions.each { |sub| CoreEvents.unsubscribe(sub) } }

  it 'announces a new team with its creator' do
    submit_create_team(team_name: 'Acme')
    team = Team.where(name: 'Acme').first

    assert_includes @heard, [:team_created, { team_id: team.id, creator_id: @alice.id }]
  end

  it 'announces a deleted team' do
    submit_create_team(team_name: 'Acme')
    team = Team.where(name: 'Acme').first

    DeleteTeam.call(team: team)

    assert_includes @heard, [:team_deleted, { team_id: team.id }]
  end
end
