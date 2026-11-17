# frozen_string_literal: true

class Mainline
  hash_branch('maps', 'stories') do |r|
    r.get 'new' do
      @story = Story.new
      load_story_tasks
      @selected_task_id = typecast_params.str('task_id')
      template_idx = TeamConstraint.for_team(@current_team.id, 'default_story_template', default: 0)
      @default_template = %w[connextra card behaviour][template_idx] || 'connextra'
      view 'new'
    end

    r.is do
      r.post do
        task_id = typecast_params.nonempty_str('task_id')
        template, title = template_title

        story_count = Story.where(map_id: @map.id).count
        if ResourceCap.stories_per_map(story_count) == :warning
          flash['warning'] = "This map has #{story_count} stories. Consider splitting it."
        end

        if template && !title
          @errors = ['Fill in all template fields']
        else
          result = CreateStory.call(map: @map, team: @current_team, actor: @current_actor, person: @current_person,
            title: title, task_id: task_id)
          @errors = result.errors
        end

        unless @errors.empty?
          @story = Story.new
          load_story_tasks
          @selected_task_id = task_id
          next view('new')
        end

        @story = result.story
        flash['notice'] = "Story '#{@story.title}' created"
        r.redirect "/maps/#{@map.id}"
      end
    end

    r.on String do |story_id|
      next unless story_id.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)

      @story = Story[story_id]
      next unless @story && @story.map_id == @map.id

      r.get 'edit' do
        @subnav_active = 'edit'
        @title = @story.title
        load_edit_form_data
        load_story_history
        @selected_task_id = @story.task_id
        @selected_release_slice_id = @story.release_slice_id
        @scenarios = @story.scenarios
        view 'edit'
      end

      r.get 'feature' do
        response['Content-Type'] = 'text/plain; charset=utf-8'
        response['Content-Disposition'] = %(attachment; filename="#{FeatureFile.file_name(@story)}")
        FeatureFile.for(@story)
      end

      # The story's Step stubs list sends the language as a form field.
      r.get 'steps' do
        language = typecast_params.str('language')
        next unless StepStubs::LANGUAGES.key?(language)

        r.redirect "/maps/#{@map.id}/stories/#{@story.id}/steps/#{language}"
      end

      r.get 'steps', String do |language|
        next unless StepStubs::LANGUAGES.key?(language)

        response['Content-Type'] = 'text/plain; charset=utf-8'
        response['Content-Disposition'] = %(attachment; filename="#{StepStubs.file_name(@story, language)}")
        StepStubs.for(@story, language)
      end

      r.get 'card' do
        @story = Story.where(id: @story.id).eager(story_assignments: :person).first
        split_flags = SplitCandidate.check_batch([@story], team_id: @current_team.id)
        notes = build_story_notes([@story.id], split_flags)
        deploy_count = Event.where(entity_id: @story.id, action: 'deployed').count
        pref = DB[:map_view_prefs].where(person_id: @current_person.id, map_id: @map.id).first
        locked = pref ? pref[:locked] : false
        awaiting = TwoPersonRule.awaiting(@current_team).any? { |waiting| waiting.id == @story.id }
        locals = { story: @story, locked: locked, map_id: @map.id,
                   story_notes: notes[@story.id] || [], deploy_count: deploy_count, awaiting_walkthrough: awaiting,
                   urgent: UrgentStory.urgent?(@story), agent_assisted: AgentReads.read?(@story.id),
                   release_block: ReleaseBlock.of(@story) }
        render('maps/stories/_card', locals: locals)
      end

      r.get 'panel' do
        @title = @story.title
        load_edit_form_data
        load_story_history
        @selected_task_id = @story.task_id
        @selected_release_slice_id = @story.release_slice_id
        @scenarios = @story.scenarios
        @scenario_errors = []
        render('maps/stories/_panel')
      end

      r.is do
        r.post do
          title = typecast_params.nonempty_str('title')
          task_id = typecast_params.nonempty_str('task_id')
          release_slice_id = typecast_params.str('release_slice_id')
          result = EditStory.call(story: @story, actor: @current_actor, title: title, task_id: task_id,
            release_slice_id: release_slice_id, decoupling_strategy: typecast_params.str('decoupling_strategy'),
            decoupling_label: typecast_params.str('decoupling_label'))
          next edit_form_response(r) if result.success?

          @errors = result.errors
          @subnav_active = 'edit'
          @title = title || @story.title
          load_edit_form_data
          load_story_history
          @selected_task_id = task_id
          @selected_release_slice_id = release_slice_id
          @scenarios = @story.scenarios
          htmx?(r) ? render('maps/stories/_edit_form') : view('edit')
        end
      end

      r.get 'history' do
        @subnav_active = 'history'
        load_story_history
        view 'history'
      end

      r.post 'archive' do
        result = ArchiveStory.call(story: @story, actor: @current_actor)
        result.success? ? flash_msg.notice("Story '#{@story.title}' archived") : flash_msg.error(result.errors.first)
        htmx_grid_or_redirect(r)
      end

      r.post 'deploy' do
        result = DeployStory.call(story: @story, actor: @current_actor, now: Time.now)
        result.success? ? flash_msg.notice("Story '#{@story.title}' marked as deployed") : flash_msg.error(result.error)
        htmx_grid_or_redirect(r)
      end

      r.post 'urgent' do
        result = StartUrgentStory.call(story: @story, person_id: @current_person.id, reason: typecast_params.str('reason'),
          team: @current_team, actor_id: @current_actor.id)
        if result.success?
          flash_msg.notice("'#{@story.title}' is the team's urgent story")
        else
          flash_msg.error(result.error, reason: result.reason)
        end
        htmx_grid_or_redirect(r)
      end

      r.post 'release' do
        result = ReleaseStory.call(story: @story, team: @current_team, actor: @current_actor,
          reason: typecast_params.str('reason'), now: Time.now)
        if result.success?
          flash_msg.notice("Story '#{@story.title}' marked as released")
        else
          flash_msg.error(result.error, reason: result.reason)
        end
        htmx_grid_or_redirect(r)
      end

      r.post 'kickoff' do
        result = Kickoff.agree(story: @story, person: @current_person)
        unless htmx?(r)
          flash['error'] = result.error
          flash['error_reason'] = result.reason
          next r.redirect("/maps/#{@map.id}/stories/#{@story.id}/edit")
        end

        @scenarios = @story.scenarios
        @scenario_errors = [result.error].compact
        with_preview(render('maps/stories/_scenarios'))
      end

      r.hash_branches('maps/stories')
    end
  end

  private

  # The steps a story can go under, in map order: by activity, then by step.
  def load_story_tasks
    @tasks = Task.where(map_id: @map.id, archived_at: nil).eager(:activity).all
      .sort_by { |task| [task.activity.position, task.position] }
  end

  def load_edit_form_data
    load_story_tasks
    @release_slices = ReleaseSlice.where(map_id: @map.id, archived_at: nil).order(:position).all
  end

  def load_story_history
    @events = Event
      .where(entity_id: @story.id, entity_type: RecordEvent.entity_type_for(Story))
      .order(:event_no)
      .eager(:actor)
      .all
    @people_by_id = history_lookup(%w[person_id attendee_ids], Person)
    @slices_by_id = history_lookup('release_slice_id', ReleaseSlice)
    @tasks_by_id = history_lookup('task_id', Task)
  end

  # The records the events name under these keys, by ID. A key may hold one ID
  # or a list of them.
  def history_lookup(keys, model)
    ids = @events.flat_map { |e| Array(keys).flat_map { |key| [e.after_state&.dig(key), e.before_state&.dig(key)] } }
      .flatten.compact.uniq
    ids.empty? ? {} : model.where(id: ids).as_hash(:id)
  end

  def with_preview(html)
    load_story_history
    html + render('maps/stories/_preview_oob') + render('maps/stories/_expand_oob') + render('maps/stories/_history_oob')
  end

  def edit_form_response(req)
    if htmx?(req)
      @story.reload
      @title = @story.title
      load_edit_form_data
      @selected_task_id = @story.task_id
      @selected_release_slice_id = @story.release_slice_id
      @save_success = true
      with_preview(render('maps/stories/_edit_form'))
    else
      flash['notice'] = 'Story updated'
      req.redirect "/maps/#{@map.id}"
    end
  end
end
