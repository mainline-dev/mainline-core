# frozen_string_literal: true

require_relative 'museum_list'
require_relative 'record_event'

# What the museum list says about the curator's suggestions. It only asks for a
# review once there is enough to review, and Not now holds it back for a while.
# Right after an acquisition the list watches for a short time, since the
# curator looks in the background.
module LetGoPrompt
  AT_LEAST = 10
  SHARE = 10
  SNOOZE = 30 * 24 * 60 * 60
  WATCH_TRIES = 15

  Prompt = Struct.new(:counts, keyword_init: true) do
    def total
      counts.values.sum
    end

    def breakdown
      all = parts
      return all.join(' and ') if all.size < 3

      "#{all[0..-2].join(', ')}, and #{all.last}"
    end

    private

    def parts
      stale, dupes, repro = counts.values_at('stale', 'dupes', 'repro').map(&:to_i)
      others = counts['vague'].to_i + counts['covered'].to_i
      [("#{stale} untouched for over a year" if stale.positive?),
       ("#{dupes} #{dupes == 1 ? 'duplicate' : 'duplicates'}" if dupes.positive?),
       ("#{repro} #{repro == 1 ? 'bug' : 'bugs'} nobody could reproduce" if repro.positive?),
       ("#{others} that #{others == 1 ? 'is' : 'are'} too vague or already covered" if others.positive?)].compact
    end
  end

  # The prompt to show, or nil if the list should say nothing.
  def self.call(team:)
    return if team.let_go_snoozed_until && team.let_go_snoozed_until > Time.now

    on_display = MuseumList.on_display(team.id)
    counts = on_display.where(kept_at: nil).exclude(let_go_group: nil).naked.group_and_count(:let_go_group).as_hash(:let_go_group, :count)
    counts['dupes'] /= 2 if counts['dupes']
    prompt = Prompt.new(counts: counts)
    prompt if prompt.total >= AT_LEAST && prompt.total * 100 >= on_display.count * SHARE
  end

  def self.snooze(team:, actor:)
    DB.transaction do
      team.update(let_go_snoozed_until: Time.now + SNOOZE)
      RecordEvent.call(actor_id: actor.id, entity: team, action: 'let_go_snoozed', team_id: team.id)
    end
  end
end
