# frozen_string_literal: true

require 'securerandom'
require_relative 'add_scenario'
require_relative 'record_event'
require_relative 'unpromote_museum_item'
require_relative 'create_story'

# Promotes Ticket Museum items to one story on a map: a new story under the
# chosen task, with a title rewritten as a story and no description. The item
# stays in the museum, linked to the story, as the record of what Jira said.
# Scenarios written while promoting go on the story (empty ones are left out);
# if one cannot be kept, nothing is promoted. Epics and sub-tasks are not
# promoted; an item is promoted once. Several go together or not at all, as a
# batch: their promote events share an id, and they can be sent back as one.
module PromoteMuseumItem
  Result = Struct.new(:success?, :errors, :story, :batch, keyword_init: true)
  Undone = Struct.new(:back, :story_archived, keyword_init: true)

  def self.call(item:, team:, actor:, person:, title:, task_id:, scenarios: [])
    together(items: [item], team: team, actor: actor, person: person, title: title, task_id: task_id, scenarios: scenarios)
  end

  def self.together(items:, team:, actor:, person:, title:, task_id:, scenarios: [])
    result = nil
    DB.transaction(savepoint: true) do
      result = promote(items, team, actor, person, title, task_id, scenarios)
      raise Sequel::Rollback unless result.success?
    end
    result
  end

  def self.promote(items, team, actor, person, title, task_id, scenarios)
    items = MuseumItem.where(id: items.map(&:id)).order(:id).for_update.all
    task = open_tasks(team.id).where(Sequel[:tasks][:id] => task_id).select_all(:tasks).first
    error = refusal(items, task)
    return failure([error]) if error

    created = CreateStory.call(map: Map[task.map_id], team: team, actor: actor, person: person, title: title, task_id: task.id)
    return failure(created.errors) unless created.success?

    errors = add_scenarios(created.story, actor, scenarios)
    return failure(errors) unless errors.empty?

    events = Event.where(entity_id: created.story.id).count
    batch = SecureRandom.uuid
    items.each do |item|
      item.update(story_id: created.story.id, promoted_at: Time.now, promoted_events: events)
      RecordEvent.call(actor_id: actor.id, entity: item, action: 'promoted', correlation_id: batch,
        after_state: { source_key: item.source_key, story_id: created.story.id })
    end
    Result.new(success?: true, errors: [], story: created.story, batch: batch)
  end

  # Sends back what was promoted together: how many went back, and whether
  # their story went with them.
  def self.undo(team_id:, actor:, batch:)
    return Undone.new(back: 0, story_archived: false) unless batch

    ids = Event.where(team_id: team_id, correlation_id: batch, action: 'promoted').select_map(:entity_id)
    items = MuseumItem.where(team_id: team_id, id: ids).exclude(promoted_at: nil).all
    results = DB.transaction { items.map { |item| UnpromoteMuseumItem.call(item: item, actor: actor) } }
    Undone.new(back: results.count(&:success?), story_archived: results.any?(&:story_archived))
  end

  # Adds each scenario with something written in it; returns what was wrong, if anything.
  def self.add_scenarios(story, actor, scenarios)
    scenarios.map { |parts| parts.transform_values { |text| text.to_s.strip } }
      .reject { |parts| parts.values.all?(&:empty?) }
      .flat_map { |parts|
        AddScenario.call(story: story, actor: actor, given_text: parts[:given], when_text: parts[:when],
          then_text: parts[:then]).errors
      }
  end

  def self.failure(errors)
    Result.new(success?: false, errors: errors)
  end

  # The team's tasks a story can be promoted under: not archived, nor on an
  # archived activity or map.
  def self.open_tasks(team_id)
    tasks = Sequel[:tasks]
    Task.join(:activities, id: :activity_id).join(:maps, id: tasks[:map_id])
      .where(tasks[:team_id] => team_id, tasks[:archived_at] => nil, Sequel[:activities][:archived_at] => nil,
        Sequel[:maps][:archived_at] => nil)
  end

  def self.refusal(items, task)
    if items.empty?
      'Choose an exhibit to promote'
    elsif items.any?(&:promoted_at)
      'This exhibit has already been promoted'
    elsif items.any?(&:discarded_at)
      'This exhibit is in storage; bring it out first'
    elsif items.any? { |item| item.epic? || item.sub_task? }
      'Epics and sub-tasks stay in the museum; promote the ticket itself'
    elsif !task
      'Choose a step on one of your maps'
    end
  end
  private_class_method :promote, :refusal, :add_scenarios, :failure
end
