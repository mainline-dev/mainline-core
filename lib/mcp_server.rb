# frozen_string_literal: true

require 'mcp'
require_relative 'core_events'
require_relative 'feature_file'
require_relative 'import_instructions'
require_relative 'step_stubs'

module MainlineMCP
  def self.build_server
    instructions = 'Read-only access to a Mainline story map, except that ' \
                   'fetching a story marks it as agent-assisted. ' \
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
      description:  'List all maps for this team',
      input_schema: { type: 'object', properties: {} }
    ) { MainlineMCP.call_list_maps }
  end

  def self.define_get_map(server)
    server.define_tool(
      name:         'get_map',
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
      description:  'Get story detail: description, scenarios, deploy history, assignments. ' \
                    'Marks the story as agent-assisted.',
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
      description:  "Get a story's scenarios as a Gherkin .feature file, tagged with the story and scenario IDs. " \
                    'With a language, also pending step definitions for it. Marks the story as agent-assisted.',
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
      description:  'Get the instructions and JSON Schema for a Mainline import file: stories proposed from a ' \
                    "specification, for a person to upload and review. Lists the team's activities and steps. " \
                    'Reads only; nothing is marked or changed.',
      input_schema: { type: 'object', properties: {} }
    ) { MCP::Tool::Response.new([{ type: 'text', text: ImportInstructions.for(team_id: MainlineMCP.current_team_id) }]) }
  end

  def self.current_team_id
    Thread.current[:mcp_team_id]
  end

  def self.call_list_maps
    team_id = current_team_id
    maps = Map.where(team_id: team_id, archived_at: nil).order(:position).all
    json = maps.map { |m| { id: m.id, name: m.name, position: m.position } }
    MCP::Tool::Response.new([{ type: 'text', text: JSON.generate(json) }])
  end

  def self.call_get_map(map_id)
    team_id = current_team_id
    map = Map[map_id]
    return error_response('Map not found') unless map
    return error_response('Map not found') unless map.team_id == team_id

    json = build_map_data(map)
    MCP::Tool::Response.new([{ type: 'text', text: JSON.generate(json) }])
  end

  def self.call_get_story(story_id)
    story = team_story(story_id)
    return error_response('Story not found') unless story

    mark_agent_read(story)
    json = build_story_data(story)
    MCP::Tool::Response.new([{ type: 'text', text: JSON.generate(json) }])
  end

  def self.call_get_feature_file(story_id, language = nil)
    story = team_story(story_id)
    return error_response('Story not found') unless story
    return error_response("Unknown language: #{language}") if language && !StepStubs::LANGUAGES.key?(language)

    mark_agent_read(story)
    files = [FeatureFile.for(story)]
    files << StepStubs.for(story, language) if language
    MCP::Tool::Response.new(files.map { |text| { type: 'text', text: text } })
  end

  def self.team_story(story_id)
    story = Story[story_id]
    story if story && story.team_id == current_team_id
  end

  # Reading a story, in any form, marks it as agent-assisted and records who
  # was on it.
  def self.mark_agent_read(story)
    team_id = current_team_id
    DB.transaction do
      DB[:stories].where(id: story.id).update(agent_assisted: true) unless story.agent_assisted
      RecordEvent.call(
        actor_id:    McpActor.id_for(team_id),
        entity:      story,
        action:      'agent_read',
        after_state: {
          user_agent: Thread.current[:mcp_user_agent],
          person_ids: StoryAssignment.where(story_id: story.id).select_map(:person_id)
        }.compact
      )
    end
  end

  def self.build_map_data(map)
    activities = Activity.where(map_id: map.id, archived_at: nil).order(:position).all
    slices = ReleaseSlice.where(map_id: map.id, archived_at: nil).order(:position).all
    personas = Persona.where(map_id: map.id, archived_at: nil).order(:position).all

    {
      id:             map.id,
      name:           map.name,
      activities:     activities.map { |act| build_activity_data(act) },
      release_slices: slices.map { |s| { id: s.id, name: s.name, position: s.position } },
      personas:       personas.map { |p| { id: p.id, name: p.name, description: p.description } }
    }
  end

  def self.build_activity_data(activity)
    tasks = Task.where(activity_id: activity.id, archived_at: nil).order(:position).all
    {
      id:       activity.id,
      name:     activity.name,
      position: activity.position,
      steps:    tasks.map { |t| build_task_data(t) }
    }
  end

  def self.build_task_data(task)
    stories = Story.where(task_id: task.id, archived_at: nil).order(:position).all
    {
      id:       task.id,
      name:     task.name,
      position: task.position,
      stories:  stories.map { |s| summarize_story(s) }
    }
  end

  def self.summarize_story(story)
    {
      id:               story.id,
      short_id:         story.id[0, 8].upcase,
      title:            story.title,
      status:           story.status,
      position:         story.position,
      release_slice_id: story.release_slice_id,
      deploy_count:     story.deploy_count
    }
  end

  def self.build_story_data(story)
    {
      id:                  story.id,
      short_id:            story.id[0, 8].upcase,
      title:               story.title,
      description:         story.description,
      status:              story.status,
      position:            story.position,
      release_slice_id:    story.release_slice_id,
      deploy_count:        story.deploy_count,
      first_deployed_at:   story.first_deployed_at&.iso8601,
      last_deployed_at:    story.last_deployed_at&.iso8601,
      decoupling_strategy: story.decoupling_strategy,
      decoupling_label:    story.decoupling_label,
      scenarios:           scenario_data(story),
      assigned_count:      StoryAssignment.where(story_id: story.id).count
    }
  end

  def self.scenario_data(story)
    Scenario.where(story_id: story.id).order(:position).all.map { |s|
      { name: s.display_name, given: s.given_text, when: s.when_text, then: s.then_text, done: !s.done_at.nil? }
    }
  end

  def self.error_response(message)
    MCP::Tool::Response.new([{ type: 'text', text: message }], error: true)
  end
end
