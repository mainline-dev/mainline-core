# frozen_string_literal: true

require 'uri'
require_relative 'import_jira_csv'
require_relative 'promote_museum_item'

# What the Ticket Museum routes share: toasts, the open case, where to go
# back to, and the tasks a story can be promoted under.
class Mainline
  # An exhibit or upload id in a museum path.
  MUSEUM_ID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  # An exhibit's open case: its record, and the rewrite form if it can be promoted.
  def museum_case(item, sub_tasks, return_to)
    @tasks_by_map = promotable_tasks if item.promotable?
    render('teams/museum/_case', locals: { item: item, sub_tasks: sub_tasks, return_to: return_to })
  end

  # The toast after acting on one exhibit: what happened, the story if there is
  # one, and the action that undoes it if there is one.
  def museum_story_fate(archived)
    archived ? 'its story was archived' : 'the story stays on the map'
  end

  def museum_toast(item, words, dot: 'done', story: nil, undo: nil, story_state: nil)
    flash['museum_toast'] = {
      'key' => item.source_key, 'words' => words, 'dot' => dot, 'story_title' => story&.title, 'story_state' => story_state,
      'story_path' => museum_story_path(story),
      'undo_path' => undo && "#{@museum_path}/#{item.id}/#{undo}"
    }
  end

  def museum_strs(name)
    typecast_params.array(:str, name) || []
  end

  # The toast after acting on a number of exhibits at once.
  def museum_count_toast(count, words, dot: 'done', undo: nil, story: nil, story_state: nil)
    flash['museum_toast'] = {
      'words' => "#{count} #{count == 1 ? 'exhibit' : 'exhibits'} #{words}", 'count' => count, 'dot' => dot, 'undo_path' => undo,
      'story_state' => story_state,
      'story_title' => story&.title, 'story_path' => museum_story_path(story)
    }
  end

  def museum_story_path(story)
    story && "/maps/#{story.map_id}/stories/#{story.id}/edit"
  end

  def museum_added_toast(items, result)
    return museum_toast(items.first, 'added to', story: result.story, undo: 'unpromote') if items.size == 1

    museum_count_toast(items.size, 'added to', story: result.story, undo: "#{@museum_path}/added/#{result.batch}/undo")
  end

  # The exhibits to promote together, those that can be, with what the form needs.
  def museum_together(ids)
    @items = MuseumItem.where(team_id: @team.id, id: ids).order(:source_key).all.select(&:promotable?)
    @sub_tasks = MuseumItem.where(team_id: @team.id, parent_key: @items.map(&:source_key)).order(:source_key).all.group_by(&:parent_key)
    @tasks_by_map = promotable_tasks
    @page_title = 'Promote together - Mainline'
  end

  # Hours until an upload left waiting is turned down.
  def museum_hours_left(import)
    [((import.created_at + ImportJiraCsv::STALE_AFTER - Time.now) / 3600).ceil, 1].max
  end

  # Refuses a form sent in place: the error shows and the form stays as it is.
  def museum_refusal(message)
    flash_msg.error(message)
    response['HX-Trigger'] = flash_msg.to_htmx_trigger.to_json
    response['HX-Reswap'] = 'none'
    ''
  end

  # Where to go back to after acting from the list: the page it came from, as
  # long as that is in this team's museum.
  def museum_return_path(path)
    museum = "/teams/#{@team.id}/museum"
    path.to_s.match?(%r{\A#{Regexp.escape(museum)}(?:[/?][^\s]*)?\z}) ? path : museum
  end

  # How a Jira link reads from the exhibit's side: "is blocked by SHOP-14".
  MUSEUM_LINK_WORDS = {
    'blocks' => ['blocks', 'is blocked by'], 'relates' => ['relates to', 'relates to'],
    'duplicate' => ['duplicates', 'is duplicated by'], 'cloners' => ['clones', 'is cloned by']
  }.freeze

  def museum_link_words(link)
    type = link['type'].to_s.downcase
    outward, inward = MUSEUM_LINK_WORDS.fetch(type, [type, "#{type} (from)"])
    link['direction'] == 'inward' ? inward : outward
  end

  # The task this person last promoted under in this team, while it is still one to promote under.
  def remembered_museum_task
    id = session["museum_task:#{@team.id}"]
    id if @tasks_by_map.values.flatten.any? { |task| task[:id] == id }
  end

  MAX_MUSEUM_SCENARIOS = 20

  # Scenario cards as posted (scenarios[0][given] and so on), in order.
  def museum_scenarios(posted)
    cards = posted.is_a?(Hash) ? posted.sort_by { |index, _card| index.to_i }.map(&:last) : Array(posted)
    cards.grep(Hash).first(MAX_MUSEUM_SCENARIOS).map do |card|
      { name: card['name'], given: card['given'], when: card['when'], then: card['then'] }
    end
  end

  def museum_filter_path(changes)
    "#{@museum_path}?#{URI.encode_www_form(@filters.merge(changes))}"
  end

  # Where else a search on display matches, for the no-match state.
  def museum_elsewhere(promoted, stored)
    return if (promoted + stored).zero?

    parts = []
    parts << "#{promoted} #{promoted == 1 ? 'match is' : 'matches are'} already promoted" if promoted.positive?
    if stored.positive?
      subject = stored == 1 ? 'match is' : 'matches are'
      subject = subject.split.last if parts.any?
      parts << "#{stored} #{subject} in storage"
    end
    "#{parts.join(' and ')}."
  end

  def import_notice(result)
    counts = { 'finished left out' => result.finished, 'promoted left as they were' => result.promoted,
               'in storage left as they are' => result.discarded, 'rows turned away' => result.skipped }
    (["#{result.added} new exhibits", "#{result.updated} refreshed from the newer file"] +
      counts.select { |_what, count| count.positive? }.map { |what, count| "#{count} #{what}" }).join(', ')
  end

  # Tasks a museum item can be promoted into, grouped by map in map order.
  def promotable_tasks
    tasks = Sequel[:tasks]
    activities = Sequel[:activities]
    maps = Sequel[:maps]
    PromoteMuseumItem.open_tasks(@team.id)
      .order(maps[:position], activities[:position], tasks[:position])
      .select(tasks[:id], tasks[:name], activities[:name].as(:activity_name), maps[:id].as(:map_id), maps[:name].as(:map_name))
      .naked.all.group_by { |task| [task[:map_id], task[:map_name]] }
  end
end
