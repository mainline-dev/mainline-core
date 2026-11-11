# frozen_string_literal: true

require 'csv'
require_relative 'feature_file'
require_relative 'jira_csv'

# The export's two spreadsheets. stories.csv is shaped for Jira's CSV importer:
# a header row, Summary on every row, one label to a column under a repeated
# header, and the original Jira key in a column of its own, so that Jira can
# never take it for the key of an existing item and overwrite it. museum.csv is
# the Ticket Museum as the museum keeps it.
#
# A cell a spreadsheet would run as a formula (one that begins with =, +, - or
# @) gets an apostrophe in front, the same guard the museum's own files use
# and that its reader takes off again.
module ExportTables
  STORY_HEADERS = ['Summary', 'Issue Type', 'Description', 'Status', 'Labels', 'Labels', 'Mainline ID',
                   'Original Jira Key'].freeze
  MUSEUM_HEADERS = ['Key', 'Type', 'Summary', 'Description', 'Labels', 'Parent', 'Created', 'Updated', 'Source',
                    'Proposed From', 'Comments', 'Links', 'Status', 'Promoted To'].freeze
  ISSUE_TYPE = 'Story'
  # Jira's default statuses. A story that is neither planned nor released is in progress.
  STATUSES = { 'planned' => 'To Do', 'released' => 'Done' }.freeze
  IN_PROGRESS = 'In Progress'

  # One row per story, in the order given (MapOrder's).
  def self.stories(placed)
    stories = placed.map(&:story)
    scenarios = Scenario.where(story_id: stories.map(&:id)).order(:position).all.group_by(&:story_id)
    keys = jira_keys(stories)
    places = places(stories)
    table(STORY_HEADERS, stories.map { |story|
      [story.title, ISSUE_TYPE, description(story, scenarios.fetch(story.id, [])), STATUSES.fetch(story.status, IN_PROGRESS),
       *places.fetch(story.task_id), story.id, keys.fetch(story.id, []).join(' ')]
    })
  end

  def self.museum(team_id)
    table(MUSEUM_HEADERS, MuseumItem.where(team_id: team_id).order(:source_key).all.map { |item|
      [item.source_key, item.issue_type, item.summary, item.description, item.labels.to_a.join(' '), item.parent_key,
       item.source_created_at&.utc&.iso8601, item.source_updated_at&.utc&.iso8601, item.source, item.origin,
       comments(item), links(item), museum_status(item), item.story_id]
    })
  end

  def self.table(headers, rows)
    CSV.generate { |csv|
      csv << headers
      rows.each { |row| csv << row.map { |cell| safe(cell) } }
    }
  end

  def self.safe(cell)
    text = cell.to_s
    text.match?(JiraCsv::FORMULA) ? "'#{text}" : text
  end

  # What the story says, then each scenario as plain text.
  def self.description(story, scenarios)
    blocks = scenarios.map { |scenario|
      ["Scenario: #{FeatureFile.one_line(scenario.display_name)}", "Given #{FeatureFile.one_line(scenario.given_text)}",
       "When #{FeatureFile.one_line(scenario.when_text)}", "Then #{FeatureFile.one_line(scenario.then_text)}"].join("\n")
    }
    [story.description.to_s.strip, *blocks].reject(&:empty?).join("\n\n")
  end

  # The Jira tickets each story was promoted from: { story id => [keys] }.
  def self.jira_keys(stories)
    MuseumItem.where(story_id: stories.map(&:id), source: 'jira').order(:source_key)
      .select_hash_groups(:story_id, :source_key)
  end

  # Each step's activity and step names as labels: { step id => [activity, step] }.
  # A Jira label cannot hold a space, so a name's words are joined with hyphens.
  def self.places(stories)
    tasks = Task.where(id: stories.map(&:task_id).uniq).all
    activities = Activity.where(id: tasks.map(&:activity_id).uniq).select_hash(:id, :name)
    tasks.to_h { |task| [task.id, [label(activities[task.activity_id]), label(task.name)]] }
  end

  def self.label(name)
    name.to_s.split.join('-')
  end

  def self.comments(item)
    item.comments.to_a.map { |comment| [comment['at']&.slice(0, 10), comment['text']].compact.join(': ') }.join("\n\n")
  end

  def self.links(item)
    item.links.to_a.map { |link| "#{link['direction']} #{link['type']} #{link['key']}" }.join("\n")
  end

  def self.museum_status(item)
    if item.promoted_at then 'promoted'
    elsif item.discarded_at then 'stored'
    else 'on display'
    end
  end

  private_class_method :table, :safe, :description, :jira_keys, :places, :label, :comments, :links, :museum_status
end
