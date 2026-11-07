# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/set_team_context'

describe SetTeamContext do
  cover 'SetTeamContext*'
  def current_team_id
    DB.get(Sequel.lit("current_setting('app.current_team_id', true)"))
  end

  it 'sets the team id for the current transaction' do
    team = Team.create(name: 'Test')
    SetTeamContext.call(team.id)

    assert_equal team.id, current_team_id
  end

  it 'treats SQL injection via quote escape as a literal value' do
    malicious = "'; DROP TABLE events; --"
    SetTeamContext.call(malicious)

    assert_equal malicious, current_team_id
    assert_predicate DB[Sequel[:pg_catalog][:pg_tables]].where(tablename: 'events'), :any?
  end

  it 'treats SQL injection via boolean logic as a literal value' do
    malicious = "' OR '1'='1"
    SetTeamContext.call(malicious)

    assert_equal malicious, current_team_id
  end

  it 'treats SQL injection via UNION SELECT as a literal value' do
    malicious = "' UNION SELECT email_ciphertext FROM people --"
    SetTeamContext.call(malicious)

    assert_equal malicious, current_team_id
  end

  it 'treats SQL injection via stacked queries as a literal value' do
    malicious = "x'; UPDATE teams SET name='hacked'; --"
    SetTeamContext.call(malicious)

    assert_equal malicious, current_team_id
    refute_predicate Team.where(name: 'hacked'), :any?
  end
end
