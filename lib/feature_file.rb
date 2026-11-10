# frozen_string_literal: true

# A story's scenarios as a Gherkin feature file: the story is the Feature, each
# scenario a named Scenario with its Given, When and Then. The Feature and every
# Scenario carry the story's ID, and each Scenario its own, so test results can
# be traced back. It only formats; the story stays the source.
module FeatureFile
  def self.for(story)
    scenarios = Scenario.where(story_id: story.id).order(:position).all
    blocks = scenarios.map { |scenario| scenario_block(story, scenario) }
    ["@story-#{story.id}\nFeature: #{one_line(story.title)}\n", *blocks].join("\n")
  end

  # A line break inside a title, name or step would start a new Gherkin line.
  def self.one_line(text)
    text.to_s.split.join(' ')
  end

  def self.file_name(story)
    slug = story.title.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-|-\z/, '')
    "#{slug.empty? ? 'story' : slug}.feature"
  end

  def self.scenario_block(story, scenario)
    <<~SCENARIO.gsub(/^/, '  ')
      @story-#{story.id} @scenario-#{scenario.id}
      Scenario: #{one_line(scenario.display_name)}
        Given #{one_line(scenario.given_text)}
        When #{one_line(scenario.when_text)}
        Then #{one_line(scenario.then_text)}
    SCENARIO
  end
  private_class_method :scenario_block
end
