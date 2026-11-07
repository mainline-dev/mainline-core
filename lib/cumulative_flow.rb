# frozen_string_literal: true

module CumulativeFlow
  Result = Struct.new(:dates, :planned, :active, :deployed, :released, keyword_init: true)

  ENTITY_TYPE = RecordEvent.entity_type_for(Story).freeze
  LIFECYCLE_ACTIONS = %w[created activated deployed deactivated released archived].freeze
  ACTION_TO_STATE = {
    'created' => :planned, 'deactivated' => :planned,
    'activated' => :active, 'deployed' => :deployed, 'released' => :released
  }.freeze
  EMPTY = Result.new(dates: [], planned: [], active: [], deployed: [], released: []).freeze

  def self.call(team_id:, days: 30, map_id: nil)
    end_date = Date.today
    start_date = days ? end_date - days : nil

    story_states = start_date ? baseline_states(team_id, start_date, map_id) : {}
    window_rows = window_rows(team_id, start_date, map_id)

    return EMPTY if story_states.empty? && window_rows.empty?

    window_start = start_date || (window_rows.any? ? window_rows.first[:day] : end_date)
    tally(story_states, window_rows.group_by { |r| r[:day] }, window_start..end_date)
  end

  def self.baseline_states(team_id, start_date, map_id)
    sql = <<~SQL
      SELECT DISTINCT ON (entity_id) entity_id, action AS last_action
        FROM events
       WHERE team_id = ?
         AND entity_type = ?
         AND action = ANY(?)
         AND occurred_at < ?::date
         #{'AND map_id = ?' if map_id}
       ORDER BY entity_id, event_no DESC
    SQL
    params = [team_id, ENTITY_TYPE, Sequel.pg_array(LIFECYCLE_ACTIONS), start_date]
    params << map_id if map_id

    DB[sql, *params].all.each_with_object({}) do |row, states|
      state = ACTION_TO_STATE[row[:last_action]]
      states[row[:entity_id]] = state if state
    end
  end

  def self.window_rows(team_id, start_date, map_id)
    sql = <<~SQL
      SELECT entity_id,
             occurred_at::date AS day,
             (ARRAY_AGG(action ORDER BY event_no DESC))[1] AS last_action
        FROM events
       WHERE team_id = ?
         AND entity_type = ?
         AND action = ANY(?)
         #{'AND occurred_at >= ?::date' if start_date}
         #{'AND map_id = ?' if map_id}
       GROUP BY entity_id, occurred_at::date
       ORDER BY day, entity_id
    SQL
    params = [team_id, ENTITY_TYPE, Sequel.pg_array(LIFECYCLE_ACTIONS)]
    params << start_date if start_date
    params << map_id if map_id
    DB[sql, *params].all
  end

  def self.tally(story_states, rows_by_date, date_range)
    series = { dates: [], planned: [], active: [], deployed: [], released: [] }

    date_range.each do |date|
      apply_day(story_states, rows_by_date[date] || [])
      counts = story_states.values.tally
      series[:dates] << date
      %i[planned active deployed released].each { |s| series[s] << counts.fetch(s, 0) }
    end

    Result.new(**series)
  end

  def self.apply_day(story_states, rows)
    rows.each do |row|
      state = ACTION_TO_STATE[row[:last_action]]
      if state
        story_states[row[:entity_id]] = state
      else
        story_states.delete(row[:entity_id])
      end
    end
  end

  private_class_method :baseline_states, :window_rows, :tally, :apply_day
end
