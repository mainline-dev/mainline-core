# frozen_string_literal: true

require 'mcp'
require_relative 'core_events'
require_relative 'feature_file'
require_relative 'import_instructions'
require_relative 'mcp_data'
require_relative 'set_team_context'
require_relative 'step_stubs'
require_relative 'story_id'

module MainlineMCP
  # Every tool only reads: it changes nothing a team edits, gives the same
  # answer each time, and reaches nothing outside Mainline. A read of a story
  # is logged, which is how the card knows a coding agent has read it.
  READ_ONLY = { read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false }.freeze
  NO_STORY = 'No story with that ID. Use an ID from get_map, or the 8-character ID on the card.'
  NO_MAP = 'No map with that ID. Use an ID from list_maps.'
  NO_TEAM = 'No team with that ID among those this coding agent can read. list_maps names them.'
  AMBIGUOUS = 'More than one story starts with that ID. Use the full ID from get_map.'
  CODING_AGENTS_PAGE = "#{ENV.fetch('BASE_URL')}/profile/coding-agents".freeze

  def self.build_server
    instructions = 'Read-only access to a Mainline story map. ' \
                   'Use list_maps to see available maps, get_map for the full hierarchy, ' \
                   'get_story for details including scenarios (acceptance criteria), ' \
                   'and get_feature_file for those scenarios as a Gherkin feature file. ' \
                   'Use get_import_format to learn how to write a file that proposes stories from a ' \
                   'specification; you cannot upload it, so give it to the person to bring in. ' \
                   'Work on one story at a time. Finish the current story before starting another. ' \
                   'Do not start work on a story that has zero scenarios. ' \
                   'Scenarios are the acceptance criteria. Without them you are guessing what done means. ' \
                   'Ask the human to add scenarios before proceeding.'

    server = MCP::Server.new(name: 'mainline', version: '1.0.0', instructions: instructions)

    define_list_maps(server)
    define_get_map(server)
    define_get_story(server)
    define_get_feature_file(server)
    define_get_import_format(server)
    CoreEvents.publish(:mcp_server_built, server: server)
    server
  end

  def self.define_list_maps(server)
    server.define_tool(
      name:         'list_maps',
      title:        'List maps',
      annotations:  READ_ONLY,
      description:  'List the maps of the teams this coding agent can read, each with its team. ' \
                    "Give a team's ID for that team's maps only.",
      input_schema: {
        type:       'object',
        properties: { team_id: { type: 'string', description: 'UUID of one team' } }
      }
    ) { |team_id: nil| MainlineMCP.call_list_maps(team_id) }
  end

  def self.define_get_map(server)
    server.define_tool(
      name:         'get_map',
      title:        'Get map',
      annotations:  READ_ONLY,
      description:  'Get full map hierarchy: activities, steps, stories, personas, release slices',
      input_schema: {
        type:       'object',
        properties: { map_id: { type: 'string', description: 'UUID of the map' } },
        required:   ['map_id']
      }
    ) { |map_id:| MainlineMCP.call_get_map(map_id) }
  end

  def self.define_get_story(server)
    server.define_tool(
      name:         'get_story',
      title:        'Get story',
      annotations:  READ_ONLY,
      description:  'Get story detail: description, scenarios, deploy history, assignments.',
      input_schema: {
        type:       'object',
        properties: { story_id: { type: 'string', description: 'UUID of the story' } },
        required:   ['story_id']
      }
    ) { |story_id:| MainlineMCP.call_get_story(story_id) }
  end

  def self.define_get_feature_file(server)
    server.define_tool(
      name:         'get_feature_file',
      title:        'Get feature file',
      annotations:  READ_ONLY,
      description:  "Get a story's scenarios as a Gherkin .feature file, tagged with the story and scenario IDs. " \
                    'With a language, also pending step definitions for it.',
      input_schema: {
        type:       'object',
        properties: {
          story_id: { type: 'string', description: 'UUID of the story' },
          language: { type: 'string', enum: StepStubs::LANGUAGES.keys, description: 'Language for step stubs' }
        },
        required:   ['story_id']
      }
    ) { |story_id:, language: nil| MainlineMCP.call_get_feature_file(story_id, language) }
  end

  def self.define_get_import_format(server)
    server.define_tool(
      name:         'get_import_format',
      title:        'Get import format',
      annotations:  READ_ONLY,
      description:  'Get the instructions and JSON Schema for a Mainline import file: stories proposed from a ' \
                    "specification, for a person to upload and review. Lists the team's activities and steps. " \
                    'Reads only; nothing is marked or changed.',
      input_schema: { type: 'object', properties: {} }
    ) { MCP::Tool::Response.new([{ type: 'text', text: ImportInstructions.for(team_id: MainlineMCP.import_team_id) }]) }
  end

  # Who the request reads as, and which teams it may read.
  def self.access
    Thread.current[:mcp_access]
  end

  # The team whose activities and steps the import format lists: the only
  # team the request reads, if it reads one.
  def self.import_team_id
    access.team_ids.first if access.team_ids.one?
  end

  # The maps of every team the request may read, or of one of them, each with
  # its team.
  def self.call_list_maps(team_id = nil)
    team_ids = access.readable_team_ids
    if team_id
      status, placed = access.place(team_id)
      return refusal(status, placed, NO_TEAM) unless status == :open

      team_ids = [team_id]
    end
    names = Team.where(id: team_ids).to_hash(:id, :name)
    json = team_ids.flat_map { |id|
      maps_of(id).map { |m| { id: m.id, name: m.name, position: m.position, team: { id: id, name: names[id] } } }
    }
    MCP::Tool::Response.new([{ type: 'text', text: JSON.generate(json) }])
  end

  def self.maps_of(team_id)
    SetTeamContext.call(team_id)
    Map.where(team_id: team_id, archived_at: nil).order(:position).all
  end

  def self.call_get_map(map_id)
    status, team_id = access.map(map_id)
    return refusal(status, team_id, NO_MAP) unless status == :open

    SetTeamContext.call(team_id)
    json = McpData.map(Map[map_id])
    MCP::Tool::Response.new([{ type: 'text', text: JSON.generate(json) }])
  end

  def self.call_get_story(story_id)
    readable_story(story_id) do |story|
      record_agent_read(story)
      json = McpData.story(story)
      MCP::Tool::Response.new([{ type: 'text', text: JSON.generate(json) }])
    end
  end

  def self.call_get_feature_file(story_id, language = nil)
    readable_story(story_id) do |story|
      next error_response("Unknown language: #{language}") if language && !StepStubs::LANGUAGES.key?(language)

      record_agent_read(story)
      files = [FeatureFile.for(story)]
      files << StepStubs.for(story, language) if language
      MCP::Tool::Response.new(files.map { |text| { type: 'text', text: text } })
    end
  end

  # The story the ID names, by its full ID or the short one on its card, read
  # in its own team; or the refusal when the request may not read it.
  def self.readable_story(story_id)
    status, team_id, id = access.story(story_id)
    return refusal(status, team_id, NO_STORY) unless status == :open

    SetTeamContext.call(team_id)
    yield Story[id]
  end

  # Why a map or story can't be read. Only the person's own teams, and the
  # teams given, are named; anything else gets the answer for nothing there.
  def self.refusal(status, team_id, not_found)
    name = (Team[team_id]&.name if team_id)
    error_response(
      case status
      when :withheld then "That is on #{name}, a team you did not give this coding agent. " \
                          "To let it read #{name}, give it that team on the Coding agents page: #{CODING_AGENTS_PAGE}"
      when :suspended then "#{name} is suspended, so its maps and stories can't be read."
      when :ambiguous then AMBIGUOUS
      else not_found
      end
    )
  end

  # Reading a story, in any form, records the read and who was on the story,
  # and writes nothing else: the AGENT chip is worked out from these reads.
  def self.record_agent_read(story)
    RecordEvent.call(
      actor_id:    McpActor.id_for(story.team_id),
      entity:      story,
      action:      AgentReads::ACTION,
      after_state: {
        user_agent: Thread.current[:mcp_user_agent],
        person_ids: StoryAssignment.where(story_id: story.id).select_map(:person_id)
      }.compact
    )
  end

  def self.error_response(message)
    MCP::Tool::Response.new([{ type: 'text', text: message }], error: true)
  end
end
