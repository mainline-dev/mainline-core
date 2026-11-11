# frozen_string_literal: true

require 'date'
require_relative 'museum_list'

# The curator's suggestions of exhibits to let go, by plain rules. Each exhibit
# on display, not kept and not in progress, goes in the first group whose rule
# it fits; every other exhibit is cleared. Duplicates come in pairs, each
# marked with its twin, and an exhibit is in one pair at most. Run after each
# acquisition and nightly. Returns the number of suggestions in each group,
# counting a pair as one. The rules are about old tickets, so of them only the
# duplicates rule ever fits an entry proposed from a specification.
module LetGo
  GROUPS = %w[stale dupes repro vague covered].freeze
  SIMILAR = 0.8
  NOT_REPRODUCED = /can'?t reproduce|cannot reproduce|couldn'?t reproduce|works for me/i
  TASK = /\A(task|sub-?task)\z/i
  COVERING_LINKS = %w[blocks relates].freeze

  def self.detect(team_id:)
    DB.transaction do
      MuseumItem.where(team_id: team_id).exclude(let_go_group: nil).update(let_go_group: nil, let_go_pair_key: nil)
      candidates = MuseumList.on_display(team_id).where(kept_at: nil, in_progress: false)
      items = candidates.all
      stale = items.select { |item| stale?(item) }
      pairs = pairs(candidates, stale.to_set(&:source_key))
      paired = pairs.flatten.to_set
      rest = items - stale
      rest = rest.reject { |item| paired.include?(item.source_key) }
      repro = rest.select { |item| not_reproduced?(item) }
      vague = (rest - repro).select { |item| vague?(item) }
      promoted = promoted_keys(team_id)
      covered = (rest - repro - vague).select { |item| covered?(item, promoted) }

      mark(team_id, stale: stale, repro: repro, vague: vague, covered: covered, pairs: pairs)
    end
  end

  def self.mark(team_id, pairs:, **groups)
    groups.each { |group, items| MuseumItem.where(id: items.map(&:id)).update(let_go_group: group.to_s) }
    pairs.each do |a, b|
      MuseumItem.where(team_id: team_id, source_key: a).update(let_go_group: 'dupes', let_go_pair_key: b)
      MuseumItem.where(team_id: team_id, source_key: b).update(let_go_group: 'dupes', let_go_pair_key: a)
    end
    { 'stale' => groups[:stale].size, 'dupes' => pairs.size, 'repro' => groups[:repro].size,
      'vague' => groups[:vague].size, 'covered' => groups[:covered].size }.select { |_group, count| count.positive? }
  end

  # Created over a year ago, with no comment and no change in Jira since.
  def self.stale?(item)
    year_ago = (Time.now.to_datetime << 12).to_time
    return false unless item.source_created_at && item.source_created_at < year_ago

    touched = item.comments.to_a.filter_map { |comment| comment['at'] && Time.iso8601(comment['at']) }
    touched << item.source_updated_at if item.source_updated_at
    touched.none? { |at| at >= year_ago }
  end

  # Pairs of the same type whose summaries are almost the same, the closest
  # first, leaving out the stale ones and any exhibit already paired.
  def self.pairs(candidates, stale)
    DB.run("SET LOCAL pg_trgm.similarity_threshold = #{SIMILAR}")
    a = Sequel[:a]
    b = Sequel[:b]
    similar = DB.from(candidates.as(:a))
      .join(candidates, Sequel.&({ a[:issue_type] => b[:issue_type] }, Sequel.lit('a.id < b.id'),
        Sequel.lit('lower(a.summary) % lower(b.summary)')), table_alias: :b)
      .select(a[:source_key].as(:first), b[:source_key].as(:second))
      .order(Sequel.desc(Sequel.function(:similarity, Sequel.function(:lower, a[:summary]), Sequel.function(:lower, b[:summary]))),
        a[:source_key], b[:source_key])
      .map { |row| [row[:first], row[:second]] }
    used = stale.dup
    similar.each_with_object([]) do |pair, pairs|
      next if pair.any? { |key| used.include?(key) }

      used.merge(pair)
      pairs << pair
    end
  end

  # A bug whose last comment says nobody could reproduce it.
  def self.not_reproduced?(item)
    item.issue_type.casecmp?('bug') && item.comments.to_a.last.to_h['text'].to_s.match?(NOT_REPRODUCED)
  end

  # Three words or fewer, and nothing more to go on. An entry proposed from a
  # specification is not judged this way: a short title is how they arrive.
  def self.vague?(item)
    !item.proposed? && item.summary.split.size <= 3 && item.description.strip.empty?
  end

  # A task whose parent, or an issue it blocks or relates to, is promoted.
  def self.covered?(item, promoted)
    return false unless item.issue_type.match?(TASK)

    linked = item.links.to_a.filter_map { |link| link['key'] if COVERING_LINKS.include?(link['type'].to_s.downcase) }
    ([item.parent_key] + linked).any? { |key| promoted.include?(key) }
  end

  def self.promoted_keys(team_id)
    MuseumItem.where(team_id: team_id).exclude(promoted_at: nil).select_map(:source_key).to_set
  end
  private_class_method :mark, :stale?, :pairs, :not_reproduced?, :vague?, :covered?, :promoted_keys
end
