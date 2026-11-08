# frozen_string_literal: true

class Mainline
  hash_branch('maps', 'tasks') do |r|
    r.get 'new' do
      @task = Task.new
      @activities = Activity.where(map_id: @map.id, archived_at: nil).order(:position).all
      @selected_activity_id = typecast_params.str('activity_id')
      view 'new'
    end

    r.on String do |task_id|
      next unless task_id.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)

      @task = Task.where(id: task_id, map_id: @map.id).first || response.finish

      r.get 'edit' do
        @activities = Activity.where(map_id: @map.id, archived_at: nil).order(:position).all
        @selected_activity_id = @task.activity_id
        view 'edit'
      end

      r.is do
        r.post do
          activity_id = typecast_params.nonempty_str('activity_id')
          result = EditTask.call(
            task: @task, actor: @current_actor,
            name: typecast_params.nonempty_str('name'), activity_id: activity_id
          )

          unless result.success?
            @errors = result.errors
            @activities = Activity.where(map_id: @map.id, archived_at: nil).order(:position).all
            @selected_activity_id = activity_id
            next view('edit')
          end

          flash['notice'] = "Step '#{@task.name}' updated"
          r.redirect "/maps/#{@map.id}"
        end
      end

      r.post 'archive' do
        if Story.where(task_id: @task.id, archived_at: nil).any?
          flash_msg.error('Cannot archive a step that has stories')
          next htmx_grid_or_redirect(r)
        end

        DB.transaction do
          @task.update(archived_at: Time.now)
          RecordEvent.call(
            actor_id:    @current_actor.id,
            entity:      @task,
            action:      'archived',
            after_state: { name: @task.name }
          )
        end

        flash_msg.notice("Step '#{@task.name}' archived")
        htmx_grid_or_redirect(r)
      end

      r.post 'reorder_stories' do
        if person_locked?
          response.status = 422
          next ''
        end

        story_ids = Array(r.params['story_id'])
        release_slice_id = r.params['release_slice_id']

        result = ReorderStories.call(
          task: @task, story_ids: story_ids, actor: @current_actor,
          release_slice_id: release_slice_id, map_id: @map.id
        )

        if result
          response.status = 422
          next ''
        end

        response.status = 200
        ''
      end
    end

    r.post do
      activity_id = typecast_params.nonempty_str('activity_id')
      result = CreateTask.call(
        map: @map, team: @current_team, actor: @current_actor,
        name: typecast_params.nonempty_str('name'), activity_id: activity_id
      )

      unless result.success?
        @errors = result.errors
        @task = Task.new
        @activities = Activity.where(map_id: @map.id, archived_at: nil).order(:position).all
        @selected_activity_id = activity_id
        next view('new')
      end

      flash['notice'] = "Step '#{result.task.name}' created"
      r.redirect "/maps/#{@map.id}"
    end
  end
end
