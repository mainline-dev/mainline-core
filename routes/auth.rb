# frozen_string_literal: true

class Mainline
  hash_branch('auth') do |r|
    r.get 'failure' do
      flash['error'] = 'Authentication failed. Please try again.'
      r.redirect '/login'
    end

    r.on String do |provider|
      next unless SignInProviders.enabled?(provider)

      r.get 'callback' do
        auth_hash = request.env['omniauth.auth']
        name  = auth_hash.info.name
        uid   = auth_hash.uid
        email = auth_hash.info.email
        email ||= "#{uid}+#{auth_hash.info.nickname}@users.noreply.github.com" if provider == 'github'

        identity = PersonIdentity.where(provider: provider, provider_subject: uid).first

        linking = session.delete('linking_provider')
        logged_in_person = linking && session['person_id'] ? Person[session['person_id']] : nil
        if logged_in_person
          if identity
            flash['error'] = 'That account is already linked to another user'
            next r.redirect('/profile/providers')
          end

          email_bidx = BlindIndex.generate_bidx(email, key: Lockbox.master_key)
          other = Person.where(email_bidx: email_bidx).exclude(id: logged_in_person.id).first
          if other
            flash['error'] = 'That account is already linked to another user'
            next r.redirect('/profile/providers')
          end

          PersonIdentity.create(
            person_id: logged_in_person.id, provider: provider,
            provider_subject: uid, email: email
          )
          flash['notice'] = "Connected #{PROVIDER_LABELS[provider] || provider}"
          next r.redirect('/profile/providers')
        end

        if identity
          person = Person[identity.person_id]
        else
          if email
            existing = Person.find_by_email(email)
            if existing
              flash['error'] = 'An account with that email already exists. ' \
                               'Sign in with your original provider and link this one from Connected Accounts.'
              next r.redirect('/login')
            end
          end

          session['pending_signup'] = {
            'name' => name, 'email' => email,
            'provider' => provider, 'uid' => uid,
            'oauth_token' => auth_hash.credentials&.token
          }
          next r.redirect('/confirm-email')
        end

        accept_invite(person, email, session)

        regenerate_session(preserve_keys: ['signup_plan'])
        session['person_id'] = person.id
        session['oauth_token'] = auth_hash.credentials&.token
        session['oauth_provider'] = provider
        flash['notice'] = "Signed in as #{person.name}"
        has_team = TeamMembership.where(person_id: person.id, left_at: nil).any?
        r.redirect(has_team ? '/teams' : '/teams/new')
      end
    end
  end
end
