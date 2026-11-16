# frozen_string_literal: true

class Mainline
  # A coding agent's app sends its person's browser here to sign in. Someone
  # signed out signs in to Mainline first and comes back. The person then
  # approves, for the teams they tick, or denies; either way the browser goes
  # back to the app. A request Mainline cannot answer that way gets a page.
  hash_branch('oauth') do |r|
    r.is 'authorize' do
      outcome = OauthRequest.check(r.params)
      next oauth_refused(outcome.page) if outcome.page
      next r.redirect(outcome.back) if outcome.back

      @oauth = outcome.request
      person = session['person_id'] && Person[session['person_id']]

      r.get do
        next oauth_sign_in_first(r) unless person

        oauth_consent(person)
      end

      r.post do
        next r.redirect('/login') unless person
        next r.redirect(OauthRequest.back(@oauth, error: 'access_denied')) unless r.params['decision'] == 'approve'

        result = SignInGrant.call(person: person, request: @oauth, team_ids: r.params['team_ids'])
        next r.redirect(OauthRequest.back(@oauth, code: result.code)) if result.success?

        @oauth_errors = result.errors
        response.status = 422
        oauth_consent(person)
      end
    end
  end

  def oauth_consent(person)
    @oauth_teams = Team.where(id: MapAccess.team_ids_for(person.id)).order(:name).all
    return oauth_refused("You aren't working on a team yet, so there is nothing a coding agent could read.") if @oauth_teams.empty?

    view 'oauth/consent', layout: false
  end

  def oauth_refused(message)
    response.status = 400
    @oauth_refusal = message
    view 'oauth/refused', layout: false
  end

  # Back here once signed in: sign-in keeps this address and returns to it.
  def oauth_sign_in_first(req)
    session['oauth_return'] = req.fullpath
    flash['notice'] = 'Sign in to Mainline to connect your coding agent.'
    req.redirect '/login'
  end
end
