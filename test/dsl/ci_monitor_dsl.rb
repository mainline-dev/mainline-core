# frozen_string_literal: true

# Loaded after core's test/dsl/mainline_dsl.rb.

require_relative 'ci_monitor_driver'

module CIMonitorDSL
  def assert_monitor_in_nav(team = @team)
    link = driver.monitor_nav_link

    refute_nil link, 'Expected the team nav to link to CI Monitor'
    assert_equal "/teams/#{team.id}/monitor", link['href']
  end

  def assert_on_monitor(team = @team)
    assert driver.on_path?("/teams/#{team.id}/monitor"), 'Expected to be on CI Monitor'
  end

  def assert_monitor_shortcut_listed(key:)
    row = driver.monitor_shortcut_row

    refute_nil row, 'Expected the shortcut cheatsheet to list CI Monitor'
    assert_equal ['g', key], row.css('kbd').map(&:text)
  end

  def connect_github_installation(installation_id, team: @team)
    driver.connect_github_installation(team, installation_id)
  end

  def visit_monitor(team = @team)
    driver.visit_monitor(team)
  end

  def visit_monitor_install(team = @team, oauth_provider: nil, oauth_token: nil,
                            ci_monitor_token: nil, stub_user_installations: nil)
    driver.visit_monitor_install(
      team,
      person:                  @_login_person,
      oauth_provider:          oauth_provider,
      oauth_token:             oauth_token,
      ci_monitor_token:        ci_monitor_token,
      stub_user_installations: stub_user_installations
    )
  end

  def visit_monitor_oauth_callback(team = @team, code:, state: :not_provided, stub_token: nil)
    driver.visit_monitor_oauth_callback(team, code: code, state: state, stub_token: stub_token)
  end

  def github_app_callback(installation_id:, state:, sign: true)
    driver.github_app_callback(installation_id: installation_id, state: state, sign: sign)
  end

  def add_monitored_repo(team = @team, provider_repo_id:, repo_name:, default_branch:, installation_id: nil)
    driver.add_monitored_repo(
      team, provider_repo_id: provider_repo_id, repo_name: repo_name,
      default_branch: default_branch, installation_id: installation_id
    )
  end

  def visit_repo_picker(team = @team, stub_repos:)
    driver.visit_repo_picker(team, stub_repos: stub_repos)
  end

  def import_repos(team = @team, selected:, stub_repos:, stub_branches: {},
                   stub_commit_dates: {}, stub_commits: [], stub_pulls: [], **)
    driver.import_repos(
      team, selected: selected, stub_repos: stub_repos,
      stub_branches: stub_branches, stub_commit_dates: stub_commit_dates,
      stub_commits: stub_commits, stub_pulls: stub_pulls
    )
  end

  def update_repo_threshold(repo, threshold_hours:, team: @team)
    driver.update_repo_threshold(team, repo, threshold_hours: threshold_hours)
  end

  def remove_monitored_repo(repo, team: @team)
    driver.remove_monitored_repo(team, repo)
  end

  def disconnect_monitor(team = @team)
    driver.disconnect_monitor(team)
  end

  def simulate_branch_webhook(repo, event:, branch_name: 'feature/x')
    driver.simulate_branch_webhook(repo, event: event, branch_name: branch_name)
  end

  def mark_spike(branch, team: @team)
    driver.mark_spike(team, branch)
  end

  def unmark_spike(branch, team: @team)
    driver.unmark_spike(team, branch)
  end

  def assert_open_branches(body, expected_count)
    assert_includes body, "data-test-id=\"open-branch-count\" data-count=\"#{expected_count}\""
  end
end
