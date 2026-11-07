# frozen_string_literal: true

require_relative 'drivers/http_driver'

module MainlineDSL
  def driver
    @driver ||= HttpDriver.new
  end

  def use_browser!
    require_relative 'drivers/browser_driver'
    Capybara.current_driver = :cuprite
    enable_shared_connection!
    @driver = BrowserDriver.new
    @_logged_in = false
    login_as(@_login_person) if @_login_person
  end

  def setup_team(name: 'Test Team')
    @team = driver.create_team(name)
  end

  # Suspended the way hosted billing will do it: core closes the team and
  # shows the message, pointing the account holder at the link if one is set.
  def suspend_team(team = @team, message: 'This team is suspended.', link: nil)
    driver.suspend_team(team, message: message, link: link)
  end

  def add_person(name:, email: nil)
    email ||= "#{name.downcase.gsub(/\s+/, '.')}@test.mainline"
    person = driver.add_person(@team, name: name, email: email)
    login_as(person) unless @_logged_in
    person
  end

  def login_as(person)
    driver.login_as(person)
    @_login_person = person
    @_logged_in = true
  end

  def create_map(name: 'Product Map')
    @map = driver.create_map(@team, name: name)
  end

  def create_persona(name, description: '')
    event_count = driver.event_count

    driver.submit_create_persona(@map, name: name, description: description)

    persona = driver.persona_named(@map, name)

    refute_nil persona, "Persona '#{name}' was not created"

    assert_equal event_count + 1, driver.event_count,
      'Expected one event for persona creation'
    assert_event_recorded(entity: persona, action: 'created')

    persona
  end

  def create_activity(name, for_personas:)
    expected_events = for_personas.length + 1 # N persona_added + 1 created

    driver.submit_create_activity(@map, {
      name:          name,
      persona_ids:   for_personas.map(&:id),
      persona_names: for_personas.map(&:name)
    })

    activity = driver.activity_named(@map, name)

    refute_nil activity, "Activity '#{name}' was not created"

    assert_equal for_personas.length, driver.personas_of(activity),
      "Activity should be linked to #{for_personas.length} persona(s)"

    new_events = driver.events_of(activity)

    assert_equal expected_events, new_events.length

    # All events share a correlation_id
    correlation = new_events.first.correlation_id

    refute_nil correlation
    assert(new_events.all? { |e| e.correlation_id == correlation })

    activity
  end

  def create_task(name, under_activity:)
    driver.submit_create_task(@map, {
      name:          name,
      activity_id:   under_activity.id,
      activity_name: under_activity.name
    })

    task = driver.task_named(under_activity, name)

    refute_nil task, "Task '#{name}' was not created"
    assert_event_recorded(entity: task, action: 'created')

    task
  end

  def create_story(title, under_task:, description: '')
    driver.submit_create_story(@map, {
      title:       title,
      task_id:     under_task.id,
      task_name:   under_task.name,
      description: description
    })

    story = driver.story_under(under_task, title)

    refute_nil story, "Story '#{title}' was not created"
    assert_equal 'planned', story.status
    assert_event_recorded(entity: story, action: 'created')

    story
  end

  def create_release_slice(name)
    driver.submit_create_release_slice(@map, name: name)

    slice = driver.release_slice_named(@map, name)

    refute_nil slice, "Release slice '#{name}' was not created"
    assert_event_recorded(entity: slice, action: 'created')

    slice
  end

  def move_story_to_slice(story, release_slice_id:)
    reorder_stories(driver.task_of(story), story_ids: [story.id], release_slice_id: release_slice_id)
  end

  def visit_assign_page(story)
    driver.visit_assign_page(@map, story)
  end

  def visit_inline_assign(story)
    driver.htmx_get_inline_assign(@map, story)
  end

  def assign_person(story, person:)
    driver.submit_assign_person(@map, story, person_id: person.id)
  end

  def unassign_person(story, assignment)
    driver.submit_unassign_person(@map, story, assignment)
  end

  def release_story(story)
    driver.submit_release(@map, story)
  end

  def deploy_story(story)
    driver.submit_deploy_story(@map, story)
  end

  def visit_story_panel(story)
    driver.htmx_get_story_panel(@map, story)
  end

  def visit_story_card(story)
    driver.htmx_get_story_card(@map, story)
  end

  def visit_webhook_settings
    driver.visit_webhook_settings(@team)
  end

  def visit_mcp_token_settings
    driver.visit_mcp_token_settings(@team)
  end

  def generate_webhook_token
    driver.submit_generate_webhook_token(@team)
    @team.refresh
    @webhook_token = driver.last_webhook_token
  end

  def api_deploy(story_ids:, token: nil)
    token ||= @webhook_token
    driver.submit_api_deploy(@team, story_ids: story_ids, token: token)
  end

  def api_deploy_raw(body:, token: nil)
    token ||= @webhook_token
    driver.submit_api_deploy_raw(@team, body: body, token: token)
  end

  def archive_story(story)
    driver.submit_archive_story(@map, story)
  end

  def archive_activity(activity)
    driver.submit_archive_activity(@map, activity)
  end

  def archive_task(task)
    driver.submit_archive_task(@map, task)
  end

  def archive_persona(persona)
    driver.submit_archive_persona(@map, persona)
  end

  def archive_map(map)
    driver.submit_archive_map(map)
  end

  def lock_map
    driver.submit_lock_map(@map)
  end

  def reorder_stories(task, story_ids:, release_slice_id: nil)
    driver.submit_reorder_stories(@map, task, story_ids: story_ids, release_slice_id: release_slice_id)
  end

  def reorder_tasks(activity, task_ids:)
    driver.submit_reorder_tasks(@map, activity, task_ids: task_ids)
  end

  def reorder_activities(activity_ids:)
    driver.submit_reorder_activities(@map, activity_ids: activity_ids)
  end

  def move_activity(activity, direction:)
    driver.submit_move_activity(@map, activity, direction: direction)
  end

  def submit_create_team(team_name:)
    driver.submit_create_team(team_name: team_name)
  end

  def visit_edit_team
    driver.visit_edit_team(@team)
  end

  def submit_edit_team(name:)
    driver.submit_edit_team(@team, name: name)
  end

  def submit_create_map(name:)
    driver.submit_create_map(name: name)
  end

  def submit_create_persona(name:, description: '')
    driver.submit_create_persona(@map, name: name, description: description)
  end

  def visit_personas
    driver.visit_personas(@map)
  end

  def visit_edit_persona(persona)
    driver.visit_edit_persona(@map, persona)
  end

  def submit_edit_persona(persona, name:, description: '', activity_ids: nil)
    attrs = { name: name, description: description }
    attrs[:activity_ids] = activity_ids if activity_ids
    driver.submit_edit_persona(@map, persona, attrs)
  end

  def submit_create_activity(name:, persona_ids:)
    driver.submit_create_activity(@map, name: name, persona_ids: persona_ids)
  end

  def visit_activities
    driver.visit_activities(@map)
  end

  def visit_edit_activity(activity)
    driver.visit_edit_activity(@map, activity)
  end

  def submit_edit_activity(activity, name:, persona_ids:)
    driver.submit_edit_activity(@map, activity, name: name, persona_ids: persona_ids)
  end

  def submit_create_task(name:, activity_id:)
    driver.submit_create_task(@map, name: name, activity_id: activity_id)
  end

  def visit_edit_task(task)
    driver.visit_edit_task(@map, task)
  end

  def submit_edit_task(task, name:, activity_id:)
    driver.submit_edit_task(@map, task, name: name, activity_id: activity_id)
  end

  def submit_create_story(title:, task_id:, description: '')
    driver.submit_create_story(@map, title: title, task_id: task_id, description: description)
  end

  def submit_create_story_from_template(**attrs)
    driver.submit_create_story_from_template(@map, attrs)
  end

  def visit_edit_story(story)
    driver.visit_edit_story(@map, story)
  end

  def edit_story(story, title:, task_id:,
                 release_slice_id: nil, decoupling_strategy: nil,
                 decoupling_label: nil)
    attrs = { title: title, task_id: task_id }
    attrs[:release_slice_id] = release_slice_id if release_slice_id
    attrs[:decoupling_strategy] = decoupling_strategy unless decoupling_strategy.nil?
    attrs[:decoupling_label] = decoupling_label unless decoupling_label.nil?
    driver.submit_edit_story(@map, story, attrs)
  end
  alias submit_edit_story edit_story

  def split_story(story, scenario_ids:, title: nil, template: nil, fields: {}, scenario_edits: {})
    driver.submit_split_story(@map, story, title: title, template: template,
      fields: fields, scenario_ids: scenario_ids, scenario_edits: scenario_edits)
  end

  def mark_scenario_done(story, scenario)
    driver.submit_scenario_done(@map, story, scenario)
  end

  def unmark_scenario_done(story, scenario)
    driver.submit_scenario_undone(@map, story, scenario)
  end

  def create_scenario(story, given_text:, when_text:, then_text:)
    driver.submit_create_scenario(@map, story,
      given: given_text, when: when_text, then: then_text)
  end

  def update_scenario(story, scenario, given_text:, when_text:, then_text:)
    driver.submit_update_scenario(@map, story, scenario,
      given: given_text, when: when_text, then: then_text)
  end

  def delete_scenario(story, scenario)
    driver.submit_delete_scenario(@map, story, scenario)
  end

  def submit_create_release_slice(name:)
    driver.submit_create_release_slice(@map, name: name)
  end

  def visit_release_slices_index
    driver.visit_release_slices_index(@map)
  end

  def submit_edit_release_slice(slice, name:)
    driver.submit_edit_release_slice(@map, slice, name: name)
  end

  def visit_edit_map
    driver.visit_edit_map(@map)
  end

  def submit_edit_map(name:)
    driver.submit_edit_map(@map, name: name)
  end

  def visit_map
    driver.visit_map(@map)
  end

  def visit_map_active
    driver.visit_map_active(@map)
  end

  def visit_map_slices
    driver.visit_map_slices(@map)
  end

  def visit_map_active_slices
    driver.visit_map_active_slices(@map)
  end

  def visit_story_history(story)
    driver.visit_story_history(@map, story)
  end

  def visit_team_dashboard
    driver.visit_team_dashboard(@team)
  end

  def visit_teamwork(lens: nil)
    driver.visit_teamwork(@team, lens: lens)
  end

  def visit_ensemble_timeline
    driver.visit_ensemble_timeline(@team)
  end

  def visit_solo_log
    driver.visit_solo_log(@team)
  end

  def visit_edit_person(person)
    driver.visit_edit_person(@team, person)
  end

  def rename_person(person, name:)
    driver.rename_person(@team, person, name: name)
  end

  def visit_inventory
    driver.visit_inventory(@team)
  end

  # Filters: type, label, epic (its key), age and page.
  def visit_museum(**filters)
    driver.visit_museum(@team, filters)
  end

  def let_the_curator_look
    driver.let_the_curator_look(@team)
  end

  def visit_let_go
    driver.visit_let_go(@team)
  end

  def let_go_keys(group)
    driver.let_go_keys(group)
  end

  def let_go_of(*keys, rest: [])
    driver.let_go_of(@team, ids: keys.map { |key| museum_item(key).id }, rest: rest)
  end

  # Chooses which side of a pair stays; the other goes, along with nothing else.
  def let_go_keeping(key, of:)
    driver.let_go_pair(@team, name: [key, of].min, id: museum_item(of).id)
  end

  def keep_exhibit(key)
    driver.keep_exhibit(@team, museum_item(key))
  end

  def unkeep_exhibit(key)
    driver.unkeep_exhibit(@team, museum_item(key))
  end

  def keep_both(pair)
    driver.keep_both(@team, pair)
  end

  def show_rest_of_let_go(group, offset:)
    driver.show_rest_of_let_go(@team, group, offset)
  end

  def let_go_row_keys
    driver.let_go_row_keys
  end

  def visit_let_go_done
    driver.visit_let_go_done(@team)
  end

  def undo_let_go
    driver.undo_let_go(@team)
  end

  def press_not_now
    driver.press_not_now(@team)
  end

  def check_for_let_go_prompt(tries:)
    driver.check_for_let_go_prompt(@team, tries)
  end

  # also: other ids to send along, as a tampered form might.
  def visit_together(*keys, also: [], mode: nil)
    driver.visit_together(@team, keys.map { |key| museum_item(key).id } + also, mode: mode)
  end

  def together_cards_shown
    driver.together_cards_shown
  end

  def leaving_keys_shown
    driver.leaving_keys_shown
  end

  def promote_together(*keys, title:, task:, scenarios: [], return_to: nil)
    driver.promote_together(@team, keys.map { |key| museum_item(key).id }, title: title, task_id: task.id, scenarios: scenarios,
      return_to: return_to)
  end

  def story_exhibits(title)
    driver.story_exhibits(@team, title)
  end

  def search_stories(query, for_keys: [])
    driver.search_stories(@team, query, for_keys.map { |key| museum_item(key).id })
  end

  def story_hits_shown
    driver.story_hits_shown
  end

  def add_to_story(*keys, to:, return_to: nil)
    driver.add_to_story(@team, keys.map { |key| museum_item(key).id }, story_id: story_titled(to)&.id, return_to: return_to)
  end

  def add_to_story_in_place(key, to:)
    item = museum_item(key)
    driver.add_to_story(@team, [item.id], story_id: story_titled(to).id, return_to: driver.return_to_in_form('add-to-story'),
      in_place: true)
  end

  def story_titled(title)
    driver.story_titled(@team, title)
  end

  def filter_museum_in_place(**filters)
    driver.filter_museum_in_place(@team, filters)
  end

  def visit_museum_promote(key)
    driver.visit_museum_promote(@team, museum_item(key))
  end

  # Scenarios as [given, when, then] triples.
  def promote_museum_item(key, title:, task:, scenarios: [], return_to: nil)
    driver.promote_museum_item(@team, museum_item(key), title: title, task_id: task.id, scenarios: scenarios,
      return_to: return_to)
  end

  def story_scenarios(title)
    driver.story_scenarios(@team, title)
  end

  # Ticks the exhibits (and any other ids given) and sends them to storage from
  # the museum page last visited, or from return_to.
  def send_museum_items_to_storage(*keys, also: [], return_to: nil)
    ids = keys.map { |key| museum_item(key).id } + also
    driver.send_museum_items_to_storage(@team, ids, return_to: return_to || driver.current_path_and_query)
  end

  def last_museum_path
    driver.current_path_and_query
  end

  def other_team_museum_item
    driver.other_team_museum_item
  end

  # from: the list the case was opened on.
  def open_museum_case(key, from: nil)
    driver.open_museum_case(@team, museum_item(key), from: from)
  end

  # For an exhibit that may not be the team's.
  def open_museum_case_of(item)
    driver.open_museum_case(@team, item)
  end

  def visit_museum_promote_of(item)
    driver.visit_museum_promote(@team, item)
  end

  def undo_storage_batch(batch)
    driver.undo_storage_batch(@team, batch)
  end

  # Submits the form on the page last seen, wherever it says to come back to.
  def promote_from_open_case(key, title:, task:)
    item = museum_item(key)
    driver.promote_museum_item(@team, item, title: title, task_id: task.id, return_to: driver.return_to_in_form("#{item.id}/promote"))
  end

  # Presses Send back to the museum on the row, on the page last seen.
  def send_back_to_museum(key)
    item = museum_item(key)
    driver.send_back_to_museum(@team, item, return_to: driver.return_to_in_form("#{item.id}/unpromote"))
  end

  def press_toast_undo
    driver.press_toast_undo
  end

  def press_bring_out(key)
    item = museum_item(key)
    driver.restore_museum_item(@team, item, return_to: driver.return_to_in_form("#{item.id}/restore"))
  end

  # Submits the form in the open case as the browser does, staying on the page.
  def promote_in_place(key, title:, task:)
    item = museum_item(key)
    driver.promote_in_place(@team, item, title: title, task_id: task.id, return_to: driver.return_to_in_form("#{item.id}/promote"))
  end

  def press_unkeep(key)
    item = museum_item(key)
    driver.unkeep_museum_item(@team, item, return_to: driver.return_to_in_form("#{item.id}/unkeep"))
  end

  def press_store(key)
    item = museum_item(key)
    driver.discard_museum_item(@team, item, return_to: driver.return_to_in_form("#{item.id}/discard"))
  end

  def discard_museum_item(key)
    driver.discard_museum_item(@team, museum_item(key))
  end

  def restore_museum_item(key)
    driver.restore_museum_item(@team, museum_item(key))
  end

  def museum_item(key)
    driver.museum_item(@team, key)
  end

  def unpromote_museum_item(key)
    driver.unpromote_museum_item(museum_item(key), @_login_person.actor)
  end

  def follow_museum_link(test_id)
    driver.follow_museum_link(test_id)
  end

  def museum_ledger_shown
    driver.museum_ledger_shown
  end

  def museum_import_problems_shown
    driver.museum_import_problems_shown
  end

  def visit_path(path)
    driver.visit_path(path)
  end

  def museum_import_rows_shown
    driver.museum_import_rows_shown
  end

  def visit_museum_import_page
    driver.visit_museum_import_page(@team)
  end

  # Uploads a Jira CSV export to the Ticket Museum and, when it can be read,
  # imports it from the preview. nil submits no file.
  def import_jira_csv(csv)
    upload_jira_csv(csv)
    apply_museum_import if driver.museum_import_shown
  end

  # Uploads a Jira CSV export and stops at the preview.
  def upload_jira_csv(csv)
    driver.upload_jira_csv(@team, csv)
  end

  # The problem rows of an upload, as the CSV a person would download.
  def download_museum_import_problems(import_id)
    driver.download_museum_import_problems(@team, import_id)
  end

  def apply_museum_import
    driver.apply_museum_import(@team, driver.museum_import_shown)
  end

  def undo_last_museum_import
    last = driver.last_museum_import(@team)
    driver.visit_museum_import(@team, last.id)
    driver.undo_museum_import(@team, last.id)
  end

  # Presses the Undo shown in the museum's list of uploads.
  def undo_museum_import_shown
    driver.undo_museum_import_shown
  end

  def cancel_museum_import
    driver.cancel_museum_import(@team, driver.museum_import_shown)
  end

  # Source keys of the museum items on the page, in the order shown.
  def museum_keys_shown
    driver.museum_keys_shown
  end

  def visit_settings
    driver.visit_settings
  end

  def update_settings(**params)
    driver.update_settings(params.transform_keys(&:to_s).transform_values(&:to_s))
  end

  def visit_flow(days: nil, map_id: nil)
    driver.visit_flow(@team, days: days, map_id: map_id)
  end

  def visit_throughput(days: nil, lens: nil, map_id: nil)
    driver.visit_throughput(@team, days: days, lens: lens, map_id: map_id)
  end

  def visit_lead_time(days: nil, map_id: nil)
    driver.visit_lead_time(@team, days: days, map_id: map_id)
  end

  def visit_map_by_id(id)
    driver.visit_map_by_id(id)
  end

  def request_login_link(email)
    driver.submit_login_link_request(email: email)
  end

  def login_links_sent(&)
    sent = []
    capture = lambda do |person:, **|
      sent << person.email
      nil
    end
    SendMagicLoginEmail.stub(:call, capture, &)
    sent
  end

  def verification_emails_sent(&)
    sent = []
    capture = lambda do |person:, **|
      sent << person.email
      nil
    end
    SendVerificationEmail.stub(:call, capture, &)
    sent
  end

  def connect_mcp_client(host:, token:, team: @team)
    driver.connect_mcp_client(team, token: token, host: host)
  end

  def press_shortcut(*keys)
    driver.press_shortcut(*keys)
  end

  def assert_notice_shown
    assert driver.flash_shown?('notice'), 'Expected the page to show a notice'
  end

  # An element with this test id is on the page. With a body, checks that
  # body; otherwise asks the driver.
  def assert_shown(test_id, body = nil)
    assert element_on_page?(test_id, body), "Expected #{test_id} on the page"
  end

  def refute_shown(test_id, body = nil)
    refute element_on_page?(test_id, body), "Expected no #{test_id} on the page"
  end

  def element_on_page?(test_id, body)
    return body.include?(%(data-test-id="#{test_id}")) if body

    driver.test_id_shown?(test_id)
  end

  # The first element comes before the second on the page.
  def assert_shown_before(test_id, other)
    assert driver.shown_before?(test_id, other), "Expected #{test_id} before #{other} on the page"
  end

  # The error on the page gives this reason for refusing.
  def assert_refused_because(reason)
    assert driver.response_includes?(%(data-reason="#{reason}")), "Expected the refusal reason #{reason}"
  end

  def refute_refused_because(reason)
    refute driver.response_includes?(%(data-reason="#{reason}")), "Expected no refusal reason #{reason}"
  end

  # An error is on the page, in a form's error list or the flash, whatever it
  # says. With a body, checks that body; otherwise asks the driver.
  def assert_error_shown(body = nil)
    assert error_on_page?(body), 'Expected an error on the page'
  end

  def refute_error_shown(body = nil)
    refute error_on_page?(body), 'Expected no error on the page'
  end

  def error_on_page?(body)
    return body.match?(/data-test-id="(form-errors|flash-error)"/) if body

    driver.flash_shown?('error') || driver.form_errors_shown?
  end

  def assert_page_includes(text)
    assert driver.response_includes?(text),
      "Expected page to include '#{text}'"
  end

  def refute_page_includes(text)
    refute driver.response_includes?(text),
      "Expected page NOT to include '#{text}'"
  end

  def assert_content_includes(text)
    assert driver.content_includes?(text),
      "Expected content to include '#{text}'"
  end

  def refute_content_includes(text)
    refute driver.content_includes?(text),
      "Expected content NOT to include '#{text}'"
  end

  def page_body
    driver.last_response.body
  end

  def assert_map_shows(text)
    visit_map

    assert_page_includes(text)
  end

  def assert_map_does_not_show(text)
    visit_map

    refute_content_includes(text)
  end

  def assert_event_recorded(entity:, action:)
    event = driver.events_of(entity, action: action).last

    refute_nil event, "Expected '#{action}' event for #{entity.class.name} #{entity.id}"
    assert_equal @team.id, event.team_id
    refute_nil event.actor_id, 'Event must have a named actor'
    event
  end

  def assert_no_events_for(entity:, action:)
    assert_empty driver.events_of(entity, action: action), "Expected NO '#{action}' event for #{entity.class.name} #{entity.id}"
  end

  def add_story_note(story, note_type:, team: @team)
    driver.add_story_note(story, team, note_type: note_type)
  end

  def dismiss_story_note(note, person:)
    driver.dismiss_story_note(note, person)
  end
end
