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
        locals = { story: @story, locked: locked, map_id: @map.id,
                   story_notes: notes[@story.id] || [], deploy_count: deploy_count }
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
          decoupling_strategy = typecast_params.str('decoupling_strategy')
          decoupling_label = typecast_params.str('decoupling_label')

          if @story.status == 'released'
            strategy = decoupling_strategy.to_s.empty? ? nil : decoupling_strategy
            label = strategy && !decoupling_label.to_s.empty? ? decoupling_label[0, 50] : nil
            DB.transaction do
              before = {
                decoupling_strategy: @story.decoupling_strategy,
                decoupling_label:    @story.decoupling_label
              }
              @story.update(decoupling_strategy: strategy, decoupling_label: label)
              RecordEvent.call(
                actor_id:     @current_actor.id,
                entity:       @story,
                action:       'edited',
                before_state: before,
                after_state:  { decoupling_strategy: strategy, decoupling_label: label }
              )
            end
            next edit_form_response(r)
          end

          title = typecast_params.nonempty_str('title')
          task_id = typecast_params.nonempty_str('task_id')
          release_slice_id = typecast_params.str('release_slice_id')

          @errors = []
          @errors << 'Title is required' unless title
          @errors << 'Title must be 200 characters or fewer' if title && title.length > 200
          @errors << 'Step is required' unless task_id

          unless @errors.empty?
            @subnav_active = 'edit'
            @title = title || @story.title
            load_edit_form_data
            load_story_history
            @selected_task_id = task_id
            @selected_release_slice_id = release_slice_id
            @scenarios = @story.scenarios
            next htmx?(r) ? render('maps/stories/_edit_form') : view('edit')
          end

          strategy = decoupling_strategy.to_s.empty? ? nil : decoupling_strategy
          label = decoupling_label[0, 50] if strategy && !decoupling_label.to_s.empty?

          updates = { title: title, task_id: task_id }
          updates[:position] = (Story.where(task_id: task_id, archived_at: nil).max(:position) || 0) + 1000 if task_id != @story.task_id
          updates[:release_slice_id] = release_slice_id.to_s.empty? ? nil : release_slice_id
          updates[:decoupling_strategy] = strategy
          updates[:decoupling_label] = label
          DB.transaction do
            before = { title: @story.title, task_id: @story.task_id, release_slice_id: @story.release_slice_id,
                        decoupling_strategy: @story.decoupling_strategy, decoupling_label: @story.decoupling_label }
            @story.update(updates)
            RecordEvent.call(
              actor_id:     @current_actor.id,
              entity:       @story,
              action:       'edited',
              before_state: before,
              after_state:  updates
            )
          end

          edit_form_response(r)
        end
      end

      r.get 'history' do
        @subnav_active = 'history'
        @events = Event
          .where(entity_id: @story.id, entity_type: RecordEvent.entity_type_for(Story))
          .order(:event_no)
          .eager(:actor)
          .all

        person_ids = @events.flat_map { |e|
          [e.after_state&.dig('person_id'), e.before_state&.dig('person_id')]
        }.compact.uniq
        @people_by_id = person_ids.empty? ? {} : Person.where(id: person_ids).as_hash(:id)

        slice_ids = @events.flat_map { |e|
          [e.after_state&.dig('release_slice_id'), e.before_state&.dig('release_slice_id')]
        }.compact.uniq
        @slices_by_id = slice_ids.empty? ? {} : ReleaseSlice.where(id: slice_ids).as_hash(:id)

        task_ids = @events.flat_map { |e|
          [e.after_state&.dig('task_id'), e.before_state&.dig('task_id')]
        }.compact.uniq
        @tasks_by_id = task_ids.empty? ? {} : Task.where(id: task_ids).as_hash(:id)

        view 'history'
      end

      r.post 'archive' do
        result = ArchiveStory.call(story: @story, actor: @current_actor)
        result.success? ? flash_msg.notice("Story '#{@story.title}' archived") : flash_msg.error(result.errors.first)
        htmx_grid_or_redirect(r)
      end

      r.post 'deploy' do
        unless @story.status == 'active'
          flash_msg.error('Only active stories can be deployed')
          next htmx_grid_or_redirect(r)
        end

        now = Time.now
        DB.transaction do
          updates = { deploy_count: Sequel.lit('deploy_count + 1'), last_deployed_at: now }
          updates[:first_deployed_at] = now if @story.deploy_count.zero?
          DB[:stories].where(id: @story.id).update(updates)
          RecordEvent.call(
            actor_id:    @current_actor.id,
            entity:      @story,
            action:      'deployed',
            after_state: { deploy_count: @story.deploy_count + 1 }
          )
        end

        flash_msg.notice("Story '#{@story.title}' marked as deployed")
        next htmx_grid_or_redirect(r)
      end

      r.post 'release' do
        if @story.status == 'active' && @story.deploy_count.positive?
          undone = Scenario.where(story_id: @story.id, done_at: nil).count
          if undone.positive?
            plural = undone == 1 ? 'scenario' : 'scenarios'
            flash_msg.error("#{undone} #{plural} not yet verified. Mark them done or split them out before releasing.",
              reason: 'unverified-scenarios')
            next htmx_grid_or_redirect(r)
          end
          DB.transaction do
            StoryAssignment.where(story_id: @story.id).each do |sa|
              sa.destroy
              RecordEvent.call(
                actor_id:     @current_actor.id,
                entity:       @story,
                action:       'person_unassigned',
                before_state: { person_id: sa.person_id, reason: 'released' }
              )
            end
            @story.update(status: 'released', released_at: Time.now)
            RecordEvent.call(
              actor_id:    @current_actor.id,
              entity:      @story,
              action:      'released',
              after_state: { status: 'released' }
            )
            SplitCandidate.invalidate_threshold!(@current_team.id)
          end
          flash_msg.notice("Story '#{@story.title}' marked as released")
        else
          msg = if @story.status == 'active'
                  'Story must be deployed at least once before release'
                else
                  'Only active stories can be released'
                end
          flash_msg.error(msg)
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
            if @story.status == 'released'
              flash['error'] = 'Cannot modify a released story'
              next r.redirect "/maps/#{@map.id}"
            end

            person_id = assignment.person_id

            DB.transaction do
              assignment.destroy
              RecordEvent.call(
                actor_id:     @current_actor.id,
                entity:       @story,
                action:       'person_unassigned',
                before_state: { person_id: person_id }
              )

              remaining = StoryAssignment.where(story_id: @story.id).count
              if remaining.zero? && @story.status == 'active'
                @story.update(status: 'planned')
                RecordEvent.call(
                  actor_id:    @current_actor.id,
                  entity:      @story,
                  action:      'deactivated',
                  after_state: { reason: 'no_assignees' }
                )
              elsif @story.status == 'active'
                AssignPerson.record_collaboration_change(@story, @current_actor.id, remaining + 1, remaining)
              end
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

      r.on 'scenarios' do
        r.is do
          r.get do
            @scenarios = @story.scenarios
            @scenario_errors = []
            render('maps/stories/_scenarios')
          end

          r.post do
            next render('maps/stories/_scenarios') if @story.status == 'released'

            name  = typecast_params.str('name').to_s.strip
            given = typecast_params.str('given').to_s.strip
            whn   = typecast_params.str('when').to_s.strip
            thn   = typecast_params.str('then').to_s.strip

            @scenario_errors = AddScenario.call(story: @story, actor: @current_actor, name: name, given_text: given,
              when_text: whn, then_text: thn).errors

            @scenarios = Scenario.where(story_id: @story.id).order(:position).all
            with_preview(render('maps/stories/_scenarios'))
          end
        end

        r.on String do |scenario_id|
          next unless scenario_id.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)

          scenario = Scenario[scenario_id]
          next unless scenario && scenario.story_id == @story.id

          r.post 'delete' do
            unless @story.status == 'released'
              scenario.destroy
              RecordEvent.call(
                actor_id: @current_actor.id,
                entity:   @story,
                action:   'scenario_removed'
              )
            end
            @scenarios = Scenario.where(story_id: @story.id).order(:position).all
            @scenario_errors = []
            with_preview(render('maps/stories/_scenarios'))
          end

          r.post 'done' do
            if @story.status != 'released' && scenario.done_at.nil?
              DB.transaction do
                scenario.update(done_at: Time.now)
                RecordEvent.call(
                  actor_id: @current_actor.id,
                  entity:   @story,
                  action:   'scenario_done'
                )
              end
            end
            @scenarios = Scenario.where(story_id: @story.id).order(:position).all
            @scenario_errors = []
            with_preview(render('maps/stories/_scenarios'))
          end

          r.post 'undone' do
            if @story.status != 'released' && scenario.done_at
              DB.transaction do
                scenario.update(done_at: nil)
                RecordEvent.call(
                  actor_id: @current_actor.id,
                  entity:   @story,
                  action:   'scenario_undone'
                )
              end
            end
            @scenarios = Scenario.where(story_id: @story.id).order(:position).all
            @scenario_errors = []
            with_preview(render('maps/stories/_scenarios'))
          end

          r.is do
            r.post do
              next render('maps/stories/_scenarios') if @story.status == 'released'

              name  = typecast_params.str('name').to_s.strip
              given = typecast_params.str('given').to_s.strip
              whn   = typecast_params.str('when').to_s.strip
              thn   = typecast_params.str('then').to_s.strip

              @scenario_errors = AddScenario.errors(name, given, whn, thn)

              scenario.update(name: name, given_text: given, when_text: whn, then_text: thn) if @scenario_errors.empty?

              @scenarios = Scenario.where(story_id: @story.id).order(:position).all
              with_preview(render('maps/stories/_scenarios'))
            end
          end
        end
      end
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

  def template_title
    template = typecast_params.nonempty_str('template')
    title = case template
            when 'connextra' then connextra_title
            when 'behaviour' then behaviour_title
            when 'card'      then card_title
            else typecast_params.nonempty_str('title')
            end
    [template, title]
  end

  def connextra_title
    role    = typecast_params.nonempty_str('role')
    goal    = typecast_params.nonempty_str('goal')
    benefit = typecast_params.nonempty_str('benefit')
    "As a #{role}, I want to #{goal}, so that #{benefit}" if role && goal && benefit
  end

  def behaviour_title
    context = typecast_params.nonempty_str('beh_context')
    persona = typecast_params.nonempty_str('beh_persona')
    action  = typecast_params.nonempty_str('beh_action')
    "When #{context}, #{persona} can #{action}" if context && persona && action
  end

  def card_title
    persona = typecast_params.nonempty_str('card_persona')
    action  = typecast_params.nonempty_str('card_action')
    "#{persona} #{action}" if persona && action
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
    @people_by_id = history_lookup('person_id', Person)
    @slices_by_id = history_lookup('release_slice_id', ReleaseSlice)
    @tasks_by_id = history_lookup('task_id', Task)
  end

  def history_lookup(key, model)
    ids = @events.flat_map { |e| [e.after_state&.dig(key), e.before_state&.dig(key)] }.compact.uniq
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
