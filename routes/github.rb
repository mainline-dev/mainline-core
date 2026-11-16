# frozen_string_literal: true

class Mainline
  hash_branch('github') do |r|
    # Where GitHub sends a person after they install the CI Monitor's app. The
    # installation number in the address can be anyone's, so it is linked only
    # for the install this session started, and only when GitHub lists that
    # installation for the person (GithubInstall).
    r.get 'callback' do
      next r.redirect('/teams') unless CIMonitorSetup.on?

      team_id = GithubInstall.finish(session, r.params['state'])
      team = team_id && Team[team_id]
      membership = team && TeamMembership.where(
        team_id: team.id, person_id: @current_person.id, left_at: nil
      ).first
      next r.redirect('/teams') unless team && membership

      SetTeamContext.call(team.id)
      monitor = "/teams/#{team.id}/monitor"
      installation_id = typecast_params.pos_int('installation_id')
      next r.redirect(monitor) unless installation_id

      token = GithubInstall.token(session)
      next r.redirect("#{monitor}/install") unless token

      installation = begin
        GithubInstall.seen(token, installation_id)
      rescue CIMonitor::GithubAPI::Error
        next r.redirect("#{monitor}/install")
      end
      if installation
        GithubInstall.link(team.id, installation)
      else
        flash['error'] = "GitHub doesn't list that installation for you, so it wasn't connected."
      end
      r.redirect monitor
    end
  end
end
