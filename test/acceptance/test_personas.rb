# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Personas' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    create_map
  end

  it 'returns 404 for a non-UUID persona id' do
    err = assert_raises(RuntimeError) { driver.get "/maps/#{@map.id}/personas/b3404700/edit" }

    assert_match(/404/, err.message)
  end

  it 'creates a persona' do
    create_persona('New Visitor')

    visit_personas

    assert_page_includes 'New Visitor'
  end

  it 'requires a name' do
    submit_create_persona(name: '', description: '')

    assert_equal(0, BypassRLS.call { Persona.where(map_id: @map.id).count })
    assert_error_shown
  end

  it 'rejects a name over 100 characters' do
    submit_create_persona(name: 'x' * 101)

    assert_equal(0, BypassRLS.call { Persona.where(map_id: @map.id).count })
    assert_error_shown
  end
end

describe 'Personas - Edit' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    create_map
    @persona = create_persona('Visitor', description: 'First-time user')
  end

  it 'shows pre-filled edit form' do
    visit_edit_persona(@persona)

    assert_page_includes('Visitor')
    assert_page_includes('First-time user')
  end

  it 'updates the name' do
    submit_edit_persona(@persona, name: 'Customer', description: 'First-time user')

    @persona.reload

    assert_equal 'Customer', @persona.name

    event = assert_event_recorded(entity: @persona, action: 'edited')

    assert_equal 'Visitor', event.before_state['name']
    assert_equal 'Customer', event.after_state['name']
  end

  it 'updates the description' do
    submit_edit_persona(@persona, name: 'Visitor', description: 'Returning user')

    @persona.reload

    assert_equal 'Returning user', @persona.description
  end

  it 'requires a name' do
    submit_edit_persona(@persona, name: '', description: 'First-time user')

    assert_error_shown

    @persona.reload

    assert_equal 'Visitor', @persona.name
  end

  it 'rejects an edit name over 100 characters' do
    submit_edit_persona(@persona, name: 'x' * 101, description: 'First-time user')

    @persona.reload

    assert_equal 'Visitor', @persona.name
    assert_error_shown
  end

  it 'shows activity checkboxes on edit' do
    create_activity('Browse', for_personas: [@persona])

    resp = driver.htmx_get_edit_persona(@map, @persona)

    assert_includes resp.body, 'Browse'
    assert_includes resp.body, 'checkbox'
  end

  it 'updates activity associations' do
    other_persona = create_persona('Shopper')
    browse = create_activity('Browse', for_personas: [@persona])
    shop = create_activity('Shop', for_personas: [@persona, other_persona])

    submit_edit_persona(@persona, name: 'Visitor', description: 'First-time user',
      activity_ids: [browse.id])

    links = ActivityPersona.where(persona_id: @persona.id).select_map(:activity_id)

    assert_includes links, browse.id
    refute_includes links, shop.id
  end

  it 'rejects removing sole persona from activity' do
    browse = create_activity('Browse', for_personas: [@persona])

    submit_edit_persona(@persona, name: 'Visitor', description: 'First-time user',
      activity_ids: [])

    links = ActivityPersona.where(persona_id: @persona.id).select_map(:activity_id)

    assert_includes links, browse.id
    assert_error_shown
  end

  it 'allows editing persona after its activity is archived' do
    browse = create_activity('Browse', for_personas: [@persona])
    task = create_task('Setup', under_activity: browse)
    archive_task(task)
    archive_activity(browse)

    submit_edit_persona(@persona, name: 'Customer', description: 'Updated')

    @persona.reload

    assert_equal 'Customer', @persona.name
  end

  it 'rejects editing persona from another map' do
    other_map = Map.create(team_id: @team.id, name: 'Other', position: 9000)
    foreign = Persona.create(map_id: other_map.id, team_id: @team.id, name: 'Foreign', position: 1000)

    assert_raises(RuntimeError, '404 - Not Found') do
      driver.visit_edit_persona(@map, foreign)
    end
  end

  it 'has disabled save button' do
    visit_edit_persona(@persona)

    assert_includes page_body, 'disabled'
  end

  it 'returns inline edit form via HTMX GET' do
    resp = driver.htmx_get_edit_persona(@map, @persona)

    refute_predicate resp, :redirect?
    refute_includes resp.body, '<!DOCTYPE'
    assert_includes resp.body, 'Visitor'
    assert_includes resp.body, 'disabled'
  end

  it 'edit form has cancel that returns card via HTMX' do
    resp = driver.htmx_get_persona_card(@map, @persona)

    refute_predicate resp, :redirect?
    assert_includes resp.body, 'persona-card'
    assert_includes resp.body, 'Visitor'
    refute_includes resp.body, '<form'
  end

  it 'inline name edit via HTMX' do
    resp = driver.htmx_get_persona_name_form(@map, @persona)

    assert_includes resp.body, 'inline-edit-form'
    assert_includes resp.body, 'Visitor'
  end

  it 'inline name save via HTMX' do
    resp = driver.htmx_edit_persona_name(@map, @persona, name: 'Customer')

    assert_includes resp.body, 'Customer'
    refute_includes resp.body, '<form'

    @persona.reload

    assert_equal 'Customer', @persona.name
  end

  it 'inline name save rejects name over 100 characters' do
    resp = driver.htmx_edit_persona_name(@map, @persona, name: 'x' * 101)

    assert_includes resp.body, 'inline-edit-form'
    assert_error_shown(resp.body)

    @persona.reload

    assert_equal 'Visitor', @persona.name
  end

  it 'inline name save requires name' do
    resp = driver.htmx_edit_persona_name(@map, @persona, name: '')

    assert_includes resp.body, 'inline-edit-form'

    @persona.reload

    assert_equal 'Visitor', @persona.name
  end

  it 'returns card after HTMX save' do
    resp = driver.htmx_edit_persona(@map, @persona, name: 'Customer', description: 'First-time user')

    refute_predicate resp, :redirect?
    assert_includes resp.body, 'persona-card'
    assert_includes resp.body, 'Customer'

    @persona.reload

    assert_equal 'Customer', @persona.name
  end

  it 'returns inline form with errors on HTMX validation failure' do
    resp = driver.htmx_edit_persona(@map, @persona, name: '', description: '')

    refute_predicate resp, :redirect?
    assert_error_shown(resp.body)
    assert_includes resp.body, 'disabled'

    @persona.reload

    assert_equal 'Visitor', @persona.name
  end
end

describe 'Persona list page' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    @bob   = add_person(name: 'Bob')
    create_map
  end

  it 'shows heading' do
    create_persona('Customer')

    visit_personas

    assert_page_includes('Personas')
  end

  it 'shows persona name and description' do
    create_persona('Customer', description: 'Buys things')

    visit_personas

    body = page_body

    assert_includes body, 'Customer'
    assert_includes body, 'Buys things'
  end

  it 'shows linked activity names' do
    persona = create_persona('Customer')
    create_activity('Browse', for_personas: [persona])

    visit_personas

    body = page_body

    assert_includes body, 'Browse'
  end

  it 'shows activity names for persona' do
    persona = create_persona('Customer')
    create_activity('Browse', for_personas: [persona])

    visit_personas

    assert_page_includes 'Browse'
  end

  it 'links back to map view' do
    create_persona('Customer')

    visit_personas

    body = page_body

    assert_includes body, "/maps/#{@map.id}\""
  end

  it 'shows empty state when no personas exist' do
    visit_personas

    assert_shown('personas-empty')
  end

  it 'links to create new persona' do
    visit_personas

    body = page_body

    assert_includes body, "/maps/#{@map.id}/personas/new"
  end

  it 'links to persona edit page' do
    persona = create_persona('Customer')

    visit_personas

    body = page_body

    assert_includes body, "/maps/#{@map.id}/personas/#{persona.id}/edit"
  end
end

describe 'Persona - History' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    create_map
  end

  it 'shows persona history on index page' do
    create_persona('Customer')

    visit_personas

    assert_page_includes('data-test-id="persona-history"')
    assert_page_includes('Customer')
    assert_page_includes('Alice')
  end

  it 'shows empty state when no persona events' do
    visit_personas

    body = page_body

    refute_includes body, 'section-title">History'
  end

  it 'htmx name edit returns updated history via OOB' do
    persona = create_persona('Customer')

    resp = driver.htmx_edit_persona_name(@map, persona, name: 'Buyer')

    assert_includes resp.body, 'hx-swap-oob'
    assert_includes resp.body, 'renamed'
  end

  it 'htmx full edit returns updated history via OOB' do
    persona = create_persona('Customer')

    resp = driver.htmx_edit_persona(@map, persona, name: 'Buyer', description: '')

    assert_includes resp.body, 'hx-swap-oob'
    assert_includes resp.body, 'renamed'
  end

  it 'limits history to 20 most recent and shows Show all link' do
    persona = create_persona('Customer')

    25.times do |i|
      RecordEvent.call(
        actor_id: @alice.actor.id, entity: persona, action: 'edited',
        before_state: { name: "v#{i}" }, after_state: { name: "v#{i + 1}" }
      )
    end

    visit_personas

    body = page_body

    assert_shown('history-show-all', body)
    assert_includes body, 'v25'
    refute_includes body, '&quot;v0&quot;'
  end

  it 'show-all returns full history' do
    persona = create_persona('Customer')

    25.times do |i|
      RecordEvent.call(
        actor_id: @alice.actor.id, entity: persona, action: 'edited',
        before_state: { name: "v#{i}" }, after_state: { name: "v#{i + 1}" }
      )
    end

    driver.visit_persona_history(@map)

    body = page_body

    assert_includes body, 'v25'
    assert_includes body, '&quot;v0&quot;'
    refute_shown('history-show-all', body)
  end
end

describe 'Personas - Archive' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    create_map
    @persona = create_persona('Visitor')
  end

  it 'archives a persona' do
    archive_persona(@persona)

    @persona.refresh

    refute_nil @persona.archived_at
  end

  it 'records an event when archiving' do
    archive_persona(@persona)

    event = Event.where(entity_type: 'persona', action: 'archived').first

    refute_nil event
    assert_equal @persona.id, event.entity_id
  end

  it 'removes persona from personas list after archiving' do
    archive_persona(@persona)

    resp = driver.visit_personas(@map)

    refute_includes resp.body, 'data-test-id="persona-card"'
  end

  it 'allows creating a new persona with the same name after archiving' do
    archive_persona(@persona)

    submit_create_persona(name: 'Visitor')

    new_persona = Persona.where(map_id: @map.id, archived_at: nil, name: 'Visitor').first

    refute_nil new_persona
    refute_equal @persona.id, new_persona.id
  end

  it 'blocks archiving when persona is sole persona on an activity' do
    create_activity('Browse', for_personas: [@persona])

    archive_persona(@persona)
    @persona.refresh

    assert_nil @persona.archived_at
  end

  it 'allows archiving when another persona covers the activity' do
    other = create_persona('Customer')
    create_activity('Browse', for_personas: [@persona, other])

    archive_persona(@persona)
    @persona.refresh

    refute_nil @persona.archived_at
  end

  it 'cleans up activity links on archive' do
    other = create_persona('Customer')
    create_activity('Browse', for_personas: [@persona, other])

    archive_persona(@persona)

    links = ActivityPersona.where(persona_id: @persona.id).count

    assert_equal 0, links
  end
end
