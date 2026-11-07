# frozen_string_literal: true

class Mainline
  hash_branch('github') do |r|
    r.get 'callback' do
      team_id = SignedState.verify(r.params['state'])
      team_id ||= session.delete('monitor_install_team_id')
      team = team_id ? Team[team_id] : nil
      membership = team && TeamMembership.where(
        team_id: team.id, person_id: @current_person.id, left_at: nil
      ).first
      next r.redirect('/teams') unless team && membership

      SetTeamContext.call(team.id)
      installation_id = r.params['installation_id']
      if installation_id && !installation_id.empty?
        new_id = installation_id.to_i
        existing = TeamInstallation.where(
          team_id: team.id, provider: 'github', installation_id: new_id
        ).first
        unless existing
          org_name = CIMonitor::GithubAPI.installation_account(new_id)
          TeamInstallation.create(
            team_id: team.id, provider: 'github', installation_id: new_id, org_name: org_name
          )
        end
      end
      r.redirect "/teams/#{team.id}/monitor"
    end
  end
end
