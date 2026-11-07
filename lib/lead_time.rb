# frozen_string_literal: true

module LeadTime
  Result = Struct.new(:buckets, :bucket_size, :max_lead_time, :p50, :p90, keyword_init: true)
  EMPTY = Result.new(buckets: [], bucket_size: nil, max_lead_time: nil, p50: nil, p90: nil).freeze

  ENTITY_TYPE = RecordEvent.entity_type_for(Story).freeze

  def self.call(team_id:, days: 30, map_id: nil)
    start_date = days ? Date.today - days : nil
    lead_times = lead_times(team_id, start_date, map_id)
    return EMPTY if lead_times.empty?

    max_lt = lead_times.max
    bucket_size = bucket_size_for(max_lt)
    sorted = lead_times.sort

    Result.new(buckets: build_buckets(lead_times, bucket_size, max_lt), bucket_size: bucket_size,
      max_lead_time: max_lt, p50: percentile(sorted, 50), p90: percentile(sorted, 90))
  end

  def self.lead_times(team_id, start_date, map_id)
    sql = <<~SQL
      SELECT e_release.entity_id,
             MIN(e_activate.occurred_at)::date AS activated_on,
             e_release.occurred_at::date AS released_on
        FROM events e_release
        JOIN events e_activate
          ON e_activate.entity_id = e_release.entity_id
         AND e_activate.team_id = e_release.team_id
         AND e_activate.entity_type = ?
         AND e_activate.action = 'activated'
       WHERE e_release.team_id = ?
         AND e_release.entity_type = ?
         AND e_release.action = 'released'
         #{'AND e_release.occurred_at >= ?::date' if start_date}
         #{'AND e_release.map_id = ?' if map_id}
       GROUP BY e_release.entity_id, e_release.occurred_at
    SQL
    params = [ENTITY_TYPE, team_id, ENTITY_TYPE]
    params << start_date if start_date
    params << map_id if map_id

    raw_rows(sql, *params)
      .reject { |r| r[:released_on].nil? || r[:activated_on].nil? }
      .map { |r| (r[:released_on] - r[:activated_on]).to_i }
      .reject(&:negative?)
  end
  private_class_method :lead_times

  def self.bucket_size_for(max_lt)
    if max_lt <= 14
      1
    elsif max_lt <= 30
      2
    else
      7
    end
  end
  private_class_method :bucket_size_for

  def self.build_buckets(lead_times, bucket_size, max_lt)
    bucket_count = ((max_lt + 1).to_f / bucket_size).ceil
    buckets = Array.new(bucket_count) { |i|
      low = i * bucket_size
      high = low + bucket_size - 1
      range = bucket_size == 1 ? low.to_s : "#{low}-#{high}"
      { range: range, low: low, high: high, count: 0 }
    }

    lead_times.each do |lt|
      idx = lt / bucket_size
      idx = bucket_count - 1 if idx >= bucket_count
      buckets[idx][:count] += 1
    end

    buckets
  end
  private_class_method :build_buckets

  def self.percentile(sorted, pct)
    return nil if sorted.empty?

    rank = (pct / 100.0 * sorted.length).ceil
    sorted[[rank - 1, 0].max]
  end
  private_class_method :percentile

  def self.raw_rows(sql, *params)
    DB[sql, *params].all
  end
  private_class_method :raw_rows
end
