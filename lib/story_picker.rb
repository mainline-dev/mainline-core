# frozen_string_literal: true

# Finds stories across a team's maps for an exhibit to be added to: open stories
# whose title has every word typed, grouped by map, in the order of the maps.
# When Jira links an exhibit to one already promoted, that story is suggested.
module StoryPicker
  LIMIT = 50
  MAX_WORDS = 10
  STATES = { 'active' => 'in progress' }.freeze

  Hit = Struct.new(:id, :title, :meta, keyword_init: true)
  Suggestion = Struct.new(:story_id, :key, :title, keyword_init: true)

  # Returns [[map name, hits], ...].
  def self.call(team_id:, query:, suggested: nil)
    rows = matching(open_stories(team_id), query).limit(LIMIT).all
    rows = with_suggested(team_id, rows, suggested) if suggested && query.to_s.strip.empty?
    relics = MuseumItem.where(story_id: rows.map { |row| row[:id] }).naked.group_and_count(:story_id).as_hash(:story_id, :count)
    rows.group_by { |row| [row[:map_id], row[:map_name]] }.map { |(_id, name), found|
      [name, found.map { |row| Hit.new(id: row[:id], title: row[:title], meta: meta(row, relics[row[:id]].to_i)) }]
    }
  end

  # The first promoted exhibit that Jira links any of these to, if its story is open.
  def self.suggestion(items:)
    keys = items.flat_map { |item| item.links.to_a.filter_map { |link| link['key'] } }
    return if keys.empty?

    linked = MuseumItem.where(team_id: items.first.team_id, source_key: keys).exclude(story_id: nil).order(:source_key).eager(:story).all
    found = linked.find { |item| item.story.archived_at.nil? }
    found && Suggestion.new(story_id: found.story_id, key: found.source_key, title: found.story.title)
  end

  # The suggested story comes first, fetched if the limit left it out.
  def self.with_suggested(team_id, rows, suggested)
    rest, found = rows.partition { |row| row[:id] != suggested }
    found = open_stories(team_id).where(Sequel[:stories][:id] => suggested).all if found.empty?
    found + rest
  end

  def self.open_stories(team_id)
    stories = Sequel[:stories]
    tasks = Sequel[:tasks]
    activities = Sequel[:activities]
    maps = Sequel[:maps]
    Story.naked.join(:tasks, id: stories[:task_id]).join(:activities, id: tasks[:activity_id]).join(:maps, id: stories[:map_id])
      .where(stories[:team_id] => team_id, stories[:archived_at] => nil, tasks[:archived_at] => nil,
        activities[:archived_at] => nil, maps[:archived_at] => nil)
      .order(maps[:position], activities[:position], tasks[:position], stories[:position])
      .select(stories[:id], stories[:title], stories[:status], tasks[:name].as(:task_name),
        activities[:name].as(:activity_name), maps[:id].as(:map_id), maps[:name].as(:map_name))
  end

  def self.matching(stories, query)
    query.to_s.split.first(MAX_WORDS).reduce(stories) { |found, word|
      found.where(Sequel.ilike(Sequel[:stories][:title], "%#{found.escape_like(word)}%"))
    }
  end

  def self.meta(row, relics)
    parts = ["#{row[:activity_name]} / #{row[:task_name]}", STATES.fetch(row[:status], row[:status])]
    parts << "#{relics} #{relics == 1 ? 'relic' : 'relics'}" if relics.positive?
    parts.join(' · ')
  end
  private_class_method :with_suggested, :open_stories, :matching, :meta
end
