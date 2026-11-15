# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/activation'

describe Activation do
  cover 'Activation*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
  end

  def on(ci_monitor: true)
    Activation.for(@team, ci_monitor: ci_monitor).select { |_, connected| connected }.keys
  end

  it 'lists the connections in order, none of them on for a new team' do
    assert_equal %i[museum github webhook agent], Activation.for(@team, ci_monitor: true).keys
    assert_empty on
  end

  it 'counts the backlog in once a ticket is in the museum' do
    MuseumItem.create(team_id: @team.id, source_key: 'SHOP-1', issue_type: 'Story', summary: 'Pay by card')

    assert_equal [:museum], on
  end

  it 'leaves the backlog out for stories proposed from a specification' do
    MuseumItem.create(team_id: @team.id, source_key: 'SPEC-1', issue_type: 'Story', summary: 'Pay by card',
      source: 'mainline')

    assert_empty on
  end

  it 'counts GitHub once a CI Monitor installation is linked to the team' do
    TeamInstallation.create(team_id: @team.id, provider: 'github', installation_id: 1)

    assert_equal [:github], on
  end

  it 'counts the deploy webhook once the team has a token' do
    @team.update(webhook_token: 'digest')

    assert_equal [:webhook], on
  end

  it 'counts the coding agent once the team has an MCP token' do
    @team.update(mcp_token: 'digest')

    assert_equal [:agent], on
  end

  it 'leaves GitHub out on an install without the CI Monitor' do
    assert_equal %i[museum webhook agent], Activation.for(@team, ci_monitor: false).keys
  end

  it 'asks the install whether the CI Monitor is on unless told' do
    was = CIMonitorSetup::SETTINGS.to_h { |name| [name, ENV.fetch(name, nil)] }
    CIMonitorSetup::SETTINGS.each { |name| ENV[name] = 'disabled' }

    assert_equal %i[museum webhook agent], Activation.for(@team).keys
  ensure
    was.each { |name, value| ENV[name] = value }
  end
end
