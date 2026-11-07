# frozen_string_literal: true

class Mainline
  MONITOR_RECENT_WINDOW = CIMonitor::Dashboard::RECENT_WINDOW_HOURS
  MONITOR_DEFAULT_THRESHOLD = CIMonitor::Dashboard::DEFAULT_THRESHOLD_HOURS
  VALID_THRESHOLDS = CIMonitor::Dashboard::VALID_THRESHOLDS
  CI_MONITOR_TOKEN_TTL = 3600

  def team_installations
    TeamInstallation.where(team_id: @team.id)
  end

  def link_installation(inst)
    existing = TeamInstallation.where(
      team_id: @team.id, provider: 'github', installation_id: inst[:id]
    ).first
    return if existing

    TeamInstallation.create(
      team_id: @team.id, provider: 'github',
      installation_id: inst[:id], org_name: inst[:account_login]
    )
  end

  def ci_monitor_oauth_redirect(req)
    client_id = ENV.fetch('CI_MONITOR_GITHUB_APP_CLIENT_ID')
    session['monitor_install_team_id'] = @team.id
    redirect_uri = "#{ENV.fetch('BASE_URL')}/teams/#{@team.id}/monitor/oauth/callback"
    state = SignedState.generate(@team.id)
    req.redirect "https://github.com/login/oauth/authorize?client_id=#{client_id}" \
                 "&redirect_uri=#{Rack::Utils.escape(redirect_uri)}&state=#{Rack::Utils.escape(state)}"
  end

  def load_monitor_dashboard
    @team.refresh
    enqueue_pending_backfills
    @goal = MONITOR_RECENT_WINDOW
    data = CIMonitor::Dashboard.load(@team.id, @goal, @team.timezone, holiday_region: @team.holiday_region)
    @repo_data = data[:repo_data]
    @overall_status = data[:overall_status]
    @total_open = data[:total_open]
    @total_over = data[:total_over]
    @allowed_thresholds = VALID_THRESHOLDS
    @streak_data = @repo_data.to_h { |rd|
      [rd[:repo].id, CIMonitor::StreakStrip.for_repo(rd[:repo].id, @team.timezone, holiday_region: @team.holiday_region)]
    }
    load_overall_streak
    load_org_groups
  end

  def enqueue_pending_backfills
    pending = MonitoredRepo.where(team_id: @team.id, backfill_status: 'pending').all
    pending.each do |repo|
      if ENV['RACK_ENV'] == 'test'
        begin
          CIMonitor::RepoBackfill.call(
            repo_id: repo.id, team_id: @team.id,
            installation_id: repo.provider_installation_id, default_branch: repo.default_branch
          )
        rescue StandardError
          nil
        end
      else
        RepoBackfillJob.perform_async(repo.id, @team.id, repo.provider_installation_id, repo.default_branch)
      end
    end
  end

  def load_overall_streak
    return unless @streak_data.any?

    @heatmap_mode ||= @team.heatmap_mode
    @overall_streak = CIMonitor::StreakStrip.combine(@streak_data.values, mode: @heatmap_mode)
    @overall_streak_count = @overall_streak[:streak]
    @overall_green_days = @overall_streak[:green_days]
    @total_pushes = @streak_data.values.sum { |s| s[:total_pushes] }
    @total_merges = @streak_data.values.sum { |s| s[:total_merges] }
    @overall_branches_over_24h = @streak_data.values.sum { |s| s[:branches_over_24h] }
    all_ages = @streak_data.values.flat_map { |s| s[:merge_ages] }
    @overall_p90_branch_hours = if all_ages.any?
                                  sorted = all_ages.sort
                                  sorted[(sorted.size * 0.9).ceil - 1]
                                end
  end

  def load_org_groups
    grouped = @repo_data.group_by { |rd| rd[:repo].repo_name.split('/').first }
    @org_groups = grouped.map { |org, repos|
      repo_ids = repos.map { |rd| rd[:repo].id }
      org_streaks = @streak_data.slice(*repo_ids).values
      org_streak = org_streaks.any? ? CIMonitor::StreakStrip.combine(org_streaks, mode: @heatmap_mode || 'max') : nil
      org_statuses = repos.map { |rd| rd[:status] }
      { org: org, repos: repos, streak: org_streak, status: CIMonitor::Status.overall(org_statuses) }
    }
  end

  def monitor_respond(req)
    if htmx?(req)
      load_monitor_dashboard
      render('teams/monitor/dashboard')
    else
      req.redirect "/teams/#{@team.id}/monitor"
    end
  end

  hash_branch('teams', 'monitor') do |r|
    r.is do
      r.get do
        if team_installations.any?
          load_monitor_dashboard
          @page_title = 'CI Monitor - Mainline'
          view 'dashboard'
        else
          @page_title = 'CI Monitor - Mainline'
          view 'connect'
        end
      end
    end

    r.post 'disconnect' do
      DB.transaction do
        MonitoredRepo.where(team_id: @team.id).each do |repo|
          IntegrationEvent.where(monitored_repo_id: repo.id).delete
          TrackedBranch.where(monitored_repo_id: repo.id).delete
        end
        MonitoredRepo.where(team_id: @team.id).delete
        team_installations.delete
      end
      url = "/teams/#{@team.id}/monitor"
      if htmx?(r)
        response['HX-Redirect'] = url
        ''
      else
        r.redirect url
      end
    end

    r.post 'heatmap-mode' do
      mode = typecast_params.nonempty_str('mode')
      @team.update(heatmap_mode: mode) if %w[max average].include?(mode)
      monitor_respond(r)
    end

    r.get 'install' do
      if session['ci_monitor_token']
        token_age = Time.now.to_i - session['ci_monitor_token_at'].to_i
        if token_age > CI_MONITOR_TOKEN_TTL
          session.delete('ci_monitor_token')
          session.delete('ci_monitor_token_at')
        end
      end
      if session['ci_monitor_token']
        begin
          app_id = ENV.fetch('CI_MONITOR_GITHUB_APP_ID').to_i
          all_installations = CIMonitor::GithubAPI.user_installations(session['ci_monitor_token'])
          matching = all_installations.select { |i| i[:app_id] == app_id }
          matching_ids = matching.map { |i| i[:id] }
          linked_ids = team_installations.select_map(:installation_id)
          stale_ids = linked_ids - matching_ids
          TeamInstallation.where(team_id: @team.id, installation_id: stale_ids).delete if stale_ids.any?

          unlinked = matching.reject { |i| linked_ids.include?(i[:id]) }

          @install_state = SignedState.generate(@team.id)

          if unlinked.any?
            @unlinked_installations = unlinked
            next view('installation_picker')
          end

          next r.redirect("/teams/#{@team.id}/monitor") if matching.empty?

          @all_linked = true
          @app_slug = ENV.fetch('CI_MONITOR_GITHUB_APP_SLUG')
          next view('installation_picker')
        rescue CIMonitor::GithubAPI::Error
          session.delete('ci_monitor_token')
          session.delete('ci_monitor_token_at')
        end
      end
      ci_monitor_oauth_redirect(r)
    end

    r.on 'oauth' do
      r.get 'callback' do
        code = r.params['code']
        next r.redirect("/teams/#{@team.id}/monitor") unless code

        verified_team_id = SignedState.verify(r.params['state'])
        unless verified_team_id == @team.id
          flash['error'] = 'Invalid OAuth state. Please try again.'
          next r.redirect("/teams/#{@team.id}/monitor")
        end

        begin
          token = CIMonitor::GithubAPI.exchange_code_for_token(code)
          session['ci_monitor_token'] = token
          session['ci_monitor_token_at'] = Time.now.to_i
          r.redirect "/teams/#{@team.id}/monitor/install"
        rescue CIMonitor::GithubAPI::Error => e
          flash['error'] = "GitHub authorization failed: #{e.message}"
          r.redirect "/teams/#{@team.id}/monitor"
        end
      end
    end

    r.post 'install' do
      installation_id = typecast_params.pos_int('installation_id')
      account_login = typecast_params.nonempty_str('account_login')
      if installation_id && session['ci_monitor_token']
        app_id = ENV.fetch('CI_MONITOR_GITHUB_APP_ID').to_i
        owned = CIMonitor::GithubAPI.user_installations(session['ci_monitor_token'])
        if owned.any? { |i| i[:app_id] == app_id && i[:id] == installation_id }
          link_installation({ id: installation_id, account_login: account_login })
        end
      end
      r.redirect "/teams/#{@team.id}/monitor"
    end

    r.on 'branches' do
      r.on String do |branch_id|
        next unless branch_id.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)

        branch = TrackedBranch[branch_id]
        next unless branch

        repo = MonitoredRepo.where(id: branch.monitored_repo_id, team_id: @team.id).first
        next unless repo

        r.post 'spike' do
          branch.update(status: 'spike')
          monitor_respond(r)
        end

        r.post 'unspike' do
          branch.update(status: 'open')
          monitor_respond(r)
        end
      end
    end

    r.get 'select-repos' do
      @installations = team_installations.all
      next r.redirect("/teams/#{@team.id}/monitor") if @installations.empty?

      existing_ids = MonitoredRepo.where(team_id: @team.id).select_map(:provider_repo_id)
      @available_repos = []
      @installations.each do |ti|
        repos = CIMonitor::GithubAPI.installation_repos(ti.installation_id)
        repos.each do |repo|
          next if existing_ids.include?(repo[:id])

          repo[:installation_id] = ti.installation_id
          @available_repos << repo
        end
      end
      view 'select_repos'
    rescue CIMonitor::GithubAPI::Error
      flash['warning'] = 'Could not fetch repos from GitHub. Try again.'
      r.redirect "/teams/#{@team.id}/monitor"
    end

    r.on 'repos' do
      r.post 'import' do
        repo_ids = typecast_params.array(:pos_int, 'repo_ids') || []
        installation_ids = team_installations.select_map(:installation_id)
        repos_to_backfill = []
        installation_ids.each do |inst_id|
          available = CIMonitor::GithubAPI.installation_repos(inst_id)
          available.each do |repo_data|
            next unless repo_ids.include?(repo_data[:id])

            default_branch = repo_data[:default_branch] || 'main'
            DB.transaction(savepoint: true) do
              repo = MonitoredRepo.create(
                team_id:                  @team.id,
                provider_installation_id: inst_id,
                provider_repo_id:         repo_data[:id],
                repo_name:                repo_data[:full_name],
                default_branch:           default_branch,
                threshold_hours:          MONITOR_DEFAULT_THRESHOLD,
                backfill_status:          'pending'
              )
              repos_to_backfill << { repo_id: repo.id, default_branch: default_branch, inst_id: inst_id }
            end
          rescue Sequel::UniqueConstraintViolation
            next
          end
        rescue CIMonitor::GithubAPI::Error
          next
        end
        team_id = @team.id
        if ENV['RACK_ENV'] == 'test'
          repos_to_backfill.each do |entry|
            CIMonitor::RepoBackfill.call(
              repo_id: entry[:repo_id], team_id: team_id,
              installation_id: entry[:inst_id], default_branch: entry[:default_branch]
            )
          rescue StandardError
            nil
          end
        else
          DB.after_commit do
            repos_to_backfill.each do |entry|
              RepoBackfillJob.perform_async(entry[:repo_id], team_id, entry[:inst_id], entry[:default_branch])
            end
          end
        end
        r.redirect "/teams/#{@team.id}/monitor"
      end

      r.is do
        r.post do
          provider_repo_id = typecast_params.pos_int('provider_repo_id')
          repo_name = typecast_params.nonempty_str('repo_name')
          default_branch = typecast_params.nonempty_str('default_branch') || 'main'
          inst_id = typecast_params.pos_int('installation_id')
          owned_ids = team_installations.select_map(:installation_id)
          next r.redirect("/teams/#{@team.id}/monitor") unless inst_id && provider_repo_id && repo_name
          next r.redirect("/teams/#{@team.id}/monitor") unless owned_ids.include?(inst_id)

          DB.transaction(savepoint: true) do
            MonitoredRepo.create(
              team_id:                  @team.id,
              provider_installation_id: inst_id,
              provider_repo_id:         provider_repo_id,
              repo_name:                repo_name,
              default_branch:           default_branch,
              threshold_hours:          MONITOR_DEFAULT_THRESHOLD
            )
          end
          r.redirect "/teams/#{@team.id}/monitor"
        rescue Sequel::UniqueConstraintViolation, Sequel::ValidationFailed
          r.redirect "/teams/#{@team.id}/monitor"
        end
      end

      r.on String do |repo_id|
        next unless repo_id.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)

        repo = MonitoredRepo.where(id: repo_id, team_id: @team.id).first
        next unless repo

        r.post 'remove' do
          DB.transaction do
            IntegrationEvent.where(monitored_repo_id: repo.id).delete
            TrackedBranch.where(monitored_repo_id: repo.id).delete
            repo.destroy
          end
          if htmx?(r)
            response['HX-Retarget'] = '#main'
            response['HX-Reswap'] = 'innerHTML'
          end
          monitor_respond(r)
        end

        r.post 'threshold' do
          hours = typecast_params.pos_int('threshold_hours')
          repo.update(threshold_hours: hours) if VALID_THRESHOLDS.include?(hours)
          monitor_respond(r)
        end
      end
    end
  end
end
