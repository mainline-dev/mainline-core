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
