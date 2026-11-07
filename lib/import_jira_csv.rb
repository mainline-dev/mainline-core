# frozen_string_literal: true

require 'time'
require_relative 'jira_csv'
require_relative 'record_event'

# Brings a Jira CSV export into the team's Ticket Museum in two steps. Staging
# reads the file and keeps what it found, changing nothing in the museum, so
# the preview can show what importing would do. Importing then adds new items
# and refreshes the rest; items already promoted onto a map, or discarded, are
# left as they are. A staged upload can be cancelled instead. The most recent
# import can be undone: what it added is removed and what it refreshed is put
# back, except items promoted or discarded since. Importing another makes the
# earlier ones final, and what they remembered is let go.
module ImportJiraCsv
  Staged = Struct.new(:success?, :errors, :missing_columns, :import, keyword_init: true)
  Result = Struct.new(:success?, :errors, :added, :updated, :finished, :promoted, :discarded, :skipped, keyword_init: true)
  Preview = Struct.new(:added, :updated, :finished, :promoted, :discarded, :skipped, keyword_init: true)
  Undone = Struct.new(:success?, :errors, :removed, :restored, :kept, keyword_init: true)

  MAX_ITEMS = 20_000
  STALE_AFTER = 24 * 60 * 60
  JSON_COLUMNS = %i[labels comments links].freeze
  REMEMBERED = %i[issue_type summary description in_progress parent_key labels comments links source_created_at
                  source_updated_at].freeze
  REFRESHED = (REMEMBERED + [:updated_at]).freeze

  # Stages a file for review. One file waits at a time: an earlier one still
  # waiting is turned down.
  def self.stage(team:, actor:, csv:, file_name:)
    read = JiraCsv.read(csv)
    return Staged.new(success?: false, errors: read.errors, missing_columns: read.missing_columns) unless read.success?

    import = DB.transaction {
      MuseumImport.where(team_id: team.id, status: 'staged').update(status: 'cancelled', items: nil, updated_at: Time.now)
      MuseumImport.create(
        team_id: team.id, actor_id: actor.id, file_name: file_name.to_s[0, 255].then { |name| name.empty? ? 'upload.csv' : name },
        status: 'staged', header: Sequel.pg_jsonb(read.header), items: Sequel.pg_jsonb(read.items),
        problems: Sequel.pg_jsonb(read.problems), finished: read.finished, skipped: read.problems.size
      )
    }
    Staged.new(success?: true, errors: [], missing_columns: [], import: import)
  end

  def self.preview(import)
    Preview.new(**counts(import), finished: import.finished, skipped: import.skipped)
  end

  def self.apply(import:, actor:)
    DB.transaction do
      one_at_a_time(import.team_id)
      import = MuseumImport.where(id: import.id).for_update.first
      next failure('This file has already been acquired or turned down') unless import.status == 'staged'

      counts = counts(import)
      next failure('A museum holds up to 20,000 exhibits') if over_limit?(import.team_id, counts[:added])

      previous = previous(import)
      store(import.team_id, import.items.to_a)
      import.update(status: 'imported', imported_at: Time.now, items: nil, previous: Sequel.pg_jsonb(previous), **counts)
      MuseumImport.where(team_id: import.team_id, status: 'imported').exclude(id: import.id).update(previous: nil)
      RecordEvent.call(actor_id: actor.id, entity: import, action: 'imported',
        after_state: counts.merge(file_name: import.file_name, finished: import.finished, skipped: import.skipped))
      Result.new(success?: true, errors: [], **counts, finished: import.finished, skipped: import.skipped)
    end
  end

  def self.undo(import:, actor:)
    DB.transaction do
      one_at_a_time(import.team_id)
      import = MuseumImport.where(id: import.id).for_update.first
      next failure('Only the most recent acquisition can be returned') unless undoable?(import)

      counts = revert(import.team_id, import.previous.to_h)
      import.update(status: 'undone', undone_at: Time.now, previous: nil)
      RecordEvent.call(actor_id: actor.id, entity: import, action: 'undone', after_state: counts.merge(file_name: import.file_name))
      Undone.new(success?: true, errors: [], **counts)
    end
  end

  # Acquisitions and returns for one team happen one after another, so what
  # each records as added or refreshed is true when its undo reads it back.
  def self.one_at_a_time(team_id)
    DB.get(Sequel.function(:pg_advisory_xact_lock, Sequel.function(:hashtext, team_id.to_s)))
  end

  def self.undoable?(import)
    import.status == 'imported' && undoable_id(import.team_id) == import.id
  end

  # The one acquisition that can still be returned: the latest, while it keeps
  # what it changed. Acquiring another makes the earlier ones final.
  def self.undoable_id(team_id)
    MuseumImport.where(team_id: team_id, status: 'imported').exclude(previous: nil).reverse(:imported_at).get(:id)
  end

  def self.cancel(import:)
    DB.transaction do
      import = MuseumImport.where(id: import.id).for_update.first
      next failure('This file has already been acquired or turned down') unless import.status == 'staged'

      import.update(status: 'cancelled', items: nil)
      Result.new(success?: true, errors: [])
    end
  end

  # Cancels uploads staged before the given time and never imported.
  def self.clear_stale(before:)
    MuseumImport.where(status: 'staged').where { created_at < before }.update(status: 'cancelled', items: nil, updated_at: Time.now)
  end

  # What importing the staged items would do to the museum as it is now.
  def self.counts(import)
    keys = import.items.map { |item| item['source_key'] }
    existing = MuseumItem.where(team_id: import.team_id, source_key: keys).select_map(%i[promoted_at discarded_at])
    promoted = existing.count { |promoted_at, _discarded_at| promoted_at }
    discarded = existing.count { |_promoted_at, discarded_at| discarded_at }
    { added: keys.size - existing.size, updated: existing.size - promoted - discarded, promoted: promoted, discarded: discarded }
  end

  # Each key the import will change: nil for one it adds, or the item as it
  # was for one it refreshes. Promoted and discarded items are not changed.
  def self.previous(import)
    keys = import.items.map { |item| item['source_key'] }
    existing = MuseumItem.where(team_id: import.team_id, source_key: keys).all.to_h { |item| [item.source_key, item] }
    keys.each_with_object({}) { |key, previous|
      item = existing[key]
      next if item && (item.promoted_at || item.discarded_at)

      previous[key] = item && remembered(item)
    }
  end

  def self.remembered(item)
    REMEMBERED.to_h { |column| [column, item[column]] }
      .merge(labels: item.labels.to_a, comments: item.comments.to_a, links: item.links.to_a,
        source_created_at: item.source_created_at&.iso8601, source_updated_at: item.source_updated_at&.iso8601)
  end

  def self.revert(team_id, previous)
    items = MuseumItem.where(team_id: team_id, source_key: previous.keys).all
    kept, changeable = items.partition { |item| item.promoted_at || item.discarded_at }
    removed, restored = changeable.partition { |item| previous[item.source_key].nil? }
    MuseumItem.where(id: removed.map(&:id)).delete
    now = Time.now
    restored.each do |item|
      MuseumItem.where(id: item.id).update(row(previous[item.source_key], team_id, now).except(:team_id, :created_at))
    end
    { removed: removed.size, restored: restored.size, kept: kept.size }
  end

  def self.over_limit?(team_id, added)
    MuseumItem.where(team_id: team_id).count + added > MAX_ITEMS
  end

  def self.store(team_id, items)
    now = Time.now
    rows = items.map { |item| row(item, team_id, now) }
    MuseumItem.dataset.insert_conflict(
      target:       %i[team_id source_key],
      update:       REFRESHED.to_h { |column| [column, Sequel[:excluded][column]] },
      update_where: { Sequel[:museum_items][:promoted_at] => nil, Sequel[:museum_items][:discarded_at] => nil }
    ).multi_insert(rows, slice: 1000)
  end

  def self.row(item, team_id, now)
    row = item.to_h.transform_keys(&:to_sym)
    JSON_COLUMNS.each { |column| row[column] = Sequel.pg_jsonb(row[column].to_a) }
    row.merge(team_id: team_id, created_at: now, updated_at: now,
      source_created_at: row[:source_created_at] && Time.iso8601(row[:source_created_at]),
      source_updated_at: row[:source_updated_at] && Time.iso8601(row[:source_updated_at]))
  end

  def self.failure(message)
    Result.new(success?: false, errors: [message])
  end
  private_class_method :counts, :previous, :remembered, :revert, :over_limit?, :store, :row, :failure
end
