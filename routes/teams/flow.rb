# frozen_string_literal: true

class Mainline
  hash_branch('teams', 'flow') do |r|
    @maps = Map.where(team_id: @team.id, archived_at: nil).order(:position).all
    map_id_param = r.params['map_id']
    @map_filter = map_id_param if map_id_param && @maps.any? { |m| m.id.to_s == map_id_param }

    r.get 'lead-time' do
      @days = if r.params.key?('days')
                %w[30 60 90].include?(r.params['days']) ? r.params['days'].to_i : nil
              else
                30
              end
      @histogram = LeadTime.call(team_id: @team.id, days: @days, map_id: @map_filter)
      @page_title = 'Lead Time - Mainline'
      view 'lead_time'
    end

    r.get 'throughput' do
      @days = if r.params.key?('days')
                %w[30 60 90].include?(r.params['days']) ? r.params['days'].to_i : nil
              else
                30
              end
      @lens = %w[released deployed both].include?(r.params['lens']) ? r.params['lens'] : 'released'
      if @lens == 'both'
        @deploy_scatter = ThroughputScatter.call(team_id: @team.id, action: 'deployed', days: @days, map_id: @map_filter)
        @release_scatter = ThroughputScatter.call(team_id: @team.id, action: 'released', days: @days, map_id: @map_filter)
      else
        @scatter = ThroughputScatter.call(team_id: @team.id, action: @lens, days: @days, map_id: @map_filter)
      end
      @page_title = 'Throughput - Mainline'
      view 'throughput'
    end

    r.get do
      @days = if r.params.key?('days')
                %w[30 60 90].include?(r.params['days']) ? r.params['days'].to_i : nil
              else
                30
              end
      @cfd = CumulativeFlow.call(team_id: @team.id, days: @days, map_id: @map_filter)
      @page_title = 'Cumulative Flow - Mainline'
      view 'cfd'
    end
  end
end
