# frozen_string_literal: true

require 'date'

# One page of a team's Ticket Museum. Epics are not listed: they are offered
# as a filter on their children. Sub-tasks are not listed either: they come
# back grouped under their parent, unless their parent is not in the museum.
# Epics and sub-tasks are known by Jira's default type names. The list shows
# the exhibits on display (neither promoted nor stored) unless a status asks
# for the promoted ones, the stored ones, the kept ones (on display, held back
# from the curator), or everything. A search finds the
# items whose key, summary or description contain every word typed, up to ten
# words. The catalogue counts the whole museum by status, whatever the filters.
# Exhibits let go carry the reason they were stored, and storage can be narrowed
# to one reason.
module MuseumList
  Catalogue = Struct.new(:on_display, :promoted, :stored, keyword_init: true) do
    def total
      on_display + promoted + stored
    end
  end

  # What the list found, with the menus and counts worked out on first use,
  # so a swap of the rows alone pays for the rows alone.
  # The datasets a page was cut from: the team's items, the listed ones, and
  # those matching the filters, with the status asked for.
  Scope = Struct.new(:status, :all, :listed, :matching, keyword_init: true)

  class Page
    attr_reader :items, :sub_tasks, :total, :page, :pages

    def initialize(items:, sub_tasks:, total:, page:, pages:, scope:)
      @items = items
      @sub_tasks = sub_tasks
      @total = total
      @page = page
      @pages = pages
      @scope = scope
    end

    def types
      @types ||= MuseumList.by_status(@scope.listed, @scope.status).distinct.order(:issue_type).select_map(:issue_type)
    end

    def labels
      @labels ||= MuseumList.labels(@scope.all)
    end

    # Where the museum's exhibits came from. Worth offering as a filter only
    # when there is more than one.
    def sources
      @sources ||= @scope.all.distinct.order(:source).select_map(:source)
    end

    def epics
      @epics ||= @scope.all.where(EPIC).order(:summary, :source_key).all
    end

    def promoted_matches
      @promoted_matches ||= MuseumList.promoted(@scope.matching).count
    end

    def stored_matches
      @stored_matches ||= MuseumList.stored(@scope.matching).count
    end

    def catalogue
      @catalogue ||= MuseumList.catalogue(@scope.listed)
    end

    def whys
      @whys ||= MuseumList.stored(@scope.listed).exclude(storage_note: nil).distinct.order(:storage_note).select_map(:storage_note)
    end
  end

  PER_PAGE = 100
  AGES = %w[under-3-months 3-to-12-months over-a-year].freeze
  EPIC = Sequel.ilike(:issue_type, 'epic')
  SUB_TASK = Sequel.like(:issue_type, /^sub-?task$/i)
  SEARCHED = %i[source_key summary description].freeze
  MAX_SEARCH_WORDS = 10

  def self.call(team_id:, status: nil, page: 1, **filters)
    items = MuseumItem.where(team_id: team_id)
    listed = listed(items)
    matching = filter(listed, **filters)
    shown = by_status(matching, status)
    total = shown.count
    pages = [(total + PER_PAGE - 1) / PER_PAGE, 1].max
    page = page.clamp(1, pages)
    rows = shown
      .order(Sequel.desc(:in_progress), Sequel.desc(:source_created_at, nulls: :last), :source_key)
      .limit(PER_PAGE, (page - 1) * PER_PAGE).eager(:story).all

    Page.new(items: rows, sub_tasks: sub_tasks(items, rows), total: total, page: page, pages: pages,
      scope: Scope.new(status: status, all: items, listed: listed, matching: matching))
  end

  def self.by_status(items, status)
    case status
    when 'promoted' then promoted(items)
    when 'in-storage' then stored(items)
    when 'everything' then items
    when 'kept' then displayed(items).exclude(kept_at: nil)
    else displayed(items)
    end
  end

  def self.displayed(items)
    items.where(promoted_at: nil, discarded_at: nil)
  end

  def self.promoted(items)
    items.exclude(promoted_at: nil)
  end

  def self.stored(items)
    items.exclude(discarded_at: nil)
  end

  def self.catalogue(listed)
    Catalogue.new(on_display: by_status(listed, nil).count, promoted: promoted(listed).count, stored: stored(listed).count)
  end

  # The team's exhibits on display: listed, neither promoted nor stored.
  def self.on_display(team_id)
    displayed(listed(MuseumItem.where(team_id: team_id)))
  end

  def self.listed(items)
    in_museum = items.exclude(EPIC).select(:source_key)
    items.exclude(EPIC).where(Sequel.|(Sequel.~(SUB_TASK), Sequel.~(parent_key: in_museum), { parent_key: nil }))
  end

  def self.filter(items, type: nil, label: nil, epic: nil, age: nil, search: nil, why: nil, source: nil)
    items = search(items, search)
    items = items.where(source: source) if source
    items = items.where(storage_note: why) if why
    items = items.where(issue_type: type) if type
    items = items.where(Sequel.lit('labels @> ?', Sequel.pg_jsonb([label]))) if label
    items = items.where(parent_key: epic) if epic
    AGES.include?(age) ? by_age(items, age) : items
  end

  def self.search(items, query)
    query.to_s.split.first(MAX_SEARCH_WORDS).reduce(items) { |found, word|
      pattern = "%#{found.escape_like(word)}%"
      found.where(Sequel.|(*SEARCHED.map { |column| Sequel.ilike(column, pattern) }))
    }
  end

  def self.by_age(items, age)
    now = Time.now.to_datetime
    three_months = (now << 3).to_time
    a_year = (now << 12).to_time
    case age
    when 'under-3-months' then items.where { source_created_at > three_months }
    when '3-to-12-months' then items.where { (source_created_at <= three_months) & (source_created_at > a_year) }
    else items.where { source_created_at <= a_year }
    end
  end

  def self.sub_tasks(items, rows)
    items.where(SUB_TASK).where(parent_key: rows.map(&:source_key)).order(:source_key).all.group_by(&:parent_key)
  end

  def self.labels(items)
    items.distinct.order(:label).select_map(Sequel.function(:jsonb_array_elements_text, :labels).as(:label))
  end
  private_class_method :listed, :displayed, :filter, :search, :by_age, :sub_tasks
end
