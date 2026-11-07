# frozen_string_literal: true

module SetTeamContext
  def self.call(team_id)
    DB["SELECT set_config('app.current_team_id', ?, true)", team_id.to_s].get
  end
end
