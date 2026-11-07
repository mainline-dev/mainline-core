# frozen_string_literal: true

TeamPersona = Struct.new(
  :label,
  :team_size,
  :activity_count,
  :tasks_per_activity,
  :cycle_time,
  :release_gap,
  :rotation,
  :solo_chance,
  :ensemble_chance,
  :max_wip,
  :planned_backlog,
  :stale_deployed,
  :project_duration,
  keyword_init: true
)

TeamPersona::HIGH = TeamPersona.new(
  label:              'high',
  team_size:          5..7,
  activity_count:     3..5,
  tasks_per_activity: 2..3,
  cycle_time:         1..2,
  release_gap:        0..1,
  rotation:           :full,
  solo_chance:        0,
  ensemble_chance:    0.2,
  max_wip:            2,
  planned_backlog:    2..3,
  stale_deployed:     0,
  project_duration:   90..450
)

TeamPersona::MEDIUM = TeamPersona.new(
  label:              'medium',
  team_size:          4..6,
  activity_count:     3..4,
  tasks_per_activity: 1..3,
  cycle_time:         2..4,
  release_gap:        1..3,
  rotation:           :moderate,
  solo_chance:        0.125,
  ensemble_chance:    0.1,
  max_wip:            3,
  planned_backlog:    4..6,
  stale_deployed:     1,
  project_duration:   60..180
)

TeamPersona::LOW = TeamPersona.new(
  label:              'low',
  team_size:          3..5,
  activity_count:     2..3,
  tasks_per_activity: 1..2,
  cycle_time:         4..7,
  release_gap:        3..6,
  rotation:           :clique,
  solo_chance:        0.25,
  ensemble_chance:    0,
  max_wip:            4,
  planned_backlog:    8..12,
  stale_deployed:     3..4,
  project_duration:   30..90
)
