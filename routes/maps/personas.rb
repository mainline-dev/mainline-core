# frozen_string_literal: true

class Mainline
  hash_branch('maps', 'personas') do |r|
    r.get 'new' do
      @subnav_active = 'personas'
      @persona = Persona.new
      view 'new'
    end

    r.get 'history' do
      @persona_events = Event.where(map_id: @map.id, entity_type: 'persona')
        .order(Sequel.desc(:event_no))
        .eager(:actor)
        .all
      activities = Activity.where(map_id: @map.id).as_hash(:id)
      @event_lookup = { people: {}, slices: {}, tasks: {}, personas: {}, activities: activities }
      render('maps/personas/_history')
    end

    r.on String do |persona_id|
      next unless persona_id.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)

      @persona = Persona.where(id: persona_id, map_id: @map.id).first
      next unless @persona

      r.post 'archive' do
        result = ArchivePersona.call(persona: @persona, actor: @current_actor)
        unless result.success?
          flash['error'] = result.errors.join(', ')
          next r.redirect("/maps/#{@map.id}/personas")
        end

        if htmx?(r)
          response['HX-Trigger'] = { showFlash: { message: "Persona '#{@persona.name}' archived" } }.to_json
          ''
        else
          flash['notice'] = "Persona '#{@persona.name}' archived"
          r.redirect "/maps/#{@map.id}/personas"
        end
      end

      r.get 'edit' do
        @subnav_active = 'personas'
        load_persona_edit_data
        htmx?(r) ? render('maps/personas/_edit_form') : view('edit')
      end

      r.get 'edit_name' do
        render('maps/personas/_name_form')
      end

      r.get 'name' do
        render('maps/personas/_name')
      end

      r.post 'name' do
        name = typecast_params.nonempty_str('name')
        next render('maps/personas/_name_form') unless name

        if name.length > 100
          @errors = ['Name must be 100 characters or fewer']
          next render('maps/personas/_name_form')
        end

        DB.transaction do
          before = { name: @persona.name }
          @persona.update(name: name)
          RecordEvent.call(
            actor_id:     @current_actor.id,
            entity:       @persona,
            action:       'edited',
            before_state: before,
            after_state:  { name: name }
          )
        end

        load_persona_history_oob
        render('maps/personas/_name') + render('maps/personas/_history')
      end

      r.is do
        r.get do
          @persona = Persona.where(id: @persona.id).eager(:activities).first
          render('maps/personas/_card')
        end

        r.post do
          result = EditPersona.call(
            persona: @persona, actor: @current_actor,
            name: typecast_params.nonempty_str('name'),
            description: typecast_params.str('description') || '',
            activity_ids: (typecast_params.array(:str, 'activity_ids') || []).reject(&:empty?)
          )

          unless result.success?
            @errors = result.errors
            @subnav_active = 'personas'
            load_persona_edit_data
            next htmx?(r) ? render('maps/personas/_edit_form') : view('edit')
          end

          if htmx?(r)
            @persona.reload
            load_persona_history_oob
            render('maps/personas/_card') + render('maps/personas/_history')
          else
            flash['notice'] = "Persona '#{@persona.name}' updated"
            r.redirect "/maps/#{@map.id}/personas"
          end
        end
      end
    end

    r.is do
      r.get do
        @subnav_active = 'personas'
        @personas = Persona.where(map_id: @map.id, archived_at: nil).order(:position).eager(:activities).all
        base = Event.where(map_id: @map.id, entity_type: 'persona')
        total = base.count
        @show_all_history = total > 20
        @persona_events = base.order(Sequel.desc(:event_no)).limit(20).eager(:actor).all
        activities = Activity.where(map_id: @map.id).as_hash(:id)
        @event_lookup = { people: {}, slices: {}, tasks: {}, personas: {}, activities: activities }
        view 'index'
      end

      r.post do
        result = CreatePersona.call(
          map: @map, team: @current_team, actor: @current_actor,
          name: typecast_params.nonempty_str('name'), description: typecast_params.str('description') || ''
        )

        unless result.success?
          @errors = result.errors
          @subnav_active = 'personas'
          @persona = Persona.new
          next view('new')
        end

        flash['notice'] = "Persona '#{result.persona.name}' created"
        r.redirect "/maps/#{@map.id}/personas"
      end
    end
  end

  def load_persona_edit_data
    @activities_for_edit = Activity.where(map_id: @map.id, archived_at: nil).order(:position).all
    @selected_activity_ids = ActivityPersona.where(persona_id: @persona.id).select_map(:activity_id)
  end

  def load_persona_history_oob
    @persona_events = Event.where(map_id: @map.id, entity_type: 'persona')
      .order(Sequel.desc(:event_no))
      .eager(:actor)
      .all
    activities = Activity.where(map_id: @map.id).as_hash(:id)
    @event_lookup = { people: {}, slices: {}, tasks: {}, personas: {}, activities: activities }
    @oob = true
  end
end
