# frozen_string_literal: true

class Mainline
  hash_branch('maps', 'activities') do |r|
    r.get 'new' do
      @subnav_active = 'activities'
      @activity = Activity.new
      @personas = Persona.where(map_id: @map.id, archived_at: nil).order(:position).all
      view 'new'
    end

    r.post 'reorder' do
      if person_locked?
        response.status = 422
        next ''
      end

      activity_ids = Array(r.params['activity_id'])
      result = ReorderActivities.call(
        map: @map, activity_ids: activity_ids, actor: @current_actor
      )

      if result
        response.status = 422
        next ''
      end

      response.status = 200
      ''
    end

    r.get 'history' do
      load_activity_history
      render('maps/activities/_history')
    end

    r.on String do |activity_id|
      next unless activity_id.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)

      @activity = Activity.where(id: activity_id, map_id: @map.id).first
      next unless @activity

      r.get 'edit' do
        @subnav_active = 'activities'
        @personas = Persona.where(map_id: @map.id, archived_at: nil).order(:position).all
        @selected_persona_ids = ActivityPersona.where(activity_id: @activity.id).select_map(:persona_id)
        htmx?(r) ? render('maps/activities/_edit_form') : view('edit')
      end

      r.post 'archive' do
        if Task.where(activity_id: @activity.id, archived_at: nil).any?
          flash_msg.error('Cannot archive an activity that has tasks')
          next htmx_grid_or_redirect(r)
        end

        DB.transaction do
          @activity.update(archived_at: Time.now)
          RecordEvent.call(
            actor_id:    @current_actor.id,
            entity:      @activity,
            action:      'archived',
            after_state: { name: @activity.name }
          )
        end

        flash_msg.notice("Activity '#{@activity.name}' archived")
        htmx_grid_or_redirect(r)
      end

      r.post 'move' do
        r.redirect "/maps/#{@map.id}" if person_locked?

        direction = typecast_params.nonempty_str('direction')
        MoveActivity.call(activity: @activity, direction: direction, actor: @current_actor)
        r.redirect "/maps/#{@map.id}"
      end

      r.post 'reorder_tasks' do
        if person_locked?
          response.status = 422
          next ''
        end

        task_ids = Array(r.params['task_id'])
        result = ReorderTasks.call(
          activity: @activity, task_ids: task_ids,
          actor: @current_actor, map_id: @map.id
        )

        if result
          response.status = 422
          next ''
        end

        response.status = 200
        ''
      end

      r.is do
        r.get do
          render('maps/activities/_item')
        end

        r.post do
          persona_ids = (typecast_params.array(:str, 'persona_ids') || []).reject(&:empty?)
          result = EditActivity.call(
            activity: @activity, actor: @current_actor,
            name: typecast_params.nonempty_str('name'), persona_ids: persona_ids
          )

          unless result.success?
            @errors = result.errors
            @subnav_active = 'edit'
            @personas = Persona.where(map_id: @map.id, archived_at: nil).order(:position).all
            @selected_persona_ids = persona_ids
            next htmx?(r) ? render('maps/activities/_edit_form') : view('edit')
          end

          if htmx?(r)
            @activity.reload
            load_activity_history
            @oob = true
            render('maps/activities/_item') + render('maps/activities/_history')
          else
            flash['notice'] = "Activity '#{@activity.name}' updated"
            r.redirect "/maps/#{@map.id}/activities"
          end
        end
      end
    end

    r.is do
      r.get do
        @subnav_active = 'activities'
        @activities = Activity.where(map_id: @map.id, archived_at: nil).order(:position).eager(:personas).all
        base = Event.where(map_id: @map.id, entity_type: 'activitie')
        total = base.count
        @show_all_history = total > 20
        @activity_events = base.order(Sequel.desc(:event_no)).limit(20).eager(:actor).all
        personas = Persona.where(map_id: @map.id).as_hash(:id)
        @event_lookup = { people: {}, slices: {}, tasks: {}, personas: personas, activities: {} }
        view 'index'
      end

      r.post do
        persona_ids = (typecast_params.array(:str, 'persona_ids') || []).reject(&:empty?)
        result = CreateActivity.call(
          map: @map, team: @current_team, actor: @current_actor,
          name: typecast_params.nonempty_str('name'), persona_ids: persona_ids
        )

        unless result.success?
          @errors = result.errors
          @subnav_active = 'activities'
          @activity = Activity.new
          @personas = Persona.where(map_id: @map.id, archived_at: nil).order(:position).all
          @selected_persona_ids = persona_ids
          next view('new')
        end

        flash['notice'] = "Activity '#{result.activity.name}' created"
        r.redirect "/maps/#{@map.id}/activities"
      end
    end
  end
end
