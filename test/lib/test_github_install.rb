# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/github_install'

describe GithubInstall do
  cover 'GithubInstall*'

  before do
    @team = Team.create(name: 'Monitor Team')
    SetTeamContext.call(@team.id)
    @session = {}
  end

  def app_id
    ENV.fetch('CI_MONITOR_GITHUB_APP_ID').to_i
  end

  it 'finishes the install this session started, for its team' do
    state = GithubInstall.start(@session, @team.id)

    assert_equal @team.id, GithubInstall.finish(@session, state)
  end

  it 'starts each install with a new state, too long to guess' do
    state = GithubInstall.start({}, @team.id)

    refute_equal state, GithubInstall.start({}, @team.id)
    assert_operator state.length, :>=, 43
  end

  it 'finishes an install once' do
    state = GithubInstall.start(@session, @team.id)
    GithubInstall.finish(@session, state)

    assert_nil GithubInstall.finish(@session, state)
  end

  it 'finishes nothing for a state this session did not start, or no state' do
    state = GithubInstall.start(@session, @team.id)

    assert_nil GithubInstall.finish(@session, "#{state}x")
    assert_nil GithubInstall.finish({}, state)
    GithubInstall.start(@session, @team.id)

    assert_nil GithubInstall.finish(@session, nil)
    assert_nil GithubInstall.finish(@session, '')
  end

  it 'forgets the install it started when given the wrong state' do
    state = GithubInstall.start(@session, @team.id)
    GithubInstall.finish(@session, 'wrong')

    assert_nil GithubInstall.finish(@session, state)
  end

  it "keeps the person's GitHub sign-in for an hour, then forgets it" do
    now = Time.utc(2030, 1, 1, 12)
    @session['ci_monitor_token'] = 'alice-token'
    @session['ci_monitor_token_at'] = (now - 3600).to_i

    assert_equal 'alice-token', GithubInstall.token(@session, now: now - 600)
    assert_equal 'alice-token', GithubInstall.token(@session, now: now)
    assert_nil GithubInstall.token(@session, now: now + 1)
    assert_empty @session
  end

  it 'has no sign-in to give when there is none' do
    assert_nil GithubInstall.token({})
  end

  it 'finds an installation only in what GitHub lists for the person, for this app' do
    listed = [{ app_id: app_id, id: 1, account_login: 'mine' }, { app_id: app_id + 1, id: 2, account_login: 'other app' }]

    CIMonitor::GithubAPI.stub(:user_installations, ->(token) { token == 'alice-token' ? listed : [] }) do
      assert_equal listed.first, GithubInstall.seen('alice-token', 1)
      assert_nil GithubInstall.seen('alice-token', 2)
      assert_nil GithubInstall.seen('alice-token', 3)
    end
  end

  it 'links an installation once, named as GitHub names it' do
    installation = { app_id: app_id, id: 1, account_login: 'mine' }

    GithubInstall.link(@team.id, installation)
    GithubInstall.link(@team.id, installation)

    assert_equal [[1, 'mine', 'github']],
      TeamInstallation.where(team_id: @team.id).select_map(%i[installation_id org_name provider])
  end

  it 'links a second installation to a team that has one' do
    GithubInstall.link(@team.id, { id: 1, account_login: 'mine' })

    GithubInstall.link(@team.id, { id: 2, account_login: 'also mine' })

    assert_equal [1, 2], TeamInstallation.where(team_id: @team.id).order(:installation_id).select_map(:installation_id)
  end

  it 'links the same installation to another team on its own' do
    other = Team.create(name: 'Other Team')
    SetTeamContext.call(other.id)
    GithubInstall.link(other.id, { id: 1, account_login: 'mine' })
    SetTeamContext.call(@team.id)

    GithubInstall.link(@team.id, { id: 1, account_login: 'mine' })

    assert_equal 1, TeamInstallation.where(team_id: @team.id).count
  end
end
