# frozen_string_literal: true

class Mainline
  hash_branch('maps', 'release_slices') do |r|
    r.get 'new' do
      @subnav_active = 'slices'
      @release_slice = ReleaseSlice.new
      view 'new'
    end

    r.get 'history' do
      @slice_events = Event.where(map_id: @map.id, entity_type: 'release_slice')
        .order(Sequel.desc(:event_no))
        .eager(:actor)
        .all
      render('maps/release_slices/_history_oob')
    end

    r.on String do |slice_id|
      next unless slice_id.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)

      @release_slice = ReleaseSlice.where(id: slice_id, map_id: @map.id).first
      next unless @release_slice

      r.get 'edit_name' do
        render('maps/release_slices/_slice_name_form')
      end

      r.get 'name' do
        render('maps/release_slices/_slice_name')
      end

      r.post 'delete' do
        if person_locked?
          if request.env['HTTP_HX_REQUEST']
            response.status = 422
            next ''
          end
          next r.redirect("/maps/#{@map.id}/release_slices")
        end

        story_count = Story.where(release_slice_id: @release_slice.id, archived_at: nil).count
        unless story_count.zero?
          if request.env['HTTP_HX_REQUEST']
            response.status = 422
            next 'Cannot delete a slice that has stories'
          end
          flash['error'] = 'Cannot delete a slice that has stories'
          next r.redirect("/maps/#{@map.id}/release_slices")
        end

        name = @release_slice.name
        DB.transaction do
          Story.where(release_slice_id: @release_slice.id).update(release_slice_id: nil)
          @release_slice.destroy
          RecordEvent.call(
            actor_id:     @current_actor.id,
            entity:       @release_slice,
            action:       'deleted',
            before_state: { name: name }
          )
        end
        if request.env['HTTP_HX_REQUEST']
          @slice_events = Event.where(map_id: @map.id, entity_type: 'release_slice')
            .order(Sequel.desc(:event_no)).eager(:actor).all
          @oob = true
          next render('maps/release_slices/_history_oob')
        end
        flash['notice'] = "Slice '#{@release_slice.name}' deleted"
        r.redirect "/maps/#{@map.id}/release_slices"
      end

      r.is do
        r.post do
          name = typecast_params.nonempty_str('name')

          @errors = []
          @errors << 'Name is required' unless name
          @errors << 'Name must be 100 characters or fewer' if name && name.length > 100

          unless @errors.empty?
            next render('maps/release_slices/_slice_name_form') if request.env['HTTP_HX_REQUEST']

            r.redirect "/maps/#{@map.id}/release_slices"
            next
          end

          DB.transaction do
            before = { name: @release_slice.name }
            @release_slice.update(name: name)
            RecordEvent.call(
              actor_id:     @current_actor.id,
              entity:       @release_slice,
              action:       'edited',
              before_state: before,
              after_state:  { name: name }
            )
          end

          if request.env['HTTP_HX_REQUEST']
            @slice_events = Event.where(map_id: @map.id, entity_type: 'release_slice')
              .order(Sequel.desc(:event_no)).eager(:actor).all
            @oob = true
            html = render('maps/release_slices/_slice_name')
            next html + render('maps/release_slices/_history_oob')
          end

          flash['notice'] = "Release slice '#{@release_slice.name}' updated"
          r.redirect "/maps/#{@map.id}/release_slices"
        end
      end
    end

    r.is do
      r.get do
        @subnav_active = 'slices'
        @release_slices = ReleaseSlice.where(map_id: @map.id, archived_at: nil).order(:position).all
        base = Event.where(map_id: @map.id, entity_type: 'release_slice')
        total = base.count
        @show_all_history = total > 20
        @slice_events = base.order(Sequel.desc(:event_no)).limit(20).eager(:actor).all
        view 'index'
      end

      r.post do
        name = typecast_params.nonempty_str('name')

        @errors = []
        @errors << 'Name is required' unless name
        @errors << 'Name must be 100 characters or fewer' if name && name.length > 100

        unless @errors.empty?
          @subnav_active = 'slices'
          @release_slice = ReleaseSlice.new
          next view('new')
        end

        DB.transaction do
          next_pos = (ReleaseSlice.where(map_id: @map.id).max(:position) || 0) + 1000
          @release_slice = ReleaseSlice.create(
            map_id:   @map.id,
            team_id:  @current_team.id,
            name:     name,
            position: next_pos
          )
          RecordEvent.call(
            actor_id:    @current_actor.id,
            entity:      @release_slice,
            action:      'created',
            after_state: { name: name, position: next_pos }
          )
        end

        flash['notice'] = "Release slice '#{@release_slice.name}' created"
        r.redirect "/maps/#{@map.id}/release_slices"
      end
    end
  end
end
