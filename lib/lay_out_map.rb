# frozen_string_literal: true

require_relative 'create_map'
require_relative 'create_persona'
require_relative 'create_activity'
require_relative 'create_task'

# The backbone a staged file proposes (a map's activities and their steps),
# set against the team's maps so a person can choose what to create. It goes
# on a new map unless the team has one of that name. On a new map everything
# starts ticked; on a map the team has, what is there already is marked and
# the rest starts unticked. Nothing is created without a tick.
#
# Laying it out creates the ticked activities and steps through the same
# doors a person uses, so each is recorded as the work of whoever acquired the
# file. An activity brings the personas it is for, since it cannot exist
# without one. A new map is made only if something goes on it.
module LayOutMap
  class Refused < StandardError; end

  Plan = Struct.new(:target, :maps, :activities, :unplaced, keyword_init: true)
  Result = Struct.new(:success?, :errors, keyword_init: true)
  # The map being laid out on, made when first needed if it is to be new.
  Board = Struct.new(:team, :actor, :name, :found) do
    def map
      self.found ||= made(CreateMap.call(team: team, actor: actor, name: name)).created
    end

    def made(result)
      raise Refused, result.errors.first unless result.success?

      result
    end
  end

  # target is 'new' or the id of one of the team's maps; activities are the
  # ticked activities' places in the backbone, steps the ticked steps' as
  # "activity:step".
  def self.call(team:, actor:, backbone:, target:, activities:, steps:)
    found = Map.where(team_id: team.id, id: target, archived_at: nil).first unless target == 'new'
    return Result.new(success?: false, errors: ['Choose one of your maps to lay this out on']) unless target == 'new' || found

    board = Board.new(team, actor, backbone['map'], found)

    backbone['activities'].each_with_index do |proposed, index|
      activity = activity(board, proposed, ticked: activities.include?(index))
      next unless activity

      proposed['steps'].each_with_index { |step, at| step(board, activity, step) if steps.include?("#{index}:#{at}") }
    end
    Result.new(success?: true, errors: [])
  rescue Refused => e
    Result.new(success?: false, errors: [e.message])
  end

  # The activity of that name on the map, made if it is ticked and not there.
  def self.activity(board, proposed, ticked:)
    existing = board.found && named(Activity.where(map_id: board.found.id, archived_at: nil), proposed['name'])
    return existing if existing || !ticked

    persona_ids = proposed['personas'].map { |name| persona(board, name).id }
    board.made(CreateActivity.call(map: board.map, team: board.team, actor: board.actor, name: proposed['name'],
      persona_ids: persona_ids)).activity
  end

  def self.persona(board, name)
    named(Persona.where(map_id: board.map.id, archived_at: nil), name) ||
      board.made(CreatePersona.call(map: board.map, team: board.team, actor: board.actor, name: name, description: '')).persona
  end

  def self.step(board, activity, name)
    return if named(Task.where(activity_id: activity.id, archived_at: nil), name)

    board.made(CreateTask.call(map: board.map, team: board.team, actor: board.actor, name: name, activity_id: activity.id))
  end

  # The one of that name, whatever its capitals.
  def self.named(records, name)
    records.all.find { |record| record.name.casecmp?(name) }
  end

  def self.plan(team:, import:)
    backbone = import.backbone.to_h
    maps = Map.where(team_id: team.id, archived_at: nil).order(:position).all
    existing = maps.find { |map| map.name.casecmp?(backbone['map']) }
    there = existing ? on_map(existing) : {}
    activities = activities(backbone, there, existing ? 'unticked' : 'ticked')
    Plan.new(target: existing ? existing.id : 'new', maps: maps, activities: activities,
      unplaced: unplaced(import.items.to_a, activities))
  end

  # A map's activities and the steps under each, by lower-cased name.
  def self.on_map(map)
    activities = Activity.where(map_id: map.id, archived_at: nil).to_hash(:id, :name)
    steps = Task.where(map_id: map.id, archived_at: nil).select_map(%i[activity_id name])
    activities.to_h { |id, name| [name.downcase, steps.select { |activity_id, _| activity_id == id }.map { |_, step| step.downcase }] }
  end

  def self.activities(backbone, there, fresh)
    backbone['activities'].to_a.each_with_index.map do |activity, index|
      steps_there = there[activity['name'].downcase]
      steps = activity['steps'].each_with_index.map { |step, at|
        { index: "#{index}:#{at}", name: step, state: steps_there&.include?(step.downcase) ? 'there' : fresh }
      }
      { index: index, name: activity['name'], personas: activity['personas'], state: steps_there ? 'there' : fresh, steps: steps }
    end
  end

  # How many entries suggest a step that is neither proposed nor on the map.
  def self.unplaced(items, activities)
    places = activities.flat_map { |activity| activity[:steps].map { |step| [activity[:name].downcase, step[:name].downcase] } }
    items.count do |item|
      suggested = item['suggested'].to_h
      place = [suggested['activity'], suggested['step']]
      place.any? && !places.include?(place.map { |name| name.to_s.downcase })
    end
  end
  private_class_method :activity, :persona, :step, :named, :on_map, :activities, :unplaced
end
