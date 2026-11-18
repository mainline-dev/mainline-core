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
        if r.params.key?('max_active_stories')
          save_wip_limit(r)
        elsif r.params.key?('split_percentile')
          save_split_thresholds(r)
        elsif r.params.key?('allow_solo_activation')
          save_solo_activation(r)
        elsif r.params.key?(TwoPersonRule::KEY)
          save_two_person_rule(r)
        elsif r.params.key?(TwoPersonRule::LIMIT_KEY)
          save_walkthrough_limit(r)
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
    @wip_limit = AssignPerson.wip_limit(@team)
    @two_person_rule = TwoPersonRule.on?(@team)
    @walkthrough_limit = TwoPersonRule.limit(@team)
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

  # Anyone working on the team can change the limit, and everyone can see who
  # did and why, so a reason is required in both directions.
  def save_wip_limit(req)
    limit = Integer(req.params['max_active_stories'].to_s, 10, exception: false)
    reason = req.params['wip_reason'].to_s.strip[0, 280]
    if limit.nil? || !(1..AssignPerson::WIP_CEILING).cover?(limit)
      flash['error'] = "The limit must be between 1 and #{AssignPerson::WIP_CEILING}."
    elsif reason.empty? && limit != AssignPerson.wip_limit(@team)
      flash['error'] = 'Give a reason for changing the limit.'
    else
      bounds = { min: 1, max: AssignPerson::WIP_CEILING, default: AssignPerson::DEFAULT_WIP_LIMIT }
      change_constraints({ key: AssignPerson::WIP_KEY, value: limit, **bounds }, reason: reason)
      flash['notice'] = 'WIP limit updated'
    end
    req.redirect '/settings'
  end

  def save_inventory_thresholds(req)
    aging = typecast_params.pos_int('aging_days')
    stale = typecast_params.pos_int('stale_days')

    unless valid_thresholds?(aging, stale)
      flash['error'] = 'Invalid thresholds. Stale must be greater than aging.'
      return req.redirect('/settings')
    end

    aging_days = { key: 'inventory_aging_days', value: aging, min: 1, max: 30, default: 4 }
    stale_days = { key: 'inventory_stale_days', value: stale, min: 2, max: 60, default: 10 }
    change_constraints(aging_days, stale_days)

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

    percentile = { key: 'split_percentile', value: pct, min: 50, max: 100, default: 80 }
    min_released = { key: 'split_min_released', value: min_rel, min: 5, max: 50, default: 10 }
    change_constraints(percentile, min_released) { SplitCandidate.invalidate_threshold!(@team.id) }

    flash['notice'] = 'Split thresholds updated'
    req.redirect '/settings'
  end

  def valid_split_thresholds?(pct, min_rel)
    pct && min_rel && VALID_SPLIT_PCT.cover?(pct) && VALID_SPLIT_MIN.cover?(min_rel)
  end

  def save_solo_activation(req)
    value = typecast_params.str('allow_solo_activation') == '1' ? 1 : 0
    change_constraints({ key: 'allow_solo_activation', value: value, min: 0, max: 1, default: 0 })
    flash['notice'] = 'Activation setting updated'
    req.redirect '/settings'
  end

  # The rule guards every release, so turning it off or back on needs a
  # reason, which everyone on the team can see in the history.
  def save_two_person_rule(req)
    value = typecast_params.str(TwoPersonRule::KEY) == '1' ? 1 : 0
    reason = req.params['two_person_rule_reason'].to_s.strip[0, 280]
    if reason.empty? && (value == 1) != TwoPersonRule.on?(@team)
      flash['error'] = 'Give a reason for changing the two-person rule.'
      flash['error_reason'] = 'reason-needed'
    else
      change_constraints({ key: TwoPersonRule::KEY, value: value, min: 0, max: 1, default: 1 }, reason: reason)
      flash['notice'] = 'Two-person rule updated'
    end
    req.redirect '/settings'
  end

  # Like the WIP limit: anyone working on the team can change it, with a
  # reason in both directions.
  def save_walkthrough_limit(req)
    limit = Integer(req.params[TwoPersonRule::LIMIT_KEY].to_s, 10, exception: false)
    reason = req.params['walkthrough_limit_reason'].to_s.strip[0, 280]
    error, error_reason = walkthrough_limit_refusal(limit, reason)
    if error
      flash['error'] = error
      flash['error_reason'] = error_reason
    else
      range = TwoPersonRule::LIMIT_RANGE
      setting = { key: TwoPersonRule::LIMIT_KEY, value: limit, min: range.min, max: range.max, default: TwoPersonRule::DEFAULT_LIMIT }
      change_constraints(setting, reason: reason)
      flash['notice'] = 'Walkthrough limit updated'
    end
    req.redirect '/settings'
  end

  # Why the limit cannot be saved, with the reason's short name, if it cannot.
  def walkthrough_limit_refusal(limit, reason)
    range = TwoPersonRule::LIMIT_RANGE
    return ["The limit must be between #{range.min} and #{range.max}.", 'out-of-range'] unless range.cover?(limit)

    ['Give a reason for changing the limit.', 'reason-needed'] if reason.empty? && limit != TwoPersonRule.limit(@team)
  end

  def save_timezone(req)
    tz = typecast_params.nonempty_str('timezone')

    unless tz && valid_timezone?(tz)
      flash['error'] = 'Invalid timezone.'
      return req.redirect('/settings')
    end

    ChangeTeamField.call(team: @team, actor: @current_person.actor, field: :timezone, value: tz)
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

    ChangeTeamField.call(team: @team, actor: @current_person.actor, field: :holiday_region, value: region)
    flash['notice'] = 'Holiday region updated'
    req.redirect '/settings'
  end

  def save_default_story_template(req)
    name = typecast_params.str('default_story_template')
    idx = STORY_TEMPLATES.index(name)

    unless idx
      flash['error'] = 'Invalid template'
      return req.redirect '/settings'
    end

    change_constraints({ key: 'default_story_template', value: idx, min: 0, max: 2, default: 0 })
    flash['notice'] = 'Default story template updated'
    req.redirect '/settings'
  end

  # Saves the team's numbered settings given, together, each with its record.
  def change_constraints(*settings, reason: nil, &)
    ChangeTeamConstraint.call(team: @team, actor: @current_person.actor, settings: settings, reason: reason, &)
  end
end
