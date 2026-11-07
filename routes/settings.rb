# frozen_string_literal: true

require 'holidays'
require 'tzinfo'

class Mainline
  VALID_AGING_RANGE = (1..30)
  VALID_STALE_RANGE = (2..60)
  VALID_SPLIT_PCT   = (50..100)
  VALID_SPLIT_MIN   = (5..50)

  hash_branch('settings') do |r|
    @team = @current_team
    next r.redirect('/teams') unless @team

    @membership = TeamMembership.where(
      team_id: @team.id, person_id: @current_person.id, left_at: nil
    ).first
    next r.redirect('/teams') unless @membership&.working

    SetTeamContext.call(@team.id)

    r.is do
      r.get { load_settings_page }

      r.post do
        if r.params.key?('split_percentile')
          save_split_thresholds(r)
        elsif r.params.key?('allow_solo_activation')
          save_solo_activation(r)
        elsif r.params.key?('timezone')
          save_timezone(r)
        elsif r.params.key?('holiday_region')
          save_holiday_region(r)
        elsif r.params.key?('default_story_template')
          save_default_story_template(r)
        else
          save_inventory_thresholds(r)
        end
      end
    end
  end

  def load_settings_page
    @aging_days = TeamConstraint.for_team(@team.id, 'inventory_aging_days', default: 4)
    @stale_days = TeamConstraint.for_team(@team.id, 'inventory_stale_days', default: 10)
    @allow_solo_activation = TeamConstraint.for_team(@team.id, 'allow_solo_activation', default: 0)
    @split_percentile = TeamConstraint.for_team(@team.id, 'split_percentile', default: 80)
    @split_min_released = TeamConstraint.for_team(@team.id, 'split_min_released', default: 10)
    template_idx = TeamConstraint.for_team(@team.id, 'default_story_template', default: 0)
    @default_story_template = %w[connextra card behaviour][template_idx] || 'connextra'
    @settings_events = Event.where(
      team_id: @team.id, entity_type: %w[team_constraint team]
    ).order(Sequel.desc(:occurred_at)).limit(20).eager(actor: :person).all
    @page_title = 'Settings - Mainline'
    view 'settings'
  end

  def save_inventory_thresholds(req)
    aging = typecast_params.pos_int('aging_days')
    stale = typecast_params.pos_int('stale_days')

    unless valid_thresholds?(aging, stale)
      flash['error'] = 'Invalid thresholds. Stale must be greater than aging.'
      return req.redirect('/settings')
    end

    DB.transaction do
      upsert_constraint_with_event('inventory_aging_days', aging, min: 1, max: 30, default: 4)
      upsert_constraint_with_event('inventory_stale_days', stale, min: 2, max: 60, default: 10)
    end

    flash['notice'] = 'Inventory thresholds updated'
    req.redirect '/settings'
  end

  def valid_thresholds?(aging, stale)
    aging && stale && VALID_AGING_RANGE.cover?(aging) && VALID_STALE_RANGE.cover?(stale) && stale > aging
  end

  def save_split_thresholds(req)
    pct = typecast_params.pos_int('split_percentile')
    min_rel = typecast_params.pos_int('split_min_released')

    unless valid_split_thresholds?(pct, min_rel)
      flash['error'] = 'Invalid split thresholds.'
      return req.redirect('/settings')
    end

    DB.transaction do
      upsert_constraint_with_event('split_percentile', pct, min: 50, max: 100, default: 80)
      upsert_constraint_with_event('split_min_released', min_rel, min: 5, max: 50, default: 10)
      SplitCandidate.invalidate_threshold!(@team.id)
    end

    flash['notice'] = 'Split thresholds updated'
    req.redirect '/settings'
  end

  def valid_split_thresholds?(pct, min_rel)
    pct && min_rel && VALID_SPLIT_PCT.cover?(pct) && VALID_SPLIT_MIN.cover?(min_rel)
  end

  def save_solo_activation(req)
    value = typecast_params.str('allow_solo_activation') == '1' ? 1 : 0
    upsert_constraint_with_event('allow_solo_activation', value, min: 0, max: 1, default: 0)
    flash['notice'] = 'Activation setting updated'
    req.redirect '/settings'
  end

  def save_timezone(req)
    tz = typecast_params.nonempty_str('timezone')

    unless tz && valid_timezone?(tz)
      flash['error'] = 'Invalid timezone.'
      return req.redirect('/settings')
    end

    old_tz = @team.timezone
    @team.update(timezone: tz)

    if old_tz != tz
      RecordEvent.call(
        actor_id: @current_person.actor.id, entity: @team, action: 'updated',
        team_id: @team.id,
        before_state: { timezone: old_tz },
        after_state: { timezone: tz }
      )
    end

    flash['notice'] = 'Timezone updated'
    req.redirect '/settings'
  end

  def valid_timezone?(name)
    TZInfo::Timezone.get(name)
    true
  rescue TZInfo::InvalidTimezoneIdentifier
    false
  end

  def save_holiday_region(req)
    region = typecast_params.nonempty_str('holiday_region')

    if region && !Holidays.available_regions.include?(region.to_sym)
      flash['error'] = 'Invalid holiday region.'
      return req.redirect('/settings')
    end

    old_region = @team.holiday_region
    @team.update(holiday_region: region)

    if old_region != region
      RecordEvent.call(
        actor_id: @current_person.actor.id, entity: @team, action: 'updated',
        team_id: @team.id,
        before_state: { holiday_region: old_region },
        after_state: { holiday_region: region }
      )
    end

    flash['notice'] = 'Holiday region updated'
    req.redirect '/settings'
  end

  STORY_TEMPLATES = %w[connextra card behaviour].freeze

  def save_default_story_template(req)
    name = typecast_params.str('default_story_template')
    idx = STORY_TEMPLATES.index(name)

    unless idx
      flash['error'] = 'Invalid template'
      return req.redirect '/settings'
    end

    upsert_constraint_with_event('default_story_template', idx, min: 0, max: 2, default: 0)
    flash['notice'] = 'Default story template updated'
    req.redirect '/settings'
  end

  def upsert_constraint_with_event(key, value, min:, max:, default:)
    old_value = TeamConstraint.for_team(@team.id, key, default: default)
    upsert_constraint(key, value, min: min, max: max, default: default)
    return if old_value == value

    row = TeamConstraint.where(team_id: @team.id, constraint_key: key).first
    RecordEvent.call(
      actor_id: @current_person.actor.id, entity: row, action: 'updated',
      team_id: @team.id,
      before_state: { constraint_key: key, value: old_value },
      after_state: { constraint_key: key, value: value }
    )
  end

  def upsert_constraint(key, value, min:, max:, default:)
    DB[:team_constraints].insert_conflict(
      target: %i[team_id constraint_key],
      update: { value: value, updated_at: Sequel.lit('now()') }
    ).insert(
      id: Sequel.lit('gen_random_uuid()'),
      team_id: @team.id, constraint_key: key,
      value: value, min_value: min, max_value: max, default_value: default,
      updated_at: Sequel.lit('now()')
    )
  end
end
