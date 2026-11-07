# frozen_string_literal: true

module ThroughputScatter
  Result = Struct.new(:start_date, :end_date, :daily_counts, keyword_init: true)
  EMPTY = Result.new(start_date: nil, end_date: nil, daily_counts: {}).freeze

  ENTITY_TYPE = RecordEvent.entity_type_for(Story).freeze

  def self.call(team_id:, action: 'released', days: 30, map_id: nil)
    end_date = Date.today
    start_date = days ? end_date - days : nil

    sql = <<~SQL
      SELECT occurred_at::date AS day, COUNT(*) AS cnt
        FROM events
       WHERE team_id = ?
         AND entity_type = ?
         AND action = ?
         #{'AND occurred_at >= ?::date' if start_date}
         #{'AND map_id = ?' if map_id}
       GROUP BY day
       ORDER BY day
    SQL
    params = [team_id, ENTITY_TYPE, action]
    params << start_date if start_date
    params << map_id if map_id

    rows = DB[sql, *params].all
    return EMPTY if rows.empty? && start_date.nil?

    daily_counts = {}
    rows.each { |r| daily_counts[r[:day]] = r[:cnt] }

    window_start = start_date || rows.first[:day]

    Result.new(start_date: window_start, end_date: end_date, daily_counts: daily_counts)
  end
end
