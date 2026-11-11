# frozen_string_literal: true

require_relative 'discard_museum_item'
require_relative 'let_go'
require_relative 'museum_list'

# The curator's suggestions as a person reviews them: by group, each with the
# evidence for it, and nothing goes unless it was ticked. An exhibit let go lands
# in storage with its group's id as the note. Only the first few of a group
# are shown; whatever was not shown goes together or not at all. An exhibit kept
# is never suggested again, until that is undone. Duplicates come as pairs: the
# side with more detail stays by default, and a pair counts as one suggestion.
# What goes together is a batch: its storage events share an id, and it can be
# brought back as one.
module LetGoReview
  SHOWN = 5
  PAIRS_SHOWN = 2
  PAGE = 50
  QUOTE = 50
  LINK_WORDS = { 'blocks' => 'Blocks', 'relates' => 'Relates to' }.freeze

  GROUPS = {
    'stale'   => {
      title: 'Untouched for over a year',
      why:   'No progress, no comments and no edits in a year. The team has got by without it all that time.',
      rule:  'created > 12 months ago · no comment or edit in 12 months · not in progress'
    },
    'dupes'   => {
      title: 'Probably the same ticket twice',
      why:   'Near-identical summaries. Keep the one with more detail and let the other go.',
      rule:  'summary similarity ≥ 0.8 · same type'
    },
    'repro'   => {
      title: 'Bugs nobody could reproduce',
      why:   "Someone said it couldn't be reproduced, and nothing happened after that.",
      rule:  %(type = Bug · a comment matches "can't reproduce" · no later activity)
    },
    'vague'   => {
      title: 'Too vague to act on',
      why:   'A few words and no description, so anyone picking it up would have to guess what was meant.',
      rule:  'summary ≤ 3 words · description empty'
    },
    'covered' => {
      title: 'Already covered by a promoted story',
      why:   'They are linked to an exhibit you have already promoted, and they add no behaviour of their own.',
      rule:  'linked to a promoted exhibit · type is Sub-task or Task'
    }
  }.freeze

  Outcome = Struct.new(:gone, :batch, keyword_init: true)

  Suggestion = Struct.new(:item, :evidence, keyword_init: true) do
    def going
      self
    end

    def ticked(ids)
      ids.include?(item.id) ? [self] : []
    end

    def in?(seen)
      seen.include?(item.id)
    end
  end

  Pair = Struct.new(:keeper, :other, keyword_init: true) do
    def going
      other
    end

    # Never both sides, whatever was sent.
    def ticked(ids)
      [other, keeper].select { |side| ids.include?(side.item.id) }.first(1)
    end

    def in?(seen)
      keeper.in?(seen) || other.in?(seen)
    end

    def name
      [keeper.item.source_key, other.item.source_key].min
    end
  end

  Group = Struct.new(:id, :title, :why, :rule, :suggestions, keyword_init: true) do
    def shown
      suggestions.first(limit)
    end

    def rest
      suggestions.drop(limit)
    end

    def limit
      id == 'dupes' ? PAIRS_SHOWN : SHOWN
    end
  end

  def self.groups(team_id:)
    stories = promoted_stories(team_id)
    by_group = MuseumList.on_display(team_id).where(kept_at: nil).exclude(let_go_group: nil).all.group_by(&:let_go_group)
    GROUPS.filter_map do |id, words|
      items = by_group.fetch(id, [])
      found = id == 'dupes' ? pairs(items) : suggestions(items, stories)
      Group.new(id: id, suggestions: found, **words) unless found.empty?
    end
  end

  # The title of a group, for a reason kept by id.
  def self.title(id)
    GROUPS.dig(id, :title) || id
  end

  # One exhibit as a suggestion, whether or not it is still on offer.
  def self.suggestion(item)
    Suggestion.new(item: item, evidence: evidence(item, promoted_stories(item.team_id)))
  end

  # Sends the ticked suggestions (and whatever was not shown of any group named
  # in rest) to storage as one batch, and keeps both sides of the pairs named in
  # keep.
  def self.let_go(team_id:, actor:, ids:, seen: [], rest: [], keep: [])
    found = groups(team_id: team_id)
    DB.transaction {
      keep_pairs(found, keep, actor)
      going = chosen(found, ids, seen + ids, rest)
      sent = DiscardMuseumItem.many(items: going.map(&:first), actor: actor, notes: going.to_h { |item, note| [item.id, note] })
      Outcome.new(gone: sent.stored, batch: sent.batch)
    }
  end

  def self.undo(team_id:, actor:, batch:)
    DiscardMuseumItem.restore_batch(team_id: team_id, actor: actor, batch: batch)
  end

  def self.keep(item:, actor:)
    set_kept(item, actor, Time.now, 'kept')
  end

  def self.unkeep(item:, actor:)
    set_kept(item, actor, nil, 'unkept')
  end

  def self.set_kept(item, actor, kept_at, action)
    DB.transaction do
      item.update(kept_at: kept_at)
      RecordEvent.call(actor_id: actor.id, entity: item, action: action, after_state: { source_key: item.source_key })
    end
  end

  def self.keep_pairs(found, names, actor)
    pairs = found.find { |group| group.id == 'dupes' }&.suggestions.to_a
    pairs.select { |pair| names.include?(pair.name) }.each do |pair|
      [pair.keeper, pair.other].each { |side| keep(item: side.item, actor: actor) }
    end
  end

  def self.chosen(found, ids, seen, rest)
    found.flat_map { |group|
      shown, hidden = group.suggestions.partition { |suggestion| suggestion.in?(seen) }
      picked = shown.flat_map { |suggestion| suggestion.ticked(ids) }
      picked += hidden.map(&:going) if rest.include?(group.id)
      picked.map { |suggestion| [suggestion.item, group.id] }
    }
  end

  def self.suggestions(items, stories)
    in_order = items.sort_by { |item| [item.source_key[/\A\D+/], item.source_key[/\d+\z/].to_i] }
    in_order.filter_map { |item|
      found = evidence(item, stories)
      Suggestion.new(item: item, evidence: found) if found
    }
  end

  # Both sides still on offer, the longer description first, then the first key.
  def self.pairs(items)
    suggestions(items, {}).group_by { |one| [one.item.source_key, one.item.let_go_pair_key].min }.values
      .select { |sides| sides.size == 2 }
      .map { |sides|
        keeper, other = sides.sort_by.with_index { |one, index| [-one.item.description.length, index] }
        Pair.new(keeper: keeper, other: other)
      }
  end

  def self.evidence(item, stories)
    case item.let_go_group
    when 'stale' then stale_evidence(item)
    when 'dupes' then pair_evidence(item)
    when 'repro' then repro_evidence(item)
    when 'vague' then vague_evidence(item)
    when 'covered' then covered_evidence(item, stories)
    end
  end

  def self.stale_evidence(item)
    last = item.comments.to_a.filter_map { |comment| comment['at'] }.max
    "Created #{month(item.source_created_at)} · #{last ? "last comment #{month(Time.iso8601(last))}" : 'never commented'}"
  end

  def self.pair_evidence(item)
    words = item.description.split.size
    "#{words.zero? ? 'No description' : count(words, 'word')} · #{count(item.comments.to_a.size, 'comment')}"
  end

  # The evidence for one exhibit, or nil when what the curator saw has gone since.
  def self.repro_evidence(item)
    comment = item.comments.to_a.last
    return unless comment

    text = comment['text']
    text = "#{text[0, QUOTE].rstrip}..." if text.length > QUOTE
    %("#{text}" #{month(Time.iso8601(comment['at'])) if comment['at']}).rstrip
  end

  def self.vague_evidence(item)
    "No description · #{count(item.labels.to_a.size, 'label')}"
  end

  def self.covered_evidence(item, stories)
    return %(Parent #{item.parent_key} → "#{stories[item.parent_key]}") if stories[item.parent_key]

    link = item.links.to_a.find { |one| stories[one['key']] && LINK_WORDS[one['type'].to_s.downcase] }
    return unless link

    %(#{LINK_WORDS[link['type'].to_s.downcase]} #{link['key']} → "#{stories[link['key']]}")
  end

  def self.count(number, noun)
    "#{number.zero? ? 'no' : number} #{noun}#{'s' unless number == 1}"
  end

  def self.month(time)
    time.strftime('%b %Y')
  end

  def self.promoted_stories(team_id)
    MuseumItem.where(team_id: team_id).exclude(story_id: nil).eager(:story).all
      .to_h { |item| [item.source_key, item.story.title] }
  end
  private_class_method :set_kept, :keep_pairs, :chosen, :suggestions, :pairs, :evidence, :stale_evidence, :pair_evidence,
    :repro_evidence, :vague_evidence, :covered_evidence, :count, :month, :promoted_stories
end
