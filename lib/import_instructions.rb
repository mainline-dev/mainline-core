# frozen_string_literal: true

require 'json'
require_relative 'add_scenario'
require_relative 'mainline_file'

# What a model needs to turn a specification or research into a Mainline
# import file: how to break the work into stories, an example, and the schema
# the file must pass. One text, shown wherever it is asked for (the import
# page, the docs, the MCP tool). For a team it also lists the activities and
# steps already on its maps, so the file can suggest places that exist.
module ImportInstructions
  EXAMPLE = JSON.parse(<<~JSON).freeze
    {
      "mainline": 1,
      "map": "Online shop",
      "personas": ["Shopper"],
      "activities": [
        { "name": "Check out", "personas": ["Shopper"], "steps": ["Enter details", "Pay"] }
      ],
      "entries": [
        {
          "key": "SHOP-GUEST-01",
          "title": "Guests can check out without an account",
          "source": "Checkout specification, section 4.2",
          "why": "A third of baskets are abandoned at the sign-up page.",
          "suggested": { "activity": "Check out", "step": "Enter details" },
          "draft_scenarios": [
            {
              "name": "Guest pays with only an email address",
              "given": "I have items in my basket and no account",
              "when": "I choose to continue as a guest",
              "then": "I can place the order with only my email address"
            }
          ]
        }
      ]
    }
  JSON

  BREAKDOWN = <<~TEXT.freeze
    # Writing a Mainline import file

    You are turning a specification, a plan or research into a Mainline import file. Mainline is a project tool built around a user story map. The file proposes stories. A person will read each one in Mainline and decide what to keep, reword or drop, so write for that reader.

    ## What to produce

    One JSON file and nothing else. It must pass the JSON Schema at the end of these instructions. A file that fails is refused whole, with a list of what to correct.

    ## How to break the work down

    - Each entry is one story: a small change that someone using the product can see or do, and that could be released on its own.
    - Write the title as what someone can do or see, such as "Guests can check out without an account". A title that names a ticket, a layer or a task, such as "Add an API endpoint", is not a story yet.
    - Give each story one to three scenarios. Each has a name, a given, a when and a then. A story that needs more than five scenarios is two stories.
    - A given, a when or a then is one short line of at most #{AddScenario::MAX_LENGTH} characters. A scenario's name is at most #{AddScenario::NAME_LENGTH}.
    - Put the entries in the order they would be built, with the thinnest working version of the product first.
    - Give every entry a `source` saying where in the document it came from, and a `why`.
    - Give every entry a `key` of your own, such as SHOP-GUEST-01. When you revise a file you wrote before, keep every entry's key as it was. Mainline then refreshes the entry and does not add it a second time.
    - A file holds at most #{MainlineFile::MAX_ENTRIES} entries. Fewer is better: propose what would be built first.
  TEXT

  BACKBONE = <<~TEXT
    ## The map

    A story sits under a step, and a step under an activity. Activities run left to right in the order someone meets them. To propose a map, name the `map`, list its `personas`, and give its `activities`, each with the personas it is for and its `steps`. Give each entry a `suggested` activity and step.
  TEXT

  def self.for(team_id:)
    [BREAKDOWN, BACKBONE, existing(team_id), block('An example', EXAMPLE),
     block('The schema', JSON.parse(File.read(MainlineFile::SCHEMA_PATH)))].compact.join("\n")
  end

  def self.block(heading, content)
    "## #{heading}\n\n```json\n#{JSON.pretty_generate(content)}\n```\n"
  end

  # The activities and steps already on the team's maps, if it has any.
  def self.existing(team_id)
    return unless team_id

    maps = Map.where(team_id: team_id, archived_at: nil).order(:position).all
    lines = maps.flat_map { |map| ["Map: #{map.name}", *activity_lines(map)] }
    return if lines.empty?

    "This team's maps already have these activities and steps. Where an entry fits one, suggest it, spelled the same way.\n\n" \
      "#{lines.join("\n")}\n"
  end

  def self.activity_lines(map)
    steps = Task.where(map_id: map.id, archived_at: nil).order(:position).select_map(%i[activity_id name])
    Activity.where(map_id: map.id, archived_at: nil).order(:position).map do |activity|
      "- #{activity.name}: #{steps.select { |activity_id, _| activity_id == activity.id }.map(&:last).join(', ')}"
    end
  end
  private_class_method :block, :existing, :activity_lines
end
