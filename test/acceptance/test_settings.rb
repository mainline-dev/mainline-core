# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Settings' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
  end

  it 'shows settings page with default thresholds' do
    visit_settings

    assert_page_includes('data-test-id="settings"')
    assert_page_includes('value="4"')
    assert_page_includes('value="10"')
  end

  it 'shows custom thresholds when configured' do
    TeamConstraint.create(
      team_id: @team.id, constraint_key: 'inventory_aging_days',
      value: 7, min_value: 1, max_value: 30, default_value: 4
    )
    TeamConstraint.create(
      team_id: @team.id, constraint_key: 'inventory_stale_days',
      value: 21, min_value: 2, max_value: 60, default_value: 10
    )

    visit_settings

    assert_page_includes('value="7"')
    assert_page_includes('value="21"')
  end

  it 'updates aging threshold' do
    update_settings(aging_days: 5, stale_days: 10)
    row = TeamConstraint.where(team_id: @team.id, constraint_key: 'inventory_aging_days').first

    assert_equal 5, row.value
  end

  it 'updates stale threshold' do
    update_settings(aging_days: 4, stale_days: 14)
    row = TeamConstraint.where(team_id: @team.id, constraint_key: 'inventory_stale_days').first

    assert_equal 14, row.value
  end

  it 'rejects stale less than or equal to aging' do
    update_settings(aging_days: 10, stale_days: 5)

    assert_equal 0, TeamConstraint.where(team_id: @team.id).count
  end

  it 'rejects out-of-range values' do
    update_settings(aging_days: 0, stale_days: 10)

    assert_equal 0, TeamConstraint.where(team_id: @team.id).count
  end

  it 'shows warning banner' do
    visit_settings

    assert_shown('team-wide-warning')
  end

  it 'records event when thresholds change' do
    update_settings(aging_days: 5, stale_days: 14)

    events = Event.where(team_id: @team.id, entity_type: 'team_constraint', action: 'updated').all

    assert_equal 2, events.size
  end

  it 'does not record event when value unchanged' do
    update_settings(aging_days: 4, stale_days: 10)

    events = Event.where(team_id: @team.id, entity_type: 'team_constraint').all

    assert_equal 0, events.size
  end

  it 'shows event history on settings page' do
    update_settings(aging_days: 5, stale_days: 14)
    visit_settings

    assert_page_includes('Alice')
    assert_page_includes('data-setting="inventory_aging_days"')
  end

  it 'shows default split thresholds' do
    visit_settings

    assert_page_includes('value="80"')
  end

  it 'shows custom split thresholds' do
    TeamConstraint.create(
      team_id: @team.id, constraint_key: 'split_percentile',
      value: 90, min_value: 50, max_value: 100, default_value: 80
    )
    TeamConstraint.create(
      team_id: @team.id, constraint_key: 'split_min_released',
      value: 20, min_value: 5, max_value: 50, default_value: 10
    )

    visit_settings

    assert_page_includes('value="90"')
    assert_page_includes('value="20"')
  end

  it 'updates split percentile' do
    update_settings(split_percentile: 90, split_min_released: 10)
    row = TeamConstraint.where(team_id: @team.id, constraint_key: 'split_percentile').first

    assert_equal 90, row.value
  end

  it 'updates split min released' do
    update_settings(split_percentile: 80, split_min_released: 15)
    row = TeamConstraint.where(team_id: @team.id, constraint_key: 'split_min_released').first

    assert_equal 15, row.value
  end

  it 'rejects split percentile out of range' do
    update_settings(split_percentile: 40, split_min_released: 10)

    assert_nil TeamConstraint.where(team_id: @team.id, constraint_key: 'split_percentile').first
  end

  it 'rejects split min released out of range' do
    update_settings(split_percentile: 80, split_min_released: 2)

    assert_nil TeamConstraint.where(team_id: @team.id, constraint_key: 'split_min_released').first
  end

  it 'records event when split thresholds change' do
    update_settings(split_percentile: 90, split_min_released: 15)

    events = Event.where(team_id: @team.id, entity_type: 'team_constraint', action: 'updated').all

    assert_equal 2, events.size
  end

  it 'does not record event when split values unchanged' do
    update_settings(split_percentile: 80, split_min_released: 10)

    events = Event.where(team_id: @team.id, entity_type: 'team_constraint').all

    assert_equal 0, events.size
  end

  it 'shows split events in history' do
    update_settings(split_percentile: 90, split_min_released: 15)
    visit_settings

    assert_page_includes('Alice')
    assert_page_includes('data-setting="split_percentile"')
  end

  it 'percentile 100 disables split detection' do
    update_settings(split_percentile: 100, split_min_released: 10)
    row = TeamConstraint.where(team_id: @team.id, constraint_key: 'split_percentile').first

    assert_equal 100, row.value
  end

  it 'shows solo activation toggle defaulting to off' do
    visit_settings

    assert_page_includes('data-test-id="solo-activation"')
    refute_page_includes('checked')
  end

  it 'enables solo activation' do
    update_settings(allow_solo_activation: '1')

    val = TeamConstraint.for_team(@team.id, 'allow_solo_activation', default: 0)

    assert_equal 1, val
  end

  it 'disables solo activation' do
    TeamConstraint.create(
      team_id: @team.id, constraint_key: 'allow_solo_activation',
      value: 1, min_value: 0, max_value: 1, default_value: 0
    )

    update_settings(allow_solo_activation: '0')

    val = TeamConstraint.for_team(@team.id, 'allow_solo_activation', default: 0)

    assert_equal 0, val
  end

  it 'records event when solo activation changes' do
    update_settings(allow_solo_activation: '1')

    events = Event.where(team_id: @team.id, entity_type: 'team_constraint', action: 'updated')
      .all.select { |e| e.after_state['constraint_key'] == 'allow_solo_activation' }

    assert_equal 1, events.size
  end

  it 'shows timezone selector defaulting to UTC' do
    visit_settings

    assert_page_includes('data-test-id="timezone"')
    assert_page_includes('UTC')
  end

  it 'updates timezone' do
    update_settings(timezone: 'America/New_York')

    @team.refresh

    assert_equal 'America/New_York', @team.timezone
  end

  it 'rejects invalid timezone' do
    update_settings(timezone: 'Not/A/Zone')

    @team.refresh

    assert_equal 'UTC', @team.timezone
  end

  it 'shows current timezone when non-default' do
    @team.update(timezone: 'Europe/Berlin')
    visit_settings

    assert_page_includes('Europe/Berlin')
  end

  it 'records event when timezone changes' do
    update_settings(timezone: 'Asia/Tokyo')

    events = Event.where(team_id: @team.id, entity_type: 'team', action: 'updated').all

    assert_equal 1, events.size
    assert_equal 'UTC', events.first.before_state['timezone']
    assert_equal 'Asia/Tokyo', events.first.after_state['timezone']
  end

  it 'does not record event when timezone unchanged' do
    update_settings(timezone: 'UTC')

    events = Event.where(team_id: @team.id, entity_type: 'team', action: 'updated').all

    assert_equal 0, events.size
  end

  it 'shows timezone change in history' do
    update_settings(timezone: 'Asia/Tokyo')
    visit_settings

    assert_page_includes('data-setting="timezone"')
    assert_page_includes('Asia/Tokyo')
  end

  it 'shows holiday region selector' do
    visit_settings

    assert_page_includes('data-test-id="holiday-region"')
  end

  it 'updates holiday region' do
    update_settings(holiday_region: 'au')

    @team.refresh

    assert_equal 'au', @team.holiday_region
  end

  it 'rejects invalid holiday region' do
    update_settings(holiday_region: 'not_a_region')

    @team.refresh

    assert_nil @team.holiday_region
  end

  it 'clears holiday region with empty selection' do
    @team.update(holiday_region: 'au')
    update_settings(holiday_region: '')

    @team.refresh

    assert_nil @team.holiday_region
  end

  it 'records event when holiday region changes' do
    update_settings(holiday_region: 'jp')

    events = Event.where(team_id: @team.id, entity_type: 'team', action: 'updated').all

    assert_equal 1, events.size
    assert_nil events.first.before_state['holiday_region']
    assert_equal 'jp', events.first.after_state['holiday_region']
  end

  it 'saves default story template' do
    update_settings(default_story_template: 'card')
    row = TeamConstraint.where(team_id: @team.id, constraint_key: 'default_story_template').first

    assert_equal 1, row.value
  end

  it 'pre-selects saved template on new story page' do
    TeamConstraint.create(
      team_id: @team.id, constraint_key: 'default_story_template',
      value: 2, min_value: 0, max_value: 2, default_value: 0
    )
    create_map
    create_persona('User')
    create_activity('Browse', for_personas: [Persona.first])

    resp = driver.get "/maps/#{@map.id}/stories/new"

    assert_includes resp.body, 'value="behaviour" selected'
  end

  describe 'WIP limit' do
    def wip_limit
      TeamConstraint.for_team(@team.id, 'max_active_stories', default: 1)
    end

    def wip_events
      Event.where(team_id: @team.id, entity_type: 'team_constraint').all
        .select { |event| event.after_state['constraint_key'] == 'max_active_stories' }
    end

    it 'starts at one active story per person' do
      visit_settings

      assert_page_includes('name="max_active_stories" value="1"')
    end

    it 'raises the limit with a reason, recorded on an event' do
      update_settings(max_active_stories: 2, wip_reason: 'Waiting on a vendor')

      assert_equal 2, wip_limit
      event = wip_events.first

      assert_equal 1, event.before_state['value']
      assert_equal 'Waiting on a vendor', event.after_state['reason']
      assert_equal @alice.actor_id, event.actor_id
    end

    it 'needs a reason to change the limit' do
      update_settings(max_active_stories: 2, wip_reason: '   ')

      assert_equal 1, wip_limit
      assert_empty wip_events
      visit_settings

      assert_error_shown
    end

    it 'needs a reason to lower the limit as well' do
      update_settings(max_active_stories: 3, wip_reason: 'Short of people')
      update_settings(max_active_stories: 2, wip_reason: '')

      assert_equal 3, wip_limit
    end

    it 'allows up to five' do
      update_settings(max_active_stories: 5, wip_reason: 'Trying it')

      assert_equal 5, wip_limit
    end

    it 'refuses a limit above the ceiling' do
      update_settings(max_active_stories: 6, wip_reason: 'Too many')

      assert_equal 1, wip_limit
      visit_settings

      assert_error_shown
    end

    it 'refuses a limit below one' do
      update_settings(max_active_stories: 0, wip_reason: 'Nothing at all')

      assert_equal 1, wip_limit
      visit_settings

      assert_error_shown
    end

    it 'records nothing when the limit stays the same' do
      update_settings(max_active_stories: 1, wip_reason: 'No change')

      assert_empty wip_events
    end

    it 'shows the change and its reason in the history' do
      update_settings(max_active_stories: 2, wip_reason: 'Waiting on a vendor')
      visit_settings

      assert_page_includes('data-setting="max_active_stories"')
      assert_shown('settings-event-reason')
    end
  end
end
