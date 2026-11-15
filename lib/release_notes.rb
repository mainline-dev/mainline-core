# frozen_string_literal: true

# A slice's release notes: the stories released in it, oldest release first,
# each with the day it was released and its scenarios, as markdown for people
# outside the team. It only formats; the stories stay the source.
module ReleaseNotes
  def self.for(slice)
    stories = released(slice.id).order(:released_at).all
    scenarios = Scenario.where(story_id: stories.map(&:id)).order(:position).all.group_by(&:story_id)
    sections = stories.map { |story| section(story, scenarios.fetch(story.id, [])) }
    ["# #{one_line(slice.name)}\n", *sections].join("\n")
  end

  def self.file_name(slice)
    slug = slice.name.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-|-\z/, '')
    slug.empty? ? 'release-notes.md' : "#{slug}-release-notes.md"
  end

  # Which of these slices have a released story to write up, by ID.
  def self.offered(slices)
    released(slices.map(&:id)).select_map(:release_slice_id).to_set
  end

  def self.released(slice_ids)
    Story.where(release_slice_id: slice_ids, status: 'released', archived_at: nil)
  end

  def self.section(story, scenarios)
    lines = ["## #{one_line(story.title)}", "Released #{story.released_at.strftime('%-d %B %Y')}"]
    lines += ['', *scenarios.map { |scenario| scenario_line(scenario) }] if scenarios.any?
    "#{lines.join("\n")}\n"
  end

  def self.scenario_line(scenario)
    "- Given #{one_line(scenario.given_text)}, when #{one_line(scenario.when_text)}, then #{one_line(scenario.then_text)}"
  end

  # A line break inside a title or step would break the markdown.
  def self.one_line(text)
    text.split.join(' ')
  end

  private_class_method :released, :section, :scenario_line, :one_line
end
