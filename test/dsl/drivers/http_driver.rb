# test/dsl/drivers/http_driver.rb
# frozen_string_literal: true

require 'cgi/escape'
require 'rack/test'
require 'timecop'
require_relative 'records'

class HttpDriver
  include Rack::Test::Methods
  include Records

  def app
    Mainline.app
  end

  def login_as(person)
    post '/_test_login', { 'person_id' => person.id }
  end

  def visit_login
    get '/login'
    last_response
  end

  def submit_logout
    post '/logout'
    last_response
  end

  def visit_teams
    get '/teams'
    last_response
  end

  def oauth_callback(provider:, uid:, email:, name:)
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[provider.to_sym] = OmniAuth::AuthHash.new(
      provider: provider, uid: uid, info: { email: email, name: name }
    )
    get "/auth/#{provider}/callback"
    last_response
  end

  def oauth_signup(provider:, uid:, email:, name:)
    oauth_callback(provider: provider, uid: uid, email: email, name: name)
    resp = get '/confirm-email'
    token = resp.body[%r{/verify-email/([^"<]+)}, 1]
    post "/verify-email/#{token}" if token
    last_response
  end

  def visit_new_team
    get '/teams/new'
    last_response
  end

  def submit_create_team(attrs)
    post '/teams', { 'team_name' => attrs[:team_name] }
    last_response
  end

  def visit_team_dashboard(team)
    get "/teams/#{team.id}"
    last_response
  end

  def visit_edit_team(team)
    get "/teams/#{team.id}/edit"
    last_response
  end

  def submit_edit_team(team, attrs)
    post "/teams/#{team.id}/edit", { 'name' => attrs[:name] }
    follow_redirect! if last_response.redirect?
    last_response
  end

  def submit_create_map(attrs)
    post '/maps', { 'name' => attrs[:name] }
    last_response
  end

  def visit_personas(map)
    get "/maps/#{map.id}/personas"
    last_response
  end

  def visit_persona_history(map)
    get "/maps/#{map.id}/personas/history"
    last_response
  end

  def visit_edit_persona(map, persona)
    get "/maps/#{map.id}/personas/#{persona.id}/edit"
    last_response
  end

  def submit_edit_persona(map, persona, attrs)
    params = {
      'name'        => attrs[:name],
      'description' => attrs.fetch(:description, '')
    }
    params['activity_ids'] = attrs[:activity_ids] if attrs.key?(:activity_ids)
    post "/maps/#{map.id}/personas/#{persona.id}", params
    follow_redirect! if last_response.redirect?
    last_response
  end

  def htmx_get_edit_persona(map, persona)
    get "/maps/#{map.id}/personas/#{persona.id}/edit", {}, { 'HTTP_HX_REQUEST' => 'true' }
    last_response
  end

  def htmx_get_persona_card(map, persona)
    get "/maps/#{map.id}/personas/#{persona.id}", {}, { 'HTTP_HX_REQUEST' => 'true' }
    last_response
  end

  def htmx_get_persona_name_form(map, persona)
    get "/maps/#{map.id}/personas/#{persona.id}/edit_name", {}, { 'HTTP_HX_REQUEST' => 'true' }
    last_response
  end

  def htmx_edit_persona_name(map, persona, attrs)
    post "/maps/#{map.id}/personas/#{persona.id}/name", {
      'name' => attrs[:name]
    }, { 'HTTP_HX_REQUEST' => 'true' }
    last_response
  end

  def htmx_edit_persona(map, persona, attrs)
    post "/maps/#{map.id}/personas/#{persona.id}", {
      'name'        => attrs[:name],
      'description' => attrs.fetch(:description, '')
    }, { 'HTTP_HX_REQUEST' => 'true' }
    last_response
  end

  def submit_create_persona(map, attrs)
    post "/maps/#{map.id}/personas", {
      'name'        => attrs[:name],
      'description' => attrs.fetch(:description, '')
    }
    last_response
  end

  def visit_activities(map)
    get "/maps/#{map.id}/activities"
    last_response
  end

  def visit_activity_history(map)
    get "/maps/#{map.id}/activities/history"
    last_response
  end

  def visit_edit_activity(map, activity)
    get "/maps/#{map.id}/activities/#{activity.id}/edit"
    last_response
  end

  def submit_edit_activity(map, activity, attrs)
    post "/maps/#{map.id}/activities/#{activity.id}", {
      'name'        => attrs[:name],
      'persona_ids' => attrs[:persona_ids]
    }
    follow_redirect! if last_response.redirect?
    last_response
  end

  def htmx_get_activity(map:, activity:)
    get "/maps/#{map.id}/activities/#{activity.id}", {}, { 'HTTP_HX_REQUEST' => 'true' }
    last_response
  end

  def htmx_get_edit_activity(map, activity)
    get "/maps/#{map.id}/activities/#{activity.id}/edit", {}, { 'HTTP_HX_REQUEST' => 'true' }
    last_response
  end

  def htmx_edit_activity(map, activity, attrs)
    post "/maps/#{map.id}/activities/#{activity.id}", {
      'name'        => attrs[:name],
      'persona_ids' => attrs[:persona_ids]
    }, { 'HTTP_HX_REQUEST' => 'true' }
    last_response
  end

  def submit_create_activity(map, attrs)
    post "/maps/#{map.id}/activities", {
      'name'        => attrs[:name],
      'persona_ids' => attrs[:persona_ids]
    }
    last_response
  end

  def visit_edit_task(map, task)
    get "/maps/#{map.id}/tasks/#{task.id}/edit"
    last_response
  end

  def submit_edit_task(map, task, attrs)
    post "/maps/#{map.id}/tasks/#{task.id}", {
      'name'        => attrs[:name],
      'activity_id' => attrs[:activity_id]
    }
    follow_redirect! if last_response.redirect?
    last_response
  end

  def submit_create_task(map, attrs)
    post "/maps/#{map.id}/tasks", {
      'name'        => attrs[:name],
      'activity_id' => attrs[:activity_id]
    }
    last_response
  end

  def visit_edit_story(map, story)
    get "/maps/#{map.id}/stories/#{story.id}/edit"
    last_response
  end

  def submit_edit_story(map, story, attrs)
    params = {
      'title'   => attrs[:title],
      'task_id' => attrs[:task_id]
    }
    params['release_slice_id'] = attrs[:release_slice_id] if attrs.key?(:release_slice_id)
    params['decoupling_strategy'] = attrs[:decoupling_strategy] if attrs.key?(:decoupling_strategy)
    params['decoupling_label'] = attrs[:decoupling_label] if attrs.key?(:decoupling_label)
    post "/maps/#{map.id}/stories/#{story.id}", params
    follow_redirect! if last_response.redirect?
    last_response
  end

  def submit_create_scenario(map, story, attrs)
    post "/maps/#{map.id}/stories/#{story.id}/scenarios",
      'name' => attrs[:name], 'given' => attrs[:given], 'when' => attrs[:when], 'then' => attrs[:then]
    last_response
  end

  def submit_update_scenario(map, story, scenario, attrs)
    post "/maps/#{map.id}/stories/#{story.id}/scenarios/#{scenario.id}",
      'name' => attrs[:name], 'given' => attrs[:given], 'when' => attrs[:when], 'then' => attrs[:then]
    last_response
  end

  # Each scenario is [given, when, then] or [given, when, then, name]; the
  # name defaults to the Then line.
  def scenario_cards(scenarios)
    scenarios.each_with_index.to_h do |(given, whn, thn, name), i|
      [i.to_s, { 'name' => name || thn, 'given' => given, 'when' => whn, 'then' => thn }]
    end
  end

  def texts_of(test_id)
    Nokogiri::HTML(last_response.body).css(%([data-test-id="#{test_id}"])).map { |node| node.text.strip }
  end

  def download_feature_file(map, story)
    get "/maps/#{map.id}/stories/#{story.id}/feature"
    last_response
  end

  def download_step_stubs(map, story, language)
    get "/maps/#{map.id}/stories/#{story.id}/steps/#{language}"
    last_response
  end

  def pick_step_stubs(map, story, language)
    get "/maps/#{map.id}/stories/#{story.id}/steps", { 'language' => language }
    follow_redirect! if last_response.redirect?
    last_response
  end

  def attributes_of(test_id, attribute)
    Nokogiri::HTML(last_response.body).css(%([data-test-id="#{test_id}"])).map { |node| node[attribute] }
  end

  def submit_delete_scenario(map, story, scenario)
    post "/maps/#{map.id}/stories/#{story.id}/scenarios/#{scenario.id}/delete"
    last_response
  end

  def submit_create_story(map, attrs)
    post "/maps/#{map.id}/stories", {
      'title'       => attrs[:title],
      'task_id'     => attrs[:task_id],
      'description' => attrs.fetch(:description, '')
    }
    last_response
  end

  def submit_create_story_from_template(map, attrs)
    params = {
      'task_id'  => attrs[:task_id],
      'template' => attrs[:template]
    }
    params['role']        = attrs[:role]    if attrs[:role]
    params['goal']        = attrs[:goal]    if attrs[:goal]
    params['benefit']     = attrs[:benefit] if attrs[:benefit]
    params['beh_context'] = attrs[:context] if attrs[:context]
    params['beh_persona'] = attrs[:persona] if attrs[:persona] && attrs[:template] == 'behaviour'
    params['beh_action']  = attrs[:action]  if attrs[:action]  && attrs[:template] == 'behaviour'
    params['card_persona'] = attrs[:persona] if attrs[:persona] && attrs[:template] == 'card'
    params['card_action']  = attrs[:action]  if attrs[:action]  && attrs[:template] == 'card'
    post "/maps/#{map.id}/stories", params
    last_response
  end

  def visit_assign_page(map, story)
    get "/maps/#{map.id}/stories/#{story.id}/assignments/new"
    last_response
  end

  def htmx_get_inline_assign(map, story)
    get "/maps/#{map.id}/stories/#{story.id}/assignments/inline",
      {}, { 'HTTP_HX_REQUEST' => 'true' }
    last_response
  end

  def htmx_submit_inline_assign(map, story, person_id:)
    post "/maps/#{map.id}/stories/#{story.id}/assignments",
      { 'person_id' => person_id },
      { 'HTTP_HX_REQUEST' => 'true' }
    last_response
  end

  def submit_assign_person(map, story, person_id:)
    post "/maps/#{map.id}/stories/#{story.id}/assignments", {
      'person_id' => person_id
    }
    last_response
  end

  def submit_unassign_person(map, story, assignment)
    post "/maps/#{map.id}/stories/#{story.id}/assignments/#{assignment.id}/unassign"
    last_response
  end

  def submit_release(map, story)
    post "/maps/#{map.id}/stories/#{story.id}/release"
    last_response
  end

  def submit_deploy_story(map, story)
    post "/maps/#{map.id}/stories/#{story.id}/deploy"
    last_response
  end

  def htmx_get_story_panel(map, story)
    get "/maps/#{map.id}/stories/#{story.id}/panel", {}, { 'HTTP_HX_REQUEST' => 'true' }
    last_response
  end

  def htmx_get_story_card(map, story)
    get "/maps/#{map.id}/stories/#{story.id}/card", {}, { 'HTTP_HX_REQUEST' => 'true' }
    last_response
  end

  def htmx_deploy_story(map, story)
    post "/maps/#{map.id}/stories/#{story.id}/deploy", {}, { 'HTTP_HX_REQUEST' => 'true' }
    last_response
  end

  def htmx_release_story(map, story)
    post "/maps/#{map.id}/stories/#{story.id}/release", {}, { 'HTTP_HX_REQUEST' => 'true' }
    last_response
  end

  def htmx_archive_story(map, story)
    post "/maps/#{map.id}/stories/#{story.id}/archive", {}, { 'HTTP_HX_REQUEST' => 'true' }
    last_response
  end

  def htmx_unassign_person(map, story, assignment)
    post "/maps/#{map.id}/stories/#{story.id}/assignments/#{assignment.id}/unassign", {},
      { 'HTTP_HX_REQUEST' => 'true' }
    last_response
  end

  def visit_webhook_settings(team)
    get "/teams/#{team.id}/webhook"
    last_response
  end

  def visit_mcp_token_settings(team)
    get "/teams/#{team.id}/mcp_token"
    last_response
  end

  def submit_generate_webhook_token(team)
    post "/teams/#{team.id}/webhook"
    @last_webhook_token = last_response.body[/class="token">([^<]+)</, 1]
    last_response
  end

  attr_reader :last_webhook_token, :last_mcp_token

  def submit_generate_mcp_token(team)
    post "/teams/#{team.id}/mcp_token"
    @last_mcp_token = last_response.body[/class="token">([^<]+)</, 1]
    last_response
  end

  def submit_login_link_request(email:)
    post '/forgot-password', { 'email' => email }
    last_response
  end

  def connect_mcp_client(team, token:, host:)
    post(
      "/mcp/#{team.id}",
      JSON.generate({
        jsonrpc: '2.0', id: 1, method: 'initialize',
        params: { protocolVersion: '2025-03-26', capabilities: {},
                  clientInfo: { name: 'test', version: '1.0' } }
      }),
      'CONTENT_TYPE'       => 'application/json',
      'HTTP_ACCEPT'        => 'application/json',
      'HTTP_AUTHORIZATION' => "Bearer #{token}",
      'HTTP_HOST'          => host
    )
    last_response
  end

  def submit_api_deploy(team, story_ids:, token:)
    post(
      "/api/teams/#{team.id}/deploys",
      JSON.generate({ story_ids: story_ids }),
      { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
    )
    last_response
  end

  def submit_api_deploy_raw(team, body:, token:)
    post(
      "/api/teams/#{team.id}/deploys",
      body,
      { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
    )
    last_response
  end

  def submit_archive_story(map, story)
    post "/maps/#{map.id}/stories/#{story.id}/archive"
    last_response
  end

  def submit_archive_activity(map, activity)
    post "/maps/#{map.id}/activities/#{activity.id}/archive"
    last_response
  end

  def submit_archive_persona(map, persona)
    post "/maps/#{map.id}/personas/#{persona.id}/archive"
    last_response
  end

  def submit_archive_map(map)
    post "/maps/#{map.id}/archive"
    last_response
  end

  def submit_archive_task(map, task)
    post "/maps/#{map.id}/tasks/#{task.id}/archive"
    last_response
  end

  def htmx_archive_task(map, task)
    post "/maps/#{map.id}/tasks/#{task.id}/archive", {}, { 'HTTP_HX_REQUEST' => 'true' }
    last_response
  end

  def visit_edit_map(map)
    get "/maps/#{map.id}/edit"
    last_response
  end

  def submit_edit_map(map, attrs)
    post "/maps/#{map.id}/edit", { 'name' => attrs[:name] }
    follow_redirect! if last_response.redirect?
    last_response
  end

  def visit_map(map)
    get "/maps/#{map.id}"
    last_response
  end

  def visit_map_active(map)
    get "/maps/#{map.id}?active=1"
    last_response
  end

  def visit_map_slices(map)
    get "/maps/#{map.id}?slices=1"
    last_response
  end

  def visit_map_active_slices(map)
    get "/maps/#{map.id}?active=1&slices=1"
    last_response
  end

  def visit_map_with_params(map, active: nil, slices: nil, hide_released: nil, slice_filter: nil)
    params = []
    params << "active=#{active}" unless active.nil?
    params << "slices=#{slices}" unless slices.nil?
    params << "hide_released=#{hide_released}" unless hide_released.nil?
    params << "slice_filter=#{slice_filter}" unless slice_filter.nil?
    url = "/maps/#{map.id}"
    url += "?#{params.join('&')}" if params.any?
    get url
    last_response
  end

  def visit_map_grid(map)
    get "/maps/#{map.id}/grid"
    last_response
  end

  def visit_map_history(map, before: nil, per_page: nil)
    params = []
    params << "before=#{before}" if before
    params << "per_page=#{per_page}" if per_page
    qs = params.any? ? "?#{params.join('&')}" : ''
    get "/maps/#{map.id}/history#{qs}"
    last_response
  end

  def submit_map_rename(map, name:)
    post "/maps/#{map.id}/edit", 'name' => name
    last_response
  end

  def visit_release_slices_index(map)
    get "/maps/#{map.id}/release_slices"
    last_response
  end

  def visit_release_slice_history(map)
    get "/maps/#{map.id}/release_slices/history"
    last_response
  end

  def submit_edit_release_slice(map, slice, attrs)
    post "/maps/#{map.id}/release_slices/#{slice.id}", {
      'name' => attrs[:name]
    }
    follow_redirect! if last_response.redirect?
    last_response
  end

  def htmx_edit_release_slice(map, slice, attrs)
    post "/maps/#{map.id}/release_slices/#{slice.id}",
      { 'name' => attrs[:name] },
      { 'HTTP_HX_REQUEST' => 'true' }
    last_response
  end

  def submit_delete_release_slice(map, slice)
    post "/maps/#{map.id}/release_slices/#{slice.id}/delete"
    follow_redirect! if last_response.redirect?
    last_response
  end

  def htmx_delete_release_slice(map, slice)
    post "/maps/#{map.id}/release_slices/#{slice.id}/delete",
      {},
      { 'HTTP_HX_REQUEST' => 'true' }
    last_response
  end

  def submit_create_release_slice(map, attrs)
    post "/maps/#{map.id}/release_slices", {
      'name' => attrs[:name]
    }
    last_response
  end

  def visit_story_history(map, story)
    get "/maps/#{map.id}/stories/#{story.id}/history"
    last_response
  end

  def visit_map_by_id(id)
    get "/maps/#{id}"
    last_response
  end

  def submit_lock_map(map)
    post "/maps/#{map.id}/lock"
    last_response
  end

  def submit_reorder_stories(map, task, story_ids:, release_slice_id: nil)
    params = { 'story_id' => story_ids }
    params['release_slice_id'] = release_slice_id unless release_slice_id.nil?
    post "/maps/#{map.id}/tasks/#{task.id}/reorder_stories", params
    last_response
  end

  def submit_reorder_tasks(map, activity, task_ids:)
    post "/maps/#{map.id}/activities/#{activity.id}/reorder_tasks", { 'task_id' => task_ids }
    last_response
  end

  def submit_reorder_activities(map, activity_ids:)
    post "/maps/#{map.id}/activities/reorder", { 'activity_id' => activity_ids }
    last_response
  end

  def submit_move_activity(map, activity, direction:)
    post "/maps/#{map.id}/activities/#{activity.id}/move", { 'direction' => direction }
    last_response
  end

  def visit_teamwork(team, lens: nil)
    url = "/teams/#{team.id}/teamwork"
    url += "?lens=#{lens}" if lens
    get url
    last_response
  end

  def visit_ensemble_timeline(team)
    get "/teams/#{team.id}/teamwork/ensemble"
    last_response
  end

  def visit_solo_log(team)
    get "/teams/#{team.id}/teamwork/solo"
    last_response
  end

  def visit_edit_person(_team, _person)
    get '/profile/edit'
    last_response
  end

  def rename_person(_team, _person, attrs)
    post '/profile/edit', { 'name' => attrs[:name] }
    follow_redirect! if last_response.redirect?
    last_response
  end

  def visit_inventory(team)
    get "/teams/#{team.id}/inventory"
    last_response
  end

  def visit_museum(team, filters)
    get "/teams/#{team.id}/museum", filters.transform_keys(&:to_s)
    last_response
  end

  def filter_museum_in_place(team, filters)
    get "/teams/#{team.id}/museum", filters.transform_keys(&:to_s), { 'HTTP_HX_REQUEST' => 'true' }
    last_response
  end

  def visit_museum_promote(team, item)
    get "/teams/#{team.id}/museum/#{item.id}/promote"
    last_response
  end

  def promote_museum_item(team, item, title:, task_id:, scenarios: [], return_to: nil)
    cards = scenario_cards(scenarios)
    params = { 'title' => title, 'task_id' => task_id, 'scenarios' => cards }
    params['return_to'] = return_to if return_to
    post "/teams/#{team.id}/museum/#{item.id}/promote", params
    follow_redirect! if last_response.redirect?
    last_response
  end

  def promote_in_place(team, item, title:, task_id:, return_to:)
    in_place = { 'HTTP_HX_REQUEST' => 'true' }
    post "/teams/#{team.id}/museum/#{item.id}/promote", { 'title' => title, 'task_id' => task_id, 'return_to' => return_to }, in_place
    get last_response['Location'], {}, in_place if last_response.redirect?
    last_response
  end

  def visit_let_go(team)
    get "/teams/#{team.id}/museum/let-go"
    last_response
  end

  def let_go_keys(group)
    section = last_response.body[/data-group="#{group}".*?(?=data-test-id="let-go-group"|\z)/m].to_s
    section.scan(/data-test-id="let-go-row" data-key="([^"]+)"/).flatten
  end

  def let_go_of(team, ids:, rest:)
    post "/teams/#{team.id}/museum/let-go", { 'ids' => ids, 'rest' => rest }
    follow_redirect! if last_response.redirect?
    last_response
  end

  def keep_exhibit(team, item)
    post "/teams/#{team.id}/museum/#{item.id}/keep", {}, { 'HTTP_HX_REQUEST' => 'true' }
    last_response
  end

  def unkeep_exhibit(team, item)
    post "/teams/#{team.id}/museum/#{item.id}/unkeep", {}, { 'HTTP_HX_REQUEST' => 'true' }
    last_response
  end

  def keep_both(team, pair)
    post "/teams/#{team.id}/museum/let-go", { 'pairs' => { pair => 'both' } }
    follow_redirect! if last_response.redirect?
    last_response
  end

  def show_rest_of_let_go(team, group, offset)
    get "/teams/#{team.id}/museum/let-go/more", { 'group' => group, 'offset' => offset, 'rest' => [group] }
    last_response
  end

  def let_go_row_keys
    last_response.body.scan(/data-test-id="let-go-row" data-key="([^"]+)"/).flatten
  end

  def visit_let_go_done(team)
    get "/teams/#{team.id}/museum/let-go/done"
    follow_redirect! if last_response.redirect?
    last_response
  end

  def undo_let_go(team)
    post "/teams/#{team.id}/museum/let-go/undo"
    follow_redirect! if last_response.redirect?
    last_response
  end

  def press_not_now(team)
    post "/teams/#{team.id}/museum/let-go/snooze", { 'return_to' => return_to_in_form('let-go/snooze') }
    follow_redirect! if last_response.redirect?
    last_response
  end

  def check_for_let_go_prompt(team, tries)
    get "/teams/#{team.id}/museum/let-go/prompt", { 'tries' => tries }
    last_response
  end

  def visit_together(team, ids, mode: nil)
    post "/teams/#{team.id}/museum/together", { 'ids' => ids, 'mode' => mode }
    follow_redirect! if last_response.redirect?
    last_response
  end

  def together_cards_shown
    last_response.body.scan(/data-test-id="museum-together-card" data-key="([^"]+)"/).flatten
  end

  def leaving_keys_shown
    last_response.body[%r{data-test-id="museum-leaving".*?</div>}m].to_s.scan(/data-leaving="[^"]+">([^<]+)</).flatten
  end

  def promote_together(team, ids, title:, task_id:, scenarios: [], return_to: nil)
    cards = scenario_cards(scenarios)
    params = { 'ids' => ids, 'title' => title, 'task_id' => task_id, 'scenarios' => cards }
    params['return_to'] = return_to if return_to
    post "/teams/#{team.id}/museum/together/promote", params
    follow_redirect! if last_response.redirect?
    last_response
  end

  def search_stories(team, query, ids = [])
    get "/teams/#{team.id}/museum/stories", { 'q' => query, 'for' => ids.join(',') }
    last_response
  end

  def shown_before?(test_id, other)
    first, second = [test_id, other].map { |id| last_response.body.index(%(data-test-id="#{id}")) }
    first && second && first < second
  end

  def story_hits_shown
    last_response.body.scan(/data-test-id="museum-story-hit" data-title="([^"]*)"/).flatten.map { |title| CGI.unescapeHTML(title) }
  end

  def add_to_story(team, ids, story_id:, return_to: nil, in_place: false)
    hx = in_place ? { 'HTTP_HX_REQUEST' => 'true' } : {}
    params = { 'ids' => ids, 'story_id' => story_id }
    params['return_to'] = return_to if return_to
    post "/teams/#{team.id}/museum/add-to-story", params, hx
    if last_response.redirect?
      in_place ? get(last_response['Location'], {}, hx) : follow_redirect!
    end
    last_response
  end

  def let_go_pair(team, name:, id:)
    post "/teams/#{team.id}/museum/let-go", { 'pairs' => { name => id } }
    follow_redirect! if last_response.redirect?
    last_response
  end

  def send_museum_items_to_storage(team, ids, return_to:)
    post "/teams/#{team.id}/museum/discard", { 'ids' => ids, 'return_to' => return_to }
    follow_redirect! if last_response.redirect?
    last_response
  end

  def current_path_and_query
    [last_request.path, last_request.query_string].reject(&:empty?).join('?')
  end

  def open_museum_case(team, item, from: nil)
    get "/teams/#{team.id}/museum/#{item.id}/case", from ? { 'return_to' => from } : {}
    last_response
  end

  # The return_to carried by the form on the page that posts to this path.
  def return_to_in_form(action)
    CGI.unescapeHTML(last_response.body[%r{action="[^"]*/#{action}"(?:(?!</form>).)*?name="return_to" value="([^"]*)"}m, 1].to_s)
  end

  def discard_museum_item(team, item, return_to: nil)
    post "/teams/#{team.id}/museum/#{item.id}/discard", return_to ? { 'return_to' => return_to } : {}
    follow_redirect! if last_response.redirect?
    last_response
  end

  def send_back_to_museum(team, item, return_to:)
    post "/teams/#{team.id}/museum/#{item.id}/unpromote", { 'return_to' => return_to }
    follow_redirect! if last_response.redirect?
    last_response
  end

  def press_toast_undo
    form = last_response.body[%r{<form [^>]*action="[^"]+"[^>]*>(?:(?!</form>).)*data-test-id="museum-toast-undo"}m]
    return_to = CGI.unescapeHTML(form[/name="return_to" value="([^"]*)"/, 1])
    post form[/action="([^"]+)"/, 1], { 'return_to' => return_to }
    follow_redirect! if last_response.redirect?
    last_response
  end

  def unkeep_museum_item(team, item, return_to:)
    post "/teams/#{team.id}/museum/#{item.id}/unkeep", { 'return_to' => return_to }
    follow_redirect! if last_response.redirect?
    last_response
  end

  def undo_storage_batch(team, batch)
    post "/teams/#{team.id}/museum/stored/#{batch}/undo"
    follow_redirect! if last_response.redirect?
    last_response
  end

  def restore_museum_item(team, item, return_to: nil)
    post "/teams/#{team.id}/museum/#{item.id}/restore", return_to ? { 'return_to' => return_to } : {}
    follow_redirect! if last_response.redirect?
    last_response
  end

  def follow_museum_link(test_id)
    tag = last_response.body[/<a [^>]*data-test-id="#{test_id}"[^>]*>/]
    get CGI.unescapeHTML(tag[/href="([^"]+)"/, 1])
    last_response
  end

  def museum_ledger_shown
    cells = last_response.body.scan(/data-test-id="museum-ledger-cell" data-kind="(\w+)" data-count="(\d+)"/)
    cells.to_h { |kind, count| [kind, count.to_i] }
  end

  def museum_import_problems_shown
    last_response.body.scan('data-test-id="museum-import-problem"').size
  end

  def visit_path(path)
    get path
    last_response
  end

  def museum_import_rows_shown
    last_response.body.scan('data-test-id="museum-import-row"').size
  end

  def visit_museum_import_page(team)
    get "/teams/#{team.id}/museum/import"
    last_response
  end

  def upload_jira_csv(team, csv)
    params = csv ? { 'csv' => Rack::Test::UploadedFile.new(StringIO.new(csv), 'text/csv', original_filename: 'jira.csv') } : {}
    post "/teams/#{team.id}/museum/import", params
    follow_redirect! if last_response.redirect?
    last_response
  end

  # The id of the import whose preview is on the page, if one is.
  def museum_import_shown
    last_request.path[%r{/museum/imports/(\h{8}-\h{4}-\h{4}-\h{4}-\h{12})\z}, 1]
  end

  def download_museum_import_problems(team, import_id)
    get "/teams/#{team.id}/museum/imports/#{import_id}/problems.csv"
    last_response.body
  end

  def apply_museum_import(team, import_id)
    post "/teams/#{team.id}/museum/imports/#{import_id}/apply"
    follow_redirect! if last_response.redirect?
    last_response
  end

  def visit_museum_import(team, import_id)
    get "/teams/#{team.id}/museum/imports/#{import_id}"
    last_response
  end

  def undo_museum_import(team, import_id)
    post "/teams/#{team.id}/museum/imports/#{import_id}/undo"
    follow_redirect! if last_response.redirect?
    last_response
  end

  def undo_museum_import_shown
    form = last_response.body[%r{<form [^>]*action="([^"]+/undo)"[^>]*>(?:(?!</form>).)*data-test-id="museum-import-undo"}m, 1]
    post form
    follow_redirect! if last_response.redirect?
    last_response
  end

  def cancel_museum_import(team, import_id)
    post "/teams/#{team.id}/museum/imports/#{import_id}/cancel"
    follow_redirect! if last_response.redirect?
    last_response
  end

  def museum_keys_shown
    last_response.body.scan(/data-test-id="museum-item" data-key="([^"]+)"/).flatten
  end

  def update_settings(params)
    post '/settings', params
    last_response
  end

  def visit_flow(team, days: nil, map_id: nil)
    url = "/teams/#{team.id}/flow"
    params = []
    params << "days=#{days}" if days
    params << "map_id=#{map_id}" if map_id
    url += "?#{params.join('&')}" if params.any?
    get url
    last_response
  end

  def visit_throughput(team, days: nil, lens: nil, map_id: nil)
    url = "/teams/#{team.id}/flow/throughput"
    params = []
    params << "days=#{days}" if days
    params << "lens=#{lens}" if lens
    params << "map_id=#{map_id}" if map_id
    url += "?#{params.join('&')}" if params.any?
    get url
    last_response
  end

  def visit_lead_time(team, days: nil, map_id: nil)
    url = "/teams/#{team.id}/flow/lead-time"
    params = []
    params << "days=#{days}" if days
    params << "map_id=#{map_id}" if map_id
    url += "?#{params.join('&')}" if params.any?
    get url
    last_response
  end

  def submit_invite(team, email:)
    post "/teams/#{team.id}/members/invites", { 'email' => email }
    last_response
  end

  def visit_invite(token)
    get "/invite/#{token}"
    last_response
  end

  def follow_invite_redirect
    follow_redirect!
    last_response
  end

  def submit_join_team(team)
    post "/teams/#{team.id}/account/join"
    last_response
  end

  def submit_archive_member(team, person)
    post "/teams/#{team.id}/members/#{person.id}/archive"
    last_response
  end

  def visit_members(team)
    get "/teams/#{team.id}/members"
    last_response
  end

  def visit_account(team)
    get "/teams/#{team.id}/account"
    last_response
  end

  def follow_redirect
    follow_redirect!
    last_response
  end

  def visit_delete_team(team)
    get "/teams/#{team.id}/account/delete"
    last_response
  end

  def submit_delete_team(team, confirmation:)
    post "/teams/#{team.id}/account/delete", { 'confirmation' => confirmation }
    last_response
  end

  def download_export(team)
    get "/teams/#{team.id}/account/export"
    last_response
  end

  def submit_split_story(map, story, scenario_ids:, title: nil, template: nil, fields: {}, scenario_edits: {})
    params = { 'scenario_ids' => scenario_ids }
    params['title'] = title if title
    params['template'] = template if template
    fields.each { |key, value| params[key.to_s] = value }
    scenario_edits.each do |sid, edit|
      params["scenario_#{sid}_given"] = edit[:given]
      params["scenario_#{sid}_when"]  = edit[:when]
      params["scenario_#{sid}_then"]  = edit[:then]
    end
    post "/maps/#{map.id}/stories/#{story.id}/split", params
    last_response
  end

  def submit_scenario_done(map, story, scenario)
    post "/maps/#{map.id}/stories/#{story.id}/scenarios/#{scenario.id}/done"
    last_response
  end

  def submit_scenario_undone(map, story, scenario)
    post "/maps/#{map.id}/stories/#{story.id}/scenarios/#{scenario.id}/undone"
    last_response
  end

  def response_includes?(text)
    last_response.body.include?(text)
  end

  def flash_shown?(kind)
    last_response.body.include?(%(data-test-id="flash-#{kind}"))
  end

  def form_errors_shown?
    last_response.body.include?('data-test-id="form-errors"')
  end

  def test_id_shown?(test_id)
    last_response.body.include?(%(data-test-id="#{test_id}"))
  end

  def content_includes?(text)
    body = last_response.body.gsub(%r{<div[^>]*data-test-id="flash-[^"]*"[^>]*>.*?</div>}m, '')
    body.include?(text)
  end

  def visit_homepage
    get '/'
    last_response
  end

  def head_request(path)
    head path
    last_response
  end

  def visit_styleguide
    get '/styleguide'
    last_response
  end

  def visit_settings
    get '/settings'
    last_response
  end

  # Without form_started, as from a form loaded a few seconds earlier.
  def submit_email_signup(name:, email:, password:, via_cloudflare: nil, website: nil, form_started: nil)
    form_started ||= Timecop.travel(Time.now - 5) { SignupTimer.token }
    params = { 'name' => name, 'email' => email, 'password' => password, 'form_started' => form_started }
    params['website'] = website if website
    post '/signup', params, cloudflare_env(via_cloudflare)
    last_response
  end

  # Loads the signup page and reads when its form was started.
  def signup_form_started
    get '/signup'
    last_response.body[/name="form_started" value="([^"]+)"/, 1]
  end

  # A request that reached the app through Cloudflare's server `edge` and the
  # proxy in front of the app, from the visitor at `visitor`.
  def cloudflare_env(via)
    return {} unless via

    { 'REMOTE_ADDR' => '172.18.0.5', 'HTTP_X_FORWARDED_FOR' => via[:edge], 'HTTP_CF_CONNECTING_IP' => via[:visitor] }
  end

  def submit_email_login(email:, password:)
    post '/login', { 'email' => email, 'password' => password }
    last_response
  end

  def submit_set_password(password:, current_password: nil)
    params = { 'password' => password }
    params['current_password'] = current_password if current_password
    post '/profile/password', params
    last_response
  end

  def redirected?
    last_response.status == 302
  end
end
