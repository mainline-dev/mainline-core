# frozen_string_literal: true

module SplitCandidate
  ENTITY_TYPE = RecordEvent.entity_type_for(Story).freeze

  def self.check(story, team_id:, threshold: nil)
    return false unless story.status == 'active'

    first_activated = Event
      .where(entity_id: story.id, entity_type: ENTITY_TYPE, action: 'activated')
      .order(:event_no)
      .first
    return false unless first_activated

    age_seconds = Time.now - first_activated.occurred_at

    threshold = percentile_threshold(team_id) if threshold.nil?
    return false unless threshold

    age_seconds > threshold
  end

  def self.check_batch(stories, team_id:, threshold: nil)
    active = stories.select { |s| s.status == 'active' }
    return {} if active.empty?

    threshold = percentile_threshold(team_id) if threshold.nil?
    return active.to_h { |s| [s.id, false] } unless threshold

    ids = active.map(&:id)
    activation_times = Event
      .where(entity_id: ids, entity_type: ENTITY_TYPE, action: 'activated')
      .group(:entity_id)
      .select_hash(
        :entity_id,
        Sequel.as(Sequel.function(:min, :occurred_at), :first_activated)
      )

    now = Time.now
    active.to_h { |s|
      activated_at = activation_times[s.id]
      exceeds = activated_at ? (now - activated_at) > threshold : false
      [s.id, exceeds]
    }
  end

  def self.percentile_threshold(team_id)
    cached = Team.where(id: team_id).get(:split_threshold_seconds)
    return cached if cached

    compute_threshold(team_id)
  end

  def self.invalidate_threshold!(team_id)
    Team.where(id: team_id).update(split_threshold_seconds: nil)
  end

  def self.compute_threshold(team_id)
    min = TeamConstraint.for_team(team_id, 'split_min_released', default: 10)
    released_count = Story.where(team_id: team_id, status: 'released').count
    return nil if released_count < min

    cycle_times = cycle_times(team_id)
    return nil if cycle_times.length < min

    pct = TeamConstraint.for_team(team_id, 'split_percentile', default: 80) / 100.0
    return nil if pct >= 1.0

    threshold = cycle_times[(cycle_times.length * pct).ceil - 1]
    Team.where(id: team_id).update(split_threshold_seconds: threshold)
    threshold
  end
  private_class_method :compute_threshold

  # Seconds from first activation to first release for each released story, ascending.
  def self.cycle_times(team_id)
    sql = <<~SQL
      SELECT EXTRACT(EPOCH FROM (MIN(e_release.occurred_at) - MIN(e_activate.occurred_at))) AS cycle_seconds
        FROM events e_release
        JOIN events e_activate
          ON e_activate.entity_id = e_release.entity_id
         AND e_activate.entity_type = ?
         AND e_activate.action = 'activated'
       WHERE e_release.team_id = ?
         AND e_release.entity_type = ?
         AND e_release.action = 'released'
       GROUP BY e_release.entity_id
      HAVING MIN(e_release.occurred_at) > MIN(e_activate.occurred_at)
       ORDER BY cycle_seconds
    SQL

    DB[sql, ENTITY_TYPE, team_id, ENTITY_TYPE].all.map { |r| r[:cycle_seconds].to_f }
  end
  private_class_method :cycle_times
end
