# frozen_string_literal: true

ENV['RACK_ENV'] ||= 'development'

raise 'DevTeardown can only run in development' unless ENV['RACK_ENV'] == 'development'

require_relative '../models'

class DevTeardown
  SEED_TEAMS = [
    'Acme Product Team',
    'Solo Dev',
    'XP Squad',
    'Steady Ship Crew',
    'Growing Pains Inc',
    'Trialing Co',
    'Expired Trial Co',
    'Paying Co',
    'Canceled Co',
    'Green CI Team',
    'Red CI Team'
  ].freeze

  TEAM_TABLES = %i[
    monitored_repos events story_notes story_assignments stories release_slices tasks
    activity_personas activities personas maps team_constraints
    team_memberships
  ].freeze

  def self.call
    teams = Team.where(name: SEED_TEAMS).all
    if teams.empty?
      puts 'No seed teams found. Nothing to do.'
      return
    end

    DB.transaction do
      disable_triggers
      teams.each do |team|
        puts "Removing '#{team.name}' (#{team.id})..."
        delete_team_data(team.id)
      end
      enable_triggers
    end

    puts "Done. #{teams.size} seed team(s) removed."
  end

  def self.disable_triggers
    DB.run('ALTER TABLE events DISABLE TRIGGER enforce_append_only')
    DB.run('ALTER TABLE activity_personas DISABLE TRIGGER check_min_one_persona')
  end

  def self.enable_triggers
    DB.run('ALTER TABLE events ENABLE TRIGGER enforce_append_only')
    DB.run('ALTER TABLE activity_personas ENABLE TRIGGER check_min_one_persona')
  end

  def self.delete_team_data(tid)
    person_ids = DB[:team_memberships].where(team_id: tid).select_map(:person_id)

    delete_system_actor_events(tid)

    TEAM_TABLES.each do |table|
      count = DB[table].where(team_id: tid).delete
      puts "  #{table}: #{count} rows"
    end

    delete_people_and_actors(tid, person_ids)

    DB[:teams].where(id: tid).delete
    puts '  teams: 1 row'
  end

  def self.delete_people_and_actors(tid, person_ids)
    actor_ids = DB[:people].where(id: person_ids).select_map(:actor_id)
    actor_ids << DB[:teams].where(id: tid).get(:webhook_actor_id)
    actor_ids.compact!
    DB[:teams].where(id: tid).update(webhook_actor_id: nil)
    pcount = DB[:people].where(id: person_ids).delete
    puts "  people: #{pcount} rows"

    acount = DB[:actors].where(id: actor_ids).delete
    puts "  actors: #{acount} rows"
  end

  def self.delete_system_actor_events(tid)
    system_actor_id = DB[:teams].where(id: tid).get(:webhook_actor_id)
    return unless system_actor_id

    ecount = DB[:events].where(actor_id: system_actor_id).delete
    puts "  events (system actor): #{ecount} rows"
  end
end
