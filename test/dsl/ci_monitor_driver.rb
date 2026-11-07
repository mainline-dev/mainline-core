# frozen_string_literal: true

# Loaded after core's test/dsl/drivers/http_driver.rb.

require 'nokogiri'

module CIMonitorDriver
  def monitor_nav_link
    test_id_element('nav-monitor')
  end

  def monitor_shortcut_row
    test_id_element('shortcut-monitor')
  end

  def test_id_element(test_id)
    Nokogiri::HTML(last_response.body).at_css(%([data-test-id="#{test_id}"]))
  end

  # A GitHub installation already connected, straight in the test database.
  def connect_github_installation(team, installation_id)
    TeamInstallation.create(team_id: team.id, provider: 'github', installation_id: installation_id)
  end

  def visit_monitor(team)
    get "/teams/#{team.id}/monitor"
    last_response
  end

  def visit_monitor_install(team, person: nil, oauth_provider: nil, oauth_token: nil,
                            ci_monitor_token: nil, stub_user_installations: nil)
    login_params = {}
    if oauth_provider && person
      login_params = {
        'person_id'      => person.id,
        'oauth_provider' => oauth_provider,
        'oauth_token'    => oauth_token
      }
    end
    if ci_monitor_token
      login_params['person_id'] ||= person&.id
      login_params['ci_monitor_token'] = ci_monitor_token
    end
    post('/_test_login', login_params) if login_params.any?

    if stub_user_installations
      CIMonitor::GithubAPI.stub(:user_installations, ->(_token) { stub_user_installations }) do
        get "/teams/#{team.id}/monitor/install"
        return last_response
      end
    end
    get "/teams/#{team.id}/monitor/install"
    last_response
  end

  def visit_monitor_oauth_callback(team, code:, state: :not_provided, stub_token: nil)
    params = { 'code' => code }
    params['state'] = state.to_s if state != :not_provided && !state.nil?
    if stub_token
      CIMonitor::GithubAPI.stub(:exchange_code_for_token, stub_token) do
        get "/teams/#{team.id}/monitor/oauth/callback", params
        return last_response
      end
    end
    get "/teams/#{team.id}/monitor/oauth/callback", params
    last_response
  end

  def github_app_callback(installation_id:, state: nil, sign: true)
    params = {}
    params['installation_id'] = installation_id.to_s if installation_id
    params['state'] = sign ? SignedState.generate(state.to_s) : state.to_s if state
    get '/github/callback', params
    last_response
  end

  def add_monitored_repo(team, provider_repo_id:, repo_name:, default_branch:, installation_id: nil)
    inst_id = installation_id || TeamInstallation.where(team_id: team.id).get(:installation_id)
    post "/teams/#{team.id}/monitor/repos",
      { 'provider_repo_id' => provider_repo_id.to_s,
        'repo_name'        => repo_name,
        'default_branch'   => default_branch,
        'installation_id'  => inst_id.to_s }
    last_response
  end

  def visit_repo_picker(team, stub_repos:)
    val = stub_repos.is_a?(Exception) ? ->(*) { raise stub_repos } : stub_repos
    CIMonitor::GithubAPI.stub(:installation_repos, val) do
      get "/teams/#{team.id}/monitor/select-repos"
    end
    last_response.body
  end

  def import_repos(team, selected:, stub_repos:, stub_branches: {}, stub_commit_dates: {},
                   stub_commits: [], stub_pulls: [], **)
    params = { 'repo_ids' => selected.map(&:to_s) }
    branch_lookup = ->(_inst_id, full_name) { stub_branches.fetch(full_name, []) }
    date_lookup = ->(_inst_id, _full_name, sha) { stub_commit_dates.fetch(sha, Time.now) }
    commits_lookup = ->(_inst_id, _full_name, _branch, **) { stub_commits }
    pulls_lookup = ->(_inst_id, _full_name, **) { stub_pulls }
    CIMonitor::GithubAPI.stub(:installation_repos, stub_repos) do
      CIMonitor::GithubAPI.stub(:repo_branches, branch_lookup) do
        CIMonitor::GithubAPI.stub(:commit_date, date_lookup) do
          CIMonitor::GithubAPI.stub(:default_branch_commits, commits_lookup) do
            CIMonitor::GithubAPI.stub(:merged_pulls, pulls_lookup) do
              post "/teams/#{team.id}/monitor/repos/import", params
            end
          end
        end
      end
    end
    last_response
  end

  def update_repo_threshold(team, repo, threshold_hours:)
    post "/teams/#{team.id}/monitor/repos/#{repo.id}/threshold",
      'threshold_hours' => threshold_hours.to_s
    last_response
  end

  def remove_monitored_repo(team, repo)
    post "/teams/#{team.id}/monitor/repos/#{repo.id}/remove"
    last_response
  end

  def disconnect_monitor(team)
    post "/teams/#{team.id}/monitor/disconnect"
    last_response
  end

  def mark_spike(team, branch)
    post "/teams/#{team.id}/monitor/branches/#{branch.id}/spike"
    last_response
  end

  def unmark_spike(team, branch)
    post "/teams/#{team.id}/monitor/branches/#{branch.id}/unspike"
    last_response
  end

  def simulate_branch_webhook(repo, event:, branch_name:)
    payload = {
      ref_type:     'branch',
      ref:          branch_name,
      installation: { id: repo.provider_installation_id },
      repository:   { id: repo.provider_repo_id }
    }
    payload[:ref] = "refs/heads/#{repo.default_branch}" if event == 'push'
    body = JSON.generate(payload)
    secret = ENV.fetch('CI_MONITOR_GITHUB_WEBHOOK_SECRET')
    signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, body)}"
    post '/webhooks/github', body,
      'CONTENT_TYPE'             => 'application/json',
      'HTTP_X_GITHUB_EVENT'      => event,
      'HTTP_X_HUB_SIGNATURE_256' => signature
    last_response
  end
end

HttpDriver.include(CIMonitorDriver)
