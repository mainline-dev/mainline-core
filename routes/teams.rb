# frozen_string_literal: true

require_relative '../lib/rate_limiter'

INVITE_RATE_LIMITER = SharedRateLimiter.new(name: 'invite', capacity: 10, refill_rate: 10.0 / 3600)

class Mainline
  hash_branch('teams') do |r|
    r.get 'new' do
      @team_name = ''
      view 'new'
    end

    r.is do
      r.get do
        @teams = Team.join(:team_memberships, team_id: :id)
          .where(Sequel[:team_memberships][:person_id] => @current_person.id)
          .where(Sequel[:team_memberships][:left_at] => nil)
          .select_all(:teams).all
        team_ids = @teams.map(&:id)
        @team_map_counts = BypassRLS.call {
          Map.where(team_id: team_ids, archived_at: nil)
            .group_and_count(:team_id).to_hash(:team_id, :count)
        }
        @team_member_counts = TeamMembership.where(team_id: team_ids, left_at: nil, working: true)
          .group_and_count(:team_id).to_hash(:team_id, :count)
        working_memberships = TeamMembership.where(team_id: team_ids, left_at: nil, working: true).all
        person_ids = working_memberships.map(&:person_id).uniq
        people = person_ids.any? ? Person.where(id: person_ids).to_hash(:id) : {}
        @team_members = working_memberships.group_by(&:team_id).transform_values { |ms| ms.map { |m| people[m.person_id]&.name }.compact }
        @can_create_team = !holds_suspended_team?
        view 'pick'
      end

      r.post do
        team_name = typecast_params.nonempty_str('team_name')

        if holds_suspended_team?
          flash['error'] = 'One of your teams is suspended. Resolve it before creating another.'
          next r.redirect '/teams'
        end

        team_count = TeamMembership.where(person_id: @current_person.id, left_at: nil).count
        cap = ResourceCap.teams_per_person(team_count)

        has_email_identity = PersonIdentity.where(person_id: @current_person.id, provider: 'email').any?
        if has_email_identity && @current_person.email_verified_at.nil?
          flash['error'] = 'Please verify your email before creating a team.'
          next r.redirect '/teams'
        end

        @errors = []
        @errors << 'You have reached your team limit' if cap == :blocked
        @errors << 'Team name is required' unless team_name
        @errors << 'Team name must be 100 characters or fewer' if team_name && team_name.length > 100

        flash['warning'] = "You belong to #{team_count} teams." if cap == :warning

        unless @errors.empty?
          @team_name = team_name || ''
          next view('new')
        end

        @current_team = Team.create(name: team_name, creator_id: @current_person.id)
        TeamMembership.create(
          team_id:   @current_team.id,
          person_id: @current_person.id,
          working:   false
        )
        CoreEvents.publish(:team_created, team_id: @current_team.id, creator_id: @current_person.id)

        flash['notice'] = "Team '#{@current_team.name}' created"
        r.redirect "/teams/#{@current_team.id}"
      end
    end

    r.on String do |team_id|
      next unless team_id.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)

      @team = Team[team_id]
      next unless @team

      @membership = TeamMembership.where(
        team_id: @team.id, person_id: @current_person.id, left_at: nil
      ).first

      unless @membership
        response.status = 403
        next view(content: '<p>You are not a member of this team.</p><p><a href="/teams">Go to your teams</a></p>')
      end

      @current_team = @team
      session['team_id'] = @team.id
      @is_creator = @team.creator_id == @current_person.id
      @is_working_member = @membership.working

      r.on 'account' do
        unless !@membership.working || @is_creator
          response.status = 403
          next view(content: '<p>Only the account holder can access this page.</p><p><a href="/teams">Go to your teams</a></p>')
        end

        append_view_subdir('account')

        r.is do
          r.get do
            working_ids = TeamMembership.where(team_id: @team.id, left_at: nil, working: true)
              .select_map(:person_id)
            @working_members = working_ids.any? ? Person.where(id: working_ids).all : []
            view 'index'
          end
        end

        r.post 'join' do
          @membership.update(working: true)
          flash['notice'] = 'You joined the team as a working member'
          r.redirect "/teams/#{@team.id}"
        end

        r.get 'export' do
          unless @is_creator
            response.status = 403
            next view(content: '<p>Only the account holder can export team data.</p><p><a href="/teams">Go to your teams</a></p>')
          end

          response['Content-Type'] = 'application/json'
          safe_name = @team.name.gsub(/[^a-zA-Z0-9 _-]/, '')
          response['Content-Disposition'] = "attachment; filename=\"#{safe_name}-export.json\""
          DataExport.to_json(team_id: @team.id)
        end

        r.on 'delete' do
          unless @is_creator
            response.status = 403
            next view(content: '<p>Only the account holder can delete this team.</p><p><a href="/teams">Go to your teams</a></p>')
          end

          r.get do
            view 'delete'
          end

          r.post do
            confirmation = typecast_params.str('confirmation')
            expected = "DELETE #{@team.name}"
            unless confirmation == expected
              flash['error'] = 'Confirmation did not match'
              next r.redirect "/teams/#{@team.id}/account/delete"
            end

            DeleteTeam.call(team: @team)
            session.clear
            r.redirect '/'
          end
        end
      end

      leave_suspended_team(r, @team) if @team.suspended? && !r.remaining_path.start_with?('/monitor')

      SetTeamContext.call(@team.id)

      r.on 'edit' do
        unless @is_creator
          response.status = 403
          next view(content: '<p>Only the account holder can rename this team.</p><p><a href="/teams">Go to your teams</a></p>')
        end

        r.get do
          @team_name = @team.name
          view 'teams/edit'
        end

        r.post do
          name = typecast_params.nonempty_str('name')

          @errors = []
          @errors << 'Name is required' if name.nil? || name.empty?
          @errors << 'Name must be 100 characters or fewer' if name && name.length > 100

          unless @errors.empty?
            @team_name = @team.name
            next view('teams/edit')
          end

          DB.transaction do
            before = { name: @team.name }
            @team.update(name: name)
            RecordEvent.call(
              actor_id:     @current_actor.id,
              entity:       @team,
              action:       'edited',
              team_id:      @team.id,
              before_state: before,
              after_state:  { name: name }
            )
          end

          flash['notice'] = 'Team renamed'
          r.redirect "/teams/#{@team.id}"
        end
      end

      r.on 'members' do
        r.is do
          r.get do
            working_ids = TeamMembership.where(team_id: @team.id, left_at: nil, working: true).select_map(:person_id)
            @working_members = working_ids.any? ? Person.where(id: working_ids).all : []
            archived_ids = TeamMembership.where(team_id: @team.id, working: true).exclude(left_at: nil).select_map(:person_id)
            @archived_members = archived_ids.any? ? Person.where(id: archived_ids).all : []
            @invitations = Invitation.where(team_id: @team.id, accepted_at: nil).all
            @page_title = 'Members - Mainline'
            view 'members'
          end
        end

        r.on 'invites' do
          r.post do
            unless INVITE_RATE_LIMITER.allow?(@team.id)
              flash['error'] = 'Too many invites. Try again later.'
              next r.redirect "/teams/#{@team.id}/members"
            end

            email = typecast_params.nonempty_str('email')

            unless email
              flash['error'] = 'Email is required'
              next r.redirect "/teams/#{@team.id}/members"
            end

            email_bidx = BlindIndex.generate_bidx(email, key: Lockbox.master_key)

            if Invitation.where(team_id: @team.id, email_bidx: email_bidx, accepted_at: nil).any?
              flash['error'] = 'This person has already been invited'
              next r.redirect "/teams/#{@team.id}/members"
            end

            member_ids = TeamMembership.where(team_id: @team.id, left_at: nil).select_map(:person_id)
            if member_ids.any? && Person.where(id: member_ids, email_bidx: email_bidx).any?
              flash['error'] = 'This person is already on the team'
              next r.redirect "/teams/#{@team.id}/members"
            end

            token = SecureRandom.urlsafe_base64(32)
            invitation = Invitation.create(
              team_id:    @team.id,
              email:      email,
              token:      InviteToken.digest(token),
              invited_by: @current_person.id,
              expires_at: Time.now + (86_400 * 7)
            )

            link = SendInviteEmail.call(
              invitation: invitation, inviter: @current_person, team: @team, token: token
            )
            if link == :failed
              invitation.destroy
              flash['error'] = 'Could not send the invitation. Please try again.'
            else
              flash['notice'] = link ? "Invite link: #{link}" : "Invitation sent to #{email}"
            end
            r.redirect "/teams/#{@team.id}/members"
          end
        end

        r.on String do |person_id|
          next unless person_id.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)

          unless @is_creator
            response.status = 403
            next view(content: '<p>Only the account holder can manage members.</p><p><a href="/teams">Go to your teams</a></p>')
          end

          target_membership = TeamMembership.where(
            team_id: @team.id, person_id: person_id, left_at: nil, working: true
          ).first
          next unless target_membership

          r.post 'archive' do
            if person_id == @current_person.id
              flash['error'] = 'You cannot archive yourself'
              next r.redirect "/teams/#{@team.id}/members"
            end

            DB.transaction do
              target_membership.update(left_at: Time.now)
              person = Person[person_id]
              RecordEvent.call(
                actor_id:     @current_actor.id,
                entity:       target_membership,
                action:       'member_archived',
                before_state: { person_id: person_id, name: person.name }
              )

              StoryAssignment.where(person_id: person_id, team_id: @team.id).each do |sa|
                story = Story[sa.story_id]
                sa.destroy
                RecordEvent.call(
                  actor_id:     @current_actor.id,
                  entity:       story,
                  action:       'person_unassigned',
                  before_state: { person_id: person_id }
                )

                remaining = StoryAssignment.where(story_id: story.id).count
                next unless remaining.zero? && story.status == 'active'

                story.update(status: 'planned')
                RecordEvent.call(
                  actor_id:    @current_actor.id,
                  entity:      story,
                  action:      'deactivated',
                  after_state: { reason: 'no_assignees' }
                )
              end
            end

            flash['notice'] = 'Member archived'
            r.redirect "/teams/#{@team.id}/members"
          end
        end
      end

      r.is do
        r.get do
          @maps = Map.where(team_id: @team.id, archived_at: nil).order(:position).all
          map_ids = @maps.map(&:id)
          @activity_counts = if map_ids.any?
                               Activity.where(map_id: map_ids, archived_at: nil)
                                 .group_and_count(:map_id).to_hash(:map_id, :count)
                             else
                               {}
                             end
          @story_counts = if map_ids.any?
                            Story.where(map_id: map_ids, archived_at: nil)
                              .group_and_count(:map_id).to_hash(:map_id, :count)
                          else
                            {}
                          end
          @active_counts = if map_ids.any?
                             Story.where(map_id: map_ids, archived_at: nil, status: 'active')
                               .group_and_count(:map_id).to_hash(:map_id, :count)
                           else
                             {}
                           end
          @last_events = if map_ids.any?
                           Event.where(map_id: map_ids)
                             .group_and_count(:map_id)
                             .select_append(Sequel.function(:max, :occurred_at).as(:last_at))
                             .all
                             .to_h { |r| [r[:map_id], r[:last_at]] }
                         else
                           {}
                         end
          @page_title = "#{@team.name} - Mainline"
          view 'show'
        end
      end

      unless @membership.working
        flash['notice'] = 'Join as a working member to access this page'
        next r.redirect("/teams/#{@team.id}")
      end

      r.hash_branches('teams')
    end
  end
end
