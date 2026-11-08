# frozen_string_literal: true

ENV['MAINLINE_SEED'] = '1'
ENV['RACK_ENV'] ||= 'development'

raise 'DevSeed can only run in development' unless ENV['RACK_ENV'] == 'development'

require_relative '../app'
require 'minitest'
require 'timecop'
require_relative '../test/dsl/mainline_dsl'
require_relative '../test/dsl/ci_monitor_dsl'
require_relative 'dev_seed_helpers'
require_relative 'team_persona'
require_relative 'name_pools'
require_relative 'simulated_team'

class DevSeed # rubocop:disable Metrics/ClassLength
  include MainlineDSL
  include CIMonitorDSL
  include Minitest::Assertions
  include DevSeedHelpers

  attr_accessor :assertions

  TEAM_NAME = 'Acme Product Team'
  START_DATE = Time.utc(2026, 3, 16, 9, 0, 0)

  def initialize
    @assertions = 0
  end

  def self.call
    new.run
  ensure
    Timecop.return
    ENV.delete('MAINLINE_SEED')
  end

  GROWING_PAINS = TeamPersona::LOW.to_h.merge(team_size: 13..15).then { |h| TeamPersona.new(**h) }

  PERSONA_TEAMS = {
    'XP Squad'          => TeamPersona::HIGH,
    'Steady Ship Crew'  => TeamPersona::MEDIUM,
    'Growing Pains Inc' => GROWING_PAINS
  }.freeze

  def run
    if Team.where(name: TEAM_NAME).any?
      puts "Seed team '#{TEAM_NAME}' already exists. Run `rake dev_teardown` first."
      return
    end

    if Team.any? || Person.any?
      puts 'Development database is not empty. Run `rake dev_teardown` or `rake dev_bounce && rake dev_up` first.'
      return
    end

    puts 'Seeding development database...'
    Timecop.freeze(START_DATE)

    create_team_and_people
    create_map_structure
    simulate_work
    seed_story_notes

    Timecop.return

    seed_persona_teams
    seed_ci_monitor
    seed_persona_ci_monitors

    puts "\nDone. URLs written to tmp/dev_seed.txt"
    write_seed_urls
  end

  def seed_persona_teams
    PERSONA_TEAMS.each do |name, persona|
      current = name != 'XP Squad'
      SimulatedTeam.new(persona, name: name, current_work: current).seed
    end
    xp_team = Team.where(name: 'XP Squad').first
    SimulatedTeam.new(
      TeamPersona::HIGH, name: 'XP Squad', team: xp_team,
      map_name: 'Long Running Project', duration: 400
    ).seed
  end

  def seed_ci_monitor
    DB["SELECT set_config('app.current_team_id', ?, false)", @team.id.to_s].get
    connect_github_installation(55555)
    seed_monitored_repos
    seed_tracked_branches
    seed_integration_events_mixed
    seed_green_monitor_team
    seed_red_monitor_team
    puts '  Created CI Monitor data (3 teams: mixed, all-green, all-red)'
  end

  def seed_monitored_repos
    DB["SELECT set_config('app.current_team_id', ?, false)", @team.id.to_s].get
    [[1001, 'acme/webapp'], [1002, 'acme/api'], [1003, 'acme/docs']].each do |id, name|
      MonitoredRepo.create(
        team_id: @team.id, provider_installation_id: 55555,
        provider_repo_id: id, repo_name: name, default_branch: 'main',
        threshold_hours: 48
      )
    end
    MonitoredRepo.where(provider_repo_id: [1001, 1002]).each do |r|
      r.update(last_push_at: Time.now - 3600)
    end
  end

  def seed_tracked_branches
    webapp = MonitoredRepo.where(provider_repo_id: 1001).first
    api = MonitoredRepo.where(provider_repo_id: 1002).first
    seed_branch(webapp, 'feature/new-header', 4 * 3600)
    seed_branch(api, 'feature/stale-endpoint', 5 * 24 * 3600)
    seed_branch(api, 'fix/quick-patch', 2 * 3600)
  end

  def seed_branch(repo, name, age_seconds)
    branch = TrackedBranch.create(monitored_repo_id: repo.id, branch_name: name, status: 'open')
    DB[:tracked_branches].where(id: branch.id).update(created_at: Time.now - age_seconds)
  end

  def seed_integration_events_mixed
    webapp = MonitoredRepo.where(provider_repo_id: 1001).first
    api = MonitoredRepo.where(provider_repo_id: 1002).first
    today = Date.today

    84.times do |i|
      date = today - (83 - i)
      next if [0, 6].include?(date.wday)

      t = Time.utc(date.year, date.month, date.day, 14, 0, 0)

      seed_push_event(webapp, t) unless [5, 18, 40].include?(i)

      next if i < 14 || (i % 3).zero?

      if (i % 7).zero?
        seed_stale_merge_event(api, t, i)
      else
        seed_push_event(api, t)
      end
    end
  end

  def seed_green_monitor_team
    green_team = Team.create(name: 'Green CI Team')
    DB["SELECT set_config('app.current_team_id', ?, false)", green_team.id.to_s].get
    person = Person.create(name: 'Grace Green', email: 'grace@green.dev')
    TeamMembership.create(team_id: green_team.id, person_id: person.id)
    connect_github_installation(66666, team: green_team)
    green_team.update(creator_id: person.id)
    repos = [[2001, 'green/frontend'], [2002, 'green/backend']].map { |id, name|
      MonitoredRepo.create(
        team_id: green_team.id, provider_installation_id: 66666,
        provider_repo_id: id, repo_name: name, default_branch: 'main',
        last_push_at: Time.now - 1800, threshold_hours: 24
      )
    }
    seed_integration_events_green(repos)
  end

  def seed_integration_events_green(repos)
    today = Date.today
    84.times do |i|
      date = today - (83 - i)
      next if [0, 6].include?(date.wday)

      t = Time.utc(date.year, date.month, date.day, 10, 0, 0)
      repos.each { |repo| seed_push_event(repo, t) }
      seed_push_event(repos.first, t + (4 * 3600)) if (i % 2).zero?
    end
  end

  def seed_red_monitor_team
    red_team = Team.create(name: 'Red CI Team')
    DB["SELECT set_config('app.current_team_id', ?, false)", red_team.id.to_s].get
    person = Person.create(name: 'Rita Red', email: 'rita@red.dev')
    TeamMembership.create(team_id: red_team.id, person_id: person.id)
    connect_github_installation(77777, team: red_team)
    red_team.update(creator_id: person.id)
    repos = [[3001, 'red/monolith'], [3002, 'red/services']].map { |id, name|
      repo = MonitoredRepo.create(
        team_id: red_team.id, provider_installation_id: 77777,
        provider_repo_id: id, repo_name: name, default_branch: 'main',
        last_push_at: Time.now - 3600, threshold_hours: 24
      )
      seed_branch(repo, "feature/long-lived-#{id}", 6 * 24 * 3600)
      seed_branch(repo, "feature/another-stale-#{id}", 4 * 24 * 3600)
      repo
    }
    seed_integration_events_red(repos)
  end

  def seed_integration_events_red(repos)
    today = Date.today
    84.times do |i|
      date = today - (83 - i)
      next if [0, 6].include?(date.wday)

      t = Time.utc(date.year, date.month, date.day, 14, 0, 0)

      repos.each do |repo|
        next if (i % 4).zero? || (i % 5).zero?

        if (i % 6).zero?
          seed_stale_merge_event(repo, t, i)
        else
          seed_push_event(repo, t)
        end
      end
    end
  end

  def seed_push_event(repo, time)
    IntegrationEvent.create(
      monitored_repo_id: repo.id, event_type: 'push', occurred_at: time
    )
  end

  def seed_stale_merge_event(repo, time, index)
    branch = TrackedBranch.create(
      monitored_repo_id: repo.id, branch_name: "seed-late-#{repo.id}-#{index}",
      status: 'merged', merged_at: time
    )
    DB[:tracked_branches].where(id: branch.id).update(created_at: time - (3 * 86_400))
    IntegrationEvent.create(
      monitored_repo_id: repo.id, event_type: 'merge',
      occurred_at: time, tracked_branch_id: branch.id
    )
  end

  def seed_persona_ci_monitors
    seed_xp_squad_monitor
    seed_steady_ship_monitor
    seed_growing_pains_monitor
    puts '  Added CI Monitor data to persona teams'
  end

  def seed_persona_monitor_repos(team, installation_id, repo_defs, threshold: 24)
    DB["SELECT set_config('app.current_team_id', ?, false)", team.id.to_s].get
    connect_github_installation(installation_id, team: team)
    repo_defs.map { |id, name|
      MonitoredRepo.create(
        team_id: team.id, provider_installation_id: installation_id,
        provider_repo_id: id, repo_name: name, default_branch: 'main',
        threshold_hours: threshold
      )
    }
  end

  def seed_xp_squad_monitor
    team = Team.where(name: 'XP Squad').first
    return unless team

    repos = seed_persona_monitor_repos(team, 10001, [[4001, 'xp-squad/app'], [4002, 'xp-squad/platform']])
    repos.each { |r| r.update(last_push_at: Time.now - (2 * 3600)) }
    seed_branch(repos.first, 'feature/current-work', 6 * 3600)
    seed_xp_squad_events(repos)
  end

  def seed_xp_squad_events(repos)
    today = Date.today
    84.times do |i|
      date = today - (83 - i)
      next if [0, 6].include?(date.wday)

      t = Time.utc(date.year, date.month, date.day, 10, 0, 0)
      repos.each { |repo| seed_push_event(repo, t) unless i == 42 }
      seed_push_event(repos.last, t + (4 * 3600)) if (i % 2).zero?
    end
  end

  def seed_steady_ship_monitor
    team = Team.where(name: 'Steady Ship Crew').first
    return unless team

    repos = seed_persona_monitor_repos(team, 10002, [[5001, 'steady-ship/web'], [5002, 'steady-ship/api']])
    repos.each { |r| r.update(last_push_at: Time.now - (4 * 3600)) }
    seed_branch(repos.first, 'feature/dashboard-rework', 8 * 3600)
    seed_branch(repos.last, 'feature/api-v2-endpoint', 30 * 3600)
    seed_steady_ship_events(repos)
  end

  def seed_steady_ship_events(repos)
    today = Date.today
    84.times do |i|
      date = today - (83 - i)
      next if [0, 6].include?(date.wday)

      t = Time.utc(date.year, date.month, date.day, 14, 0, 0)
      seed_steady_ship_web_event(repos.first, t, i)
      seed_steady_ship_api_event(repos.last, t, i)
    end
  end

  def seed_steady_ship_web_event(repo, time, index)
    return if (index % 6).zero? || [15, 33, 55].include?(index)

    if (index % 9).zero?
      seed_stale_merge_event(repo, time, index)
    else
      seed_push_event(repo, time)
    end
  end

  def seed_steady_ship_api_event(repo, time, index)
    return if index < 20 || (index % 5).zero?

    if (index % 11).zero?
      seed_stale_merge_event(repo, time, index)
    else
      seed_push_event(repo, time)
    end
  end

  def seed_growing_pains_monitor
    team = Team.where(name: 'Growing Pains Inc').first
    return unless team

    repos = seed_persona_monitor_repos(team, 10003,
      [[6001, 'growing-pains/monolith'], [6002, 'growing-pains/services'], [6003, 'growing-pains/tools']])
    repos[0].update(last_push_at: Time.now - (28 * 3600))
    repos[1].update(last_push_at: Time.now - (6 * 3600))
    seed_branch(repos[0], 'feature/auth-rewrite', 6 * 24 * 3600)
    seed_branch(repos[0], 'feature/db-migration', 3 * 24 * 3600)
    seed_branch(repos[1], 'feature/new-api', 36 * 3600)
    seed_branch(repos[2], 'feature/ci-pipeline', 5 * 24 * 3600)
    seed_growing_pains_events(repos)
  end

  def seed_growing_pains_events(repos)
    today = Date.today
    84.times do |i|
      date = today - (83 - i)
      next if [0, 6].include?(date.wday)

      t = Time.utc(date.year, date.month, date.day, 14, 0, 0)
      seed_growing_monolith_event(repos[0], t, i)
      seed_growing_services_event(repos[1], t, i)
      seed_push_event(repos[2], t) if i > 40 && i.even?
    end
  end

  def seed_growing_monolith_event(repo, time, index)
    return if (index % 3).zero? || (index % 5).zero?

    if (index % 4).zero?
      seed_stale_merge_event(repo, time, index)
    else
      seed_push_event(repo, time)
    end
  end

  def seed_growing_services_event(repo, time, index)
    return if (index % 2).zero? || (index % 7).zero?

    if (index % 5).zero?
      seed_stale_merge_event(repo, time, index)
    else
      seed_push_event(repo, time)
    end
  end

  private

  def write_seed_urls
    FileUtils.mkdir_p('tmp')
    File.open('tmp/dev_seed.txt', 'w') do |f|
      f.puts 'Teams:'
      Team.order(:name).each do |team|
        f.puts "  #{team.name}: http://localhost:3000/teams/#{team.id}"
      end
      f.puts "\nLogin as:"
      Person.order(:name).each do |person|
        f.puts "  #{person.name}: http://localhost:3000/_test_login?person_id=#{person.id}"
      end
    end
  end

  def create_team_and_people
    setup_team(name: TEAM_NAME)
    DB["SELECT set_config('app.current_team_id', ?, false)", @team.id.to_s].get
    @owner = Person.create(name: 'Acme Owner', email: 'owner@acme.dev')
    TeamMembership.create(team_id: @team.id, person_id: @owner.id, working: false)
    @team.update(creator_id: @owner.id)
    @people = {
      alice: add_person(name: 'Alice Chen',   email: 'alice@acme.dev'),
      bob:   add_person(name: 'Bob Park',     email: 'bob@acme.dev'),
      carol: add_person(name: 'Carol Diaz',   email: 'carol@acme.dev'),
      dan:   add_person(name: 'Dan Okafor',   email: 'dan@acme.dev'),
      eve:   add_person(name: 'Eve Lindgren', email: 'eve@acme.dev')
    }
    puts "  Created team with #{@people.size} people + account holder"
  end

  def create_map_structure
    create_map(name: 'Acme Onboarding')
    @customer = create_persona('Customer')
    @admin    = create_persona('Admin')
    @signup   = create_activity('Sign up',        for_personas: [@customer])
    @profile  = create_activity('Manage profile', for_personas: [@customer])
    @billing  = create_activity('Billing',        for_personas: [@customer, @admin])
    @settings = create_activity('Team settings',  for_personas: [@admin])
    @tasks = {
      register:    create_task('Register account', under_activity: @signup),
      verify:      create_task('Verify email',     under_activity: @signup),
      edit:        create_task('Edit profile',     under_activity: @profile),
      avatar:      create_task('Upload avatar',    under_activity: @profile),
      plans:       create_task('Choose plan',      under_activity: @billing),
      payment:     create_task('Payment method',   under_activity: @billing),
      permissions: create_task('Permissions',      under_activity: @settings),
      config:      create_task('Configuration',    under_activity: @settings)
    }
    puts "  Created map: #{@map.name} (4 activities, 8 steps)"
  end

  def simulate_work
    phase_1_quick_wins
    phase_2_ramp_up
    phase_3_first_ensemble
    phase_4_fast_turnaround
    phase_5_solo_and_churn
    phase_6_final_rotation
    phase_7_stale_and_backlog
    puts "  Created #{Story.where(map_id: @map.id).count} stories across 30 days"
  end

  # Days 0-2: A+B, C+D — two fast releases (2d each, 1 deploy)
  def phase_1_quick_wins
    advance_days(0)
    start_paired('Registration form', @tasks[:register], :alice, :bob)
    start_paired('Verification email', @tasks[:verify], :carol, :dan)
    advance_days(1)
    deploy('Registration form')
    deploy('Verification email')
    tag_decoupling('Registration form', strategy: 'flag', label: 'FF_NEW_REG_FLOW')
    advance_days(1)
    release('Registration form')
    release('Verification email')
  end

  # Days 2-7: B+C#1, A+E, A+D — varied cycles, outlier single-deploy release
  def phase_2_ramp_up
    start_paired('OAuth provider', @tasks[:register], :bob, :carol)
    start_paired('Display name field', @tasks[:edit], :alice, :eve)
    advance_days(1)
    deploy('OAuth provider')
    advance_days(1)
    deploy('Display name field')
    release('Display name field')
    start_paired('Profile photo', @tasks[:avatar], :alice, :dan)
    advance_days(1)
    deploy('OAuth provider')
    deploy('Profile photo')
    advance_days(2)
    release('OAuth provider')
    release('Profile photo')
  end

  # Days 7-11: D+E, ensemble(A+B+C), D+E — first ensemble session
  def phase_3_first_ensemble
    start_paired('Token validation', @tasks[:verify], :dan, :eve)
    start_ensemble('Plan comparison', @tasks[:plans], :alice, :bob, :carol)
    advance_days(1)
    deploy('Token validation')
    advance_days(1)
    release('Token validation')
    deploy('Plan comparison')
    start_paired('Card details', @tasks[:payment], :dan, :eve)
    advance_days(1)
    deploy('Card details')
    advance_days(1)
    deploy('Plan comparison')
    release('Plan comparison')
    release('Card details')
  end

  # Days 11-13: B+C#2, A+D, B+C#3 — fast turnaround, 3-deploy story
  def phase_4_fast_turnaround
    start_paired('Invoice template', @tasks[:payment], :bob, :carol)
    start_paired('Role permissions', @tasks[:permissions], :alice, :dan)
    advance_days(1)
    deploy('Invoice template')
    release('Invoice template')
    deploy('Role permissions')
    start_paired('Email alerts', @tasks[:verify], :bob, :carol)
    advance_days(1)
    deploy('Email alerts')
    deploy('Role permissions')
  end

  # Days 13-19: B+D→solo(B), A+C, D+E — Dan leaves, Bob works solo
  def phase_5_solo_and_churn
    advance_days(1)
    deploy('Role permissions')
    deploy('Email alerts')
    advance_days(1)
    release('Role permissions')
    release('Email alerts')
    start_paired('Invite link', @tasks[:register], :bob, :dan)
    start_paired('Team name editor', @tasks[:config], :alice, :carol)
    advance_days(1)
    leave_story('Invite link', :dan)
    start_paired('Email preferences', @tasks[:verify], :dan, :eve)
    advance_days(1)
    deploy('Invite link')
    deploy('Team name editor')
    deploy('Email preferences')
    advance_days(1)
    release('Invite link')
    deploy('Email preferences')
    advance_days(1)
    release('Team name editor')
    release('Email preferences')
  end

  # Days 19-24: B+C#4, ensemble(A+D+E), ensemble(C+D+E), A+B
  def phase_6_final_rotation
    start_paired('Payment retry', @tasks[:payment], :bob, :carol)
    start_ensemble('SSO config', @tasks[:register], :alice, :dan, :eve)
    advance_days(1)
    deploy('Payment retry')
    advance_days(1)
    deploy('SSO config')
    release('Payment retry')
    advance_days(1)
    deploy('SSO config')
    release('SSO config')
    start_ensemble('Annual billing', @tasks[:plans], :carol, :dan, :eve)
    start_paired('Coupon codes', @tasks[:payment], :alice, :bob)
    advance_days(1)
    deploy('Annual billing')
    deploy('Coupon codes')
    advance_days(1)
    release('Annual billing')
    release('Coupon codes')
  end

  # Days 24-30: A+C→solo(C), stale A+D, stale C+E, planned backlog
  def phase_7_stale_and_backlog
    start_paired('Account deletion', @tasks[:permissions], :alice, :carol)
    advance_days(1)
    leave_story('Account deletion', :alice)
    start_paired('Billing dashboard', @tasks[:payment], :alice, :dan)
    advance_days(1)
    deploy('Account deletion')
    advance_days(1)
    release('Account deletion')
    start_paired('Seat management', @tasks[:permissions], :carol, :eve)
    advance_days(1)
    deploy('Billing dashboard')
    deploy('Seat management')
    advance_days(2)
    create_story_timed('Avatar upload', @tasks[:avatar])
    create_story_timed('Two-factor auth', @tasks[:register])
    create_story_timed('Webhook config', @tasks[:config])
    create_story_timed('Payment history', @tasks[:payment])
  end

  def seed_story_notes
    note_story('Billing dashboard', note_type: 'stale_story')
    note_story('Seat management', note_type: 'split_candidate')
    note_story('Registration form', note_type: 'stale_flag')
    note_story('Billing dashboard', note_type: 'split_candidate')
    dismiss_note('Billing dashboard', note_type: 'split_candidate', person_key: :alice)
    puts '  Created story notes (3 active, 1 dismissed)'
  end
end
