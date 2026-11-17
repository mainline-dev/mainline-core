# frozen_string_literal: true

class Mainline
  hash_branch('maps', 'stories') do |r|
    r.get 'new' do
      @story = Story.new
      @tasks = Task
        .where(map_id: @map.id, archived_at: nil)
        .eager(:activity)
        .all
        .sort_by { |t| [t.activity.position, t.position] }
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
          @tasks = Task
            .where(map_id: @map.id, archived_at: nil)
            .eager(:activity)
            .all
            .sort_by { |t| [t.activity.position, t.position] }
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

      r.on 'assignments' do
        r.get 'new' do
          @subnav_active = 'assign'
          if @story.status == 'released'
            flash['error'] = 'Cannot assign people to a released story'
            next r.redirect "/maps/#{@map.id}"
          end
          load_assignable_people
          view 'assign'
        end

        r.get 'inline' do
          load_assignable_people
          render('maps/stories/assignments/_inline_dropdown')
        end

        r.is do
          r.post do
            if @story.status == 'released'
              flash['error'] = 'Cannot assign people to a released story'
              next r.redirect "/maps/#{@map.id}"
            end

            person_id = typecast_params.nonempty_str('person_id')
            result = AssignPerson.call(
              story: @story, person_id: person_id,
              team: @current_team, actor_id: @current_actor.id
            )

            unless result.success?
              @errors = result.errors
              @subnav_active = 'assign'
              load_assignable_people
              next view('assign')
            end

            flash_msg.notice('Person assigned')
            htmx_grid_or_redirect(r, fallback: "/maps/#{@map.id}/stories/#{@story.id}/assignments/new")
          end
        end

        r.on String do |assignment_id|
          next unless assignment_id.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)

          assignment = StoryAssignment[assignment_id]
          next unless assignment && assignment.story_id == @story.id

          r.post 'unassign' do
            result = UnassignPerson.call(story: @story, assignment: assignment, actor: @current_actor)
            unless result.success?
              flash['error'] = result.error
              next r.redirect "/maps/#{@map.id}"
            end

            flash_msg.notice('Person unassigned')
            htmx_grid_or_redirect(r)
          end
        end
      end

      r.on 'split' do
        r.get do
          next r.redirect("/maps/#{@map.id}") if @story.status == 'released' || @story.archived_at

          @split_scenarios = Scenario.where(story_id: @story.id, done_at: nil).order(:position).all
          @split_errors = []
          @form = {}
          view 'maps/stories/split'
        end

        r.post do
          scenario_ids = Array(r.params['scenario_ids']).grep(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
          edits = scenario_ids.to_h { |sid|
            [sid, { given: typecast_params.str("scenario_#{sid}_given"),
                    when:  typecast_params.str("scenario_#{sid}_when"),
                    then:  typecast_params.str("scenario_#{sid}_then") }]
          }
          template, title = template_title
          story_count = Story.where(map_id: @map.id).count
          result = if ResourceCap.stories_per_map(story_count) == :blocked
                     :map_capped
                   else
                     SplitStory.call(
                       story: @story, actor: @current_actor, person: @current_person,
                       title: title, scenario_ids: scenario_ids, scenario_edits: edits
                     )
                   end
          if result.is_a?(Symbol)
            @split_errors = [split_error_message(result, template)]
            @split_scenarios = Scenario.where(story_id: @story.id, done_at: nil).order(:position).all
            @form = r.params
            next view('maps/stories/split')
          end

          flash['notice'] = "Story '#{result.title}' split out from '#{@story.title}'"
          r.redirect "/maps/#{@map.id}"
        end
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

  def load_assignable_people
    assigned_ids = StoryAssignment.where(story_id: @story.id).select_map(:person_id)
    @available_people = available_team_members(assigned_ids)
    @busy_person_ids = AssignPerson.people_at_limit(@current_team)
  end

  def available_team_members(excluded_ids)
    Person
      .join(:team_memberships, person_id: :id)
      .where(team_id: @current_team.id)
      .where(Sequel[:team_memberships][:working] => true)
      .where(Sequel[:team_memberships][:left_at] => nil)
      .exclude(Sequel[:people][:id] => excluded_ids)
      .select_all(:people)
      .all
  end

  def load_edit_form_data
    @tasks = Task
      .where(map_id: @map.id, archived_at: nil)
      .eager(:activity)
      .all
      .sort_by { |t| [t.activity.position, t.position] }
    @release_slices = ReleaseSlice.where(map_id: @map.id, archived_at: nil).order(:position).all
  end

  def split_error_message(result, template = nil)
    return 'Fill in all template fields' if result == :title_required && template

    {
      released:           'Released stories cannot be split',
      archived:           'Archived stories cannot be split',
      map_capped:         'This map has reached its story limit',
      title_required:     'Name the new story before saving',
      title_too_long:     'Title must be 200 characters or fewer',
      scenario_invalid:   'Scenario fields must be 1-100 characters',
      scenarios_required: 'Select at least one scenario to split out'
    }.fetch(result)
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
