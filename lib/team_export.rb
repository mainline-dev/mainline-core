# frozen_string_literal: true

require 'date'
require 'zip'
require_relative 'data_export'
require_relative 'export_tables'
require_relative 'feature_file'
require_relative 'map_order'
require_relative 'record_event'

# Everything a team has in Mainline, as one zip it can take away: files for a
# person to read, and the full record. Any member of the team can download it,
# and each download is recorded as an event: who and when.
module TeamExport
  Download = Struct.new(:file_name, :body, keyword_init: true)

  # What each file is, in the order the README lists them. A file is listed
  # only when the zip holds it.
  EXPLAINED = {
    'README.md'   => 'This file.',
    'stories.md'  => 'For a coding agent: every story on the map in map order, with its status, its ID and a ' \
                     'link to its feature file.',
    'features/'   => 'One Gherkin feature file for each story that has scenarios, named by the story ID. The ' \
                     'feature and every scenario carry the story ID as a tag.',
    'stories.csv' => "For Jira's CSV importer: one row per story, in map order. Map Summary, Issue Type, " \
                     'Description, Status and Labels to the Jira fields of those names. Mainline ID and ' \
                     'Original Jira Key are for custom fields, or can be left out. Do not map Original Jira Key ' \
                     "to Jira's own key: Jira would then update the existing item with that key.",
    'museum.csv'  => 'The Ticket Museum as the museum keeps it: every exhibit, where it came from, and the ' \
                     'ID of the story it was promoted to, if it was. Assignees, reporters and comment authors ' \
                     'were left out when the tickets were imported, so they are not here.',
    'export.json' => 'The full record: maps, activities, steps, release slices, stories with their scenarios, ' \
                     'the Ticket Museum and the event log, each with its ID. The format is version 1, ' \
                     'described by the JSON Schema at https://mainline.dev/schemas/export-1.json.'
  }.freeze

  GUARD_RAILS = 'Inside Mainline, coding agents cannot change scenarios and only people release. ' \
                'Outside Mainline nothing enforces that unless you add your own checks.'

  NO_SLICE = 'No release slice'

  ACTION = 'exported'
  Made = Struct.new(:by, :at, keyword_init: true)

  def self.call(team:, actor:, on: Date.today)
    files = DB.transaction {
      SetTeamContext.call(team.id)
      RecordEvent.call(actor_id: actor.id, entity: team, action: ACTION, team_id: team.id)
      files(team)
    }
    files = { 'README.md' => readme(team, on, files.keys) }.merge(files)
    Download.new(file_name: "mainline-#{slug(team.name)}-#{on.iso8601}.zip", body: zip(files))
  end

  # The team's latest exports, newest first: who made each and when.
  def self.recent(team, limit: 5)
    Event.where(team_id: team.id, entity_id: team.id, action: ACTION).reverse(:event_no).limit(limit).eager(:actor).all
      .map { |event| Made.new(by: event.actor&.name, at: event.occurred_at) }
  end

  def self.files(team)
    placed = MapOrder.for(team.id)
    features = feature_files(placed.map(&:story))
    { 'stories.md'  => stories_md(placed, features.invert), **features.to_h { |path, story| [path, FeatureFile.for(story)] },
      'stories.csv' => ExportTables.stories(placed), 'museum.csv' => ExportTables.museum(team.id),
      'export.json' => DataExport.to_json(team_id: team.id) }
  end

  # Where each story that has scenarios keeps its feature file: { path => story }.
  def self.feature_files(stories)
    with_scenarios = Scenario.where(story_id: stories.map(&:id)).distinct.select_map(:story_id)
    stories.select { |story| with_scenarios.include?(story.id) }
      .to_h { |story| ["features/#{story.id}-#{FeatureFile.file_name(story)}", story] }
  end

  def self.stories_md(placed, paths)
    maps = placed.chunk_while { |a, b| a.story_map.id == b.story_map.id }.map { |on_map|
      slices = on_map.chunk_while { |a, b| a.slice&.id == b.slice&.id }.map { |in_slice|
        lines = in_slice.map { |place| story_line(place.story, paths[place.story]) }
        "### #{FeatureFile.one_line(in_slice.first.slice&.name || NO_SLICE)}\n\n#{lines.join("\n")}\n"
      }
      "## #{FeatureFile.one_line(on_map.first.story_map.name)}\n\n#{slices.join("\n")}"
    }
    <<~STORIES
      # Stories

      Every story on the map, in map order: release slice by release slice, and within a slice left to right across the map. Each line gives the story, its status, its ID and its feature file.

      #{maps.join("\n")}
    STORIES
  end

  def self.story_line(story, path)
    file = path ? "[#{path}](#{path})" : 'no scenarios yet'
    "- **#{FeatureFile.one_line(story.title)}** (#{story.status}) `#{story.id}`: #{file}"
  end

  def self.readme(team, date, names)
    listed = EXPLAINED.select { |name, _| name == 'README.md' || names.any? { |file| file.start_with?(name) } }
    <<~README
      # #{team.name.gsub(/\s+/, ' ').strip}: Mainline export

      Exported on #{date.iso8601}.

      ## What is here

      #{listed.map { |name, what| "- `#{name}`: #{what}" }.join("\n")}

      ## Outside Mainline

      #{GUARD_RAILS}
    README
  end

  # A team name as part of a file name: lower-case letters, digits and hyphens.
  def self.slug(name)
    slug = name.to_s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-+|-+\z/, '')
    slug.empty? ? 'team' : slug
  end

  def self.zip(files)
    Zip::OutputStream.write_buffer { |out|
      files.each do |name, content|
        out.put_next_entry(name)
        out.write(content)
      end
    }.string
  end

  private_class_method :files, :feature_files, :stories_md, :story_line, :readme, :slug, :zip
end
