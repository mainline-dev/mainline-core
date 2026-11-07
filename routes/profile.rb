# frozen_string_literal: true

require 'bcrypt'

class Mainline
  hash_branch('profile') do |r|
    next r.redirect('/login') unless @current_person

    r.hash_branches('profile')

    r.is 'password' do
      r.post do
        unless AUTH_RATE_LIMITER.allow?(request.ip)
          flash['error'] = 'Too many requests. Try again later.'
          next r.redirect('/profile/providers')
        end
        password = r.params['password'].to_s

        password_error = validate_password(password)
        if password_error
          flash['error'] = password_error
          next r.redirect('/profile/providers')
        end

        identity = PersonIdentity.where(person_id: @current_person.id, provider: 'email').first
        if identity && !session.delete('magic_login')
          current = r.params['current_password'].to_s
          error = if current.empty? then 'Current password is required'
                  elsif BCrypt::Password.new(identity.password_digest) != current then 'Current password is incorrect'
                  end
          if error
            flash['error'] = error
            next r.redirect('/profile/providers')
          end
        end
        if identity
          identity.update(password_digest: BCrypt::Password.create(password, cost: 12))
        else
          email_bidx = BlindIndex.generate_bidx(@current_person.email, key: Lockbox.master_key)
          PersonIdentity.create(
            person_id: @current_person.id, provider: 'email',
            provider_subject: email_bidx,
            email: @current_person.email,
            password_digest: BCrypt::Password.create(password, cost: 12)
          )
        end
        flash['notice'] = 'Password saved'
        r.redirect '/profile/providers'
      end
    end

    r.is 'delete-account' do
      r.post do
        if TeamMembership.where(person_id: @current_person.id, left_at: nil).any?
          flash['error'] = 'You must leave all teams before deleting your account.'
          next r.redirect('/profile/edit')
        end

        DeletePerson.call(person: @current_person)
        regenerate_session
        flash['notice'] = 'Your account has been deleted.'
        r.redirect '/login'
      end
    end

    r.is 'edit' do
      r.get do
        @person = @current_person
        @can_delete_account = TeamMembership.where(person_id: @current_person.id, left_at: nil).empty?
        @page_title = 'Profile - Mainline'
        view 'profile/edit'
      end

      r.post do
        @person = @current_person
        name = typecast_params.nonempty_str('name')

        @errors = []
        @errors << 'Name is required' unless name
        @errors << 'Name must be 100 characters or fewer' if name && name.length > 100

        next view('profile/edit') unless @errors.empty?

        DB.transaction do
          before = { name: @person.name }
          @person.update(name: name)
          @person.actor.update(name: name)
          team_ids = TeamMembership.where(person_id: @person.id, left_at: nil).select_map(:team_id)
          team_ids.each do |tid|
            SetTeamContext.call(tid)
            RecordEvent.call(
              actor_id:     @current_actor.id,
              entity:       @person,
              action:       'edited',
              before_state: before,
              after_state:  { name: name },
              team_id:      tid
            )
          end
        end

        flash['notice'] = 'Name updated'
        r.redirect '/profile/edit'
      end
    end

    r.on 'providers' do
      r.is do
        r.get do
          @identities = PersonIdentity.where(person_id: @current_person.id).all
          @magic_login = session['magic_login']
          view 'profile/providers'
        end
      end

      r.post 'connect', String do |connect_provider|
        next unless SignInProviders.enabled?(connect_provider)

        session['linking_provider'] = true
        token = session['csrf'] ||= SecureRandom.base64(32)
        response.status = 200
        response.write <<~HTML
          <html><body>
            <form id="f" method="post" action="/auth/#{Rack::Utils.escape_html(connect_provider)}">
              <input type="hidden" name="authenticity_token" value="#{token}">
            </form>
            <script nonce="#{@csp_nonce}">document.getElementById('f').submit()</script>
          </body></html>
        HTML
        request.halt
      end

      r.on String do |identity_id|
        next unless identity_id.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)

        r.post 'disconnect' do
          identity = PersonIdentity[identity_id]
          next r.redirect('/profile/providers') unless identity&.person_id == @current_person.id

          count = PersonIdentity.where(person_id: @current_person.id).count
          if count <= 1
            flash['error'] = 'Cannot disconnect your only login provider'
            next r.redirect('/profile/providers')
          end

          identity.destroy
          flash['notice'] = "Disconnected #{PROVIDER_LABELS[identity.provider] || identity.provider}"
          r.redirect '/profile/providers'
        end
      end
    end
  end
end
