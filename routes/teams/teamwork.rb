# frozen_string_literal: true

class Mainline
  hash_branch('teams', 'teamwork') do |r|
    @members = Person
      .join(:team_memberships, person_id: :id)
      .where(Sequel[:team_memberships][:team_id] => @team.id)
      .where(Sequel[:team_memberships][:working] => true)
      .where(Sequel[:team_memberships][:left_at] => nil)
      .select_all(:people)
      .order(Sequel[:people][:name])
      .all

    @window = [90, 180, 365].include?(r.params['window']&.to_i) ? r.params['window'].to_i : 180

    r.on 'walkthroughs' do
      r.post do
        story_id = typecast_params.str('story_id').to_s
        story = Story.where(id: story_id, team_id: @team.id).first if story_id.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
        next unless story

        attendee_ids = Array(r.params['attendee_ids']).grep(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
        result = RecordWalkthrough.call(story: story, actor: @current_actor, attendee_ids: attendee_ids)
        if result.success?
          flash['notice'] = "Walkthrough recorded for '#{story.title}'"
        else
          flash['error'] = result.error
          flash['error_reason'] = result.reason
        end
        r.redirect "/teams/#{@team.id}/teamwork/walkthroughs"
      end

      r.get do
        next r.redirect("/teams/#{@team.id}/teamwork") if @members.size < 2

        @active_tab = 'walkthroughs'
        @needed = Walkthroughs.needed(@team)
        @rule_on = TwoPersonRule.on?(@team)
        @limit = TwoPersonRule.limit(@team)
        @page_title = 'Walkthroughs - Mainline'
        view 'walkthroughs'
      end
    end

    r.get 'ensemble' do
      @active_tab = 'ensemble'
      @sessions = EnsembleTimeline.call(team_id: @team.id, days: @window)
      @page_title = 'Ensemble Timeline - Mainline'
      view 'ensemble'
    end

    r.get 'solo' do
      @active_tab = 'solo'
      @entries = SoloLog.call(team_id: @team.id, days: @window)
      @page_title = 'Solo Log - Mainline'
      view 'solo'
    end

    r.get do
      @active_tab = 'matrix'
      @matrix = PairingMatrix.call(team_id: @team.id, days: @window)
      @lens = %w[days current].include?(r.params['lens']) ? r.params['lens'] : 'stories'
      @page_title = 'Pairing Matrix - Mainline'
      view 'pairing'
    end
  end
end
