# frozen_string_literal: true

class Mainline
  # Who is on a story: assigning someone, the picker's lists, and taking a
  # person off. routes/maps/stories.rb loads the story.
  hash_branch('maps/stories', 'assignments') do |r|
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
end
