# frozen_string_literal: true

class Mainline
  def htmx_grid_or_redirect(req, fallback: nil)
    if req.env['HTTP_HX_REQUEST']
      trigger = @flash_msg&.to_htmx_trigger
      response['HX-Trigger'] = trigger.to_json if trigger
      FlashAdapter.clear_session(flash)
      load_map_grid_data
      render('maps/_grid')
    else
      @flash_msg&.write_session(flash)
      req.redirect(fallback || "/maps/#{@map.id}")
    end
  end

  def flash_msg
    @flash_msg ||= FlashAdapter.new
  end

  def load_map_view_prefs
    pref = DB[:map_view_prefs].where(
      person_id: @current_person.id, map_id: @map.id
    ).first
    @active_filter = pref ? pref[:active] : false
    @slices_view = pref ? pref[:slices] : false
    @hide_released = pref ? pref[:hide_released] : false
    @slice_filter = pref ? pref[:slice_filter_id] : nil
    @locked = pref ? pref[:locked] : false
    @map_archivable = Activity.where(map_id: @map.id, archived_at: nil).none? &&
                      Persona.where(map_id: @map.id, archived_at: nil).none? &&
                      Story.where(map_id: @map.id, archived_at: nil).none? &&
                      ReleaseSlice.where(map_id: @map.id, archived_at: nil).none?
  end

  def valid_slice_filter(id)
    return nil unless id&.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)

    ReleaseSlice.where(id: id, map_id: @map.id, archived_at: nil).get(:id)
  end

  def load_map_entities
    @personas = Persona.where(map_id: @map.id, archived_at: nil).order(:position).all
    @release_slices = ReleaseSlice.where(map_id: @map.id, archived_at: nil).order(:position).all
    @activities = Activity
      .where(map_id: @map.id, archived_at: nil)
      .order(:position)
      .eager(:personas, tasks: {stories: [:release_slice, {story_assignments: :person}]})
      .all
  end

  def load_map_grid_data
    load_map_entities
    @slice_filter = nil unless @release_slices.any? { |s| s.id == @slice_filter }
    @grid = MapGrid.call(
      activities: @activities, release_slices: @release_slices,
      active_filter: @active_filter, slices_view: @slices_view,
      slice_filter: @slice_filter, hide_released: @hide_released
    )
    active_stories = @activities.flat_map(&:tasks).flat_map(&:stories).select { |s| s.status == 'active' && s.archived_at.nil? }
    @split_candidates = SplitCandidate.check_batch(active_stories, team_id: @current_team.id)

    active_ids = active_stories.map(&:id)
    @story_notes = build_story_notes(active_ids, @split_candidates)
    @deploy_counts = if active_ids.any?
                       Event.where(entity_id: active_ids, action: 'deployed')
                         .group_and_count(:entity_id)
                         .to_hash(:entity_id, :count)
                     else
                       {}
                     end
  end

  def build_story_notes(story_ids, split_candidates)
    notes = {}
    if story_ids.any?
      StoryNote.where(story_id: story_ids, dismissed_at: nil)
        .select_map(%i[story_id note_type])
        .each { |sid, nt| (notes[sid] ||= []) << nt }
    end
    split_candidates.each do |sid, is_split|
      next unless is_split

      notes[sid] ||= []
      notes[sid] << 'split_candidate' unless notes[sid].include?('split_candidate')
    end
    notes
  end

  hash_branch('maps') do |r|
    r.get 'new' do
      @map_name = ''
      view 'new'
    end

    r.is do
      r.post do
        SetTeamContext.call(@current_team.id)
        name = typecast_params.nonempty_str('name')

        map_count = Map.where(team_id: @current_team.id).count
        cap = ResourceCap.maps_per_team(map_count)

        @errors = []
        @errors << 'This team has reached its map limit' if cap == :blocked
        @errors << 'Name is required' unless name
        @errors << 'Name must be 100 characters or fewer' if name && name.length > 100

        flash['warning'] = "This team has #{map_count} maps. Consider archiving unused ones." if cap == :warning

        unless @errors.empty?
          @map_name = name || ''
          next view('new')
        end

        DB.transaction do
          next_pos = (Map.where(team_id: @current_team.id).max(:position) || 0) + 1000
          @map = Map.create(
            team_id:  @current_team.id,
            name:     name,
            position: next_pos
          )
          RecordEvent.call(
            actor_id:    @current_actor.id,
            entity:      @map,
            action:      'created',
            map_id:      @map.id,
            after_state: { name: @map.name, position: @map.position }
          )
        end

        flash['notice'] = "Map '#{@map.name}' created"
        r.redirect "/maps/#{@map.id}"
      end
    end

    r.on String do |map_id|
      next unless map_id.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)

      @map = BypassRLS.call { Map[map_id] }
      next unless @map && @map.archived_at.nil?

      @current_team = Team[@map.team_id]
      next r.redirect('/teams') unless @current_team

      session['team_id'] = @current_team.id
      @is_creator = @current_team.creator_id == @current_person.id
      membership = TeamMembership.where(
        team_id: @current_team.id, person_id: @current_person.id, left_at: nil
      ).first
      unless membership&.working
        r.redirect "/teams/#{@current_team.id}/account"
        next
      end

      leave_suspended_team(r, @current_team) if @current_team.suspended?

      @is_working_member = true
      SetTeamContext.call(@current_team.id)
      load_map_view_prefs

      r.get 'edit_title' do
        render('maps/_map_title_form')
      end

      r.get 'title' do
        render('maps/_map_title')
      end

      r.on 'edit' do
        r.get do
          @subnav_active = 'edit'
          @map_name = @map.name
          view 'edit'
        end

        r.post do
          name = typecast_params.nonempty_str('name')

          @errors = []
          @errors << 'Name is required' if name.nil? || name.empty?
          @errors << 'Name must be 100 characters or fewer' if name && name.length > 100

          unless @errors.empty?
            next render('maps/_map_title_form') if request.env['HTTP_HX_REQUEST']

            @subnav_active = 'edit'
            @map_name = @map.name
            next view('edit')
          end

          DB.transaction do
            before = { name: @map.name }
            @map.update(name: name)
            RecordEvent.call(
              actor_id:     @current_actor.id,
              entity:       @map,
              action:       'edited',
              map_id:       @map.id,
              before_state: before,
              after_state:  { name: name }
            )
          end

          next render('maps/_map_title') if request.env['HTTP_HX_REQUEST']

          flash['notice'] = "Map '#{@map.name}' updated"
          r.redirect "/maps/#{@map.id}"
        end
      end

      r.get 'history' do
        @subnav_active = 'history'
        per_page = (typecast_params.int('per_page') || 50).clamp(1, 50)
        ds = Event.where(map_id: @map.id)
        before = typecast_params.int('before')
        ds = ds.where { event_no < before } if before
        @events = ds.order(Sequel.desc(:event_no)).limit(per_page + 1).all
        @has_more = @events.length > per_page
        @events = @events.first(per_page)
        @next_cursor = @events.last&.event_no if @has_more

        actor_ids = @events.map(&:actor_id).uniq
        @actors = actor_ids.any? ? Actor.where(id: actor_ids).to_hash(:id) : {}

        grouped = @events.group_by(&:entity_type)
        entity_ids = ->(type) { (grouped[type] || []).map(&:entity_id).uniq }

        stories = entity_ids.call('storie').then { |ids| ids.any? ? Story.where(id: ids).to_hash(:id) : {} }
        maps = entity_ids.call('map').then { |ids| ids.any? ? Map.where(id: ids).to_hash(:id) : {} }

        state_ids = lambda { |key|
          @events.flat_map { |e| [e.before_state[key], e.after_state[key]] }.compact.uniq
        }

        task_ids = (entity_ids.call('task') + state_ids.call('task_id')).uniq
        tasks = task_ids.any? ? Task.where(id: task_ids).to_hash(:id) : {}

        state_array_ids = lambda { |key|
          @events.flat_map { |e| Array(e.before_state[key]) + Array(e.after_state[key]) }.compact.uniq
        }

        activity_ids = (entity_ids.call('activitie') + state_array_ids.call('activity_ids')).uniq
        activities = activity_ids.any? ? Activity.where(id: activity_ids).to_hash(:id) : {}

        persona_ids = (entity_ids.call('persona') + state_ids.call('persona_id') + state_array_ids.call('persona_ids')).uniq
        personas = persona_ids.any? ? Persona.where(id: persona_ids).to_hash(:id) : {}

        slice_ids = (entity_ids.call('release_slice') + state_ids.call('release_slice_id')).uniq
        slices = slice_ids.any? ? ReleaseSlice.where(id: slice_ids).to_hash(:id) : {}

        person_ids = state_ids.call('person_id')
        people = person_ids.any? ? Person.where(id: person_ids).to_hash(:id) : {}

        @entity_names = {}
        stories.each { |id, s| @entity_names[id] = s.title }
        tasks.each { |id, t| @entity_names[id] = t.name }
        activities.each { |id, a| @entity_names[id] = a.name }
        personas.each { |id, p| @entity_names[id] = p.name }
        slices.each { |id, s| @entity_names[id] = s.name }
        maps.each { |id, m| @entity_names[id] = m.name }

        @event_lookup = { people: people, slices: slices, tasks: tasks, personas: personas, activities: activities }
        view 'history'
      end

      r.get 'grid' do
        load_map_grid_data
        render('maps/_grid')
      end

      r.is do
        r.get do
          @subnav_active = 'map'
          if %w[active slices hide_released slice_filter].any? { |k| r.params.key?(k) }
            @active_filter = typecast_params.str('active') == '1' if r.params.key?('active')
            @slices_view = typecast_params.str('slices') == '1' if r.params.key?('slices')
            @hide_released = typecast_params.str('hide_released') == '1' if r.params.key?('hide_released')
            @slice_filter = valid_slice_filter(typecast_params.str('slice_filter')) if r.params.key?('slice_filter')
            DB[:map_view_prefs].insert_conflict(
              target: %i[person_id map_id],
              update: { active: @active_filter, slices: @slices_view,
                        hide_released: @hide_released, slice_filter_id: @slice_filter }
            ).insert(
              person_id: @current_person.id, map_id: @map.id,
              active: @active_filter, slices: @slices_view,
              hide_released: @hide_released, slice_filter_id: @slice_filter
            )
          end

          load_map_grid_data
          @page_title = "#{@map.name} - Mainline"
          view 'show'
        end
      end

      r.post 'archive' do
        has_active = Activity.where(map_id: @map.id, archived_at: nil).any? ||
                     Persona.where(map_id: @map.id, archived_at: nil).any? ||
                     Story.where(map_id: @map.id, archived_at: nil).any? ||
                     ReleaseSlice.where(map_id: @map.id, archived_at: nil).any?

        if has_active
          flash['error'] = 'Archive all activities, personas, stories, and slices before archiving the map'
          next r.redirect("/maps/#{@map.id}")
        end

        DB.transaction do
          @map.update(archived_at: Time.now)
          RecordEvent.call(
            actor_id:    @current_actor.id,
            entity:      @map,
            action:      'archived',
            map_id:      @map.id,
            after_state: { name: @map.name }
          )
        end

        flash['notice'] = "Map '#{@map.name}' archived"
        if htmx?(r)
          response['HX-Redirect'] = "/teams/#{@current_team.id}"
          ''
        else
          r.redirect "/teams/#{@current_team.id}"
        end
      end

      r.post 'lock' do
        pref = DB[:map_view_prefs].where(
          person_id: @current_person.id, map_id: @map.id
        ).first
        was_locked = pref ? pref[:locked] : false
        DB[:map_view_prefs].insert_conflict(
          target: %i[person_id map_id],
          update: { locked: !was_locked }
        ).insert(
          person_id: @current_person.id, map_id: @map.id,
          locked: !was_locked
        )
        r.redirect "/maps/#{@map.id}"
      end

      r.hash_branches('maps')
    end
  end
end
