# frozen_string_literal: true

require 'bcrypt'
require 'net/http'
require 'json'
require_relative 'models'
require_relative 'lib/record_event'
require_relative 'lib/rebalance_positions'
require_relative 'lib/reorder_stories'
require_relative 'lib/reorder_tasks'
require_relative 'lib/move_activity'
require_relative 'lib/reorder_activities'
require_relative 'lib/split_candidate'
require_relative 'lib/split_story'
require_relative 'lib/create_task'
require_relative 'lib/create_story'
require_relative 'lib/edit_task'
require_relative 'lib/create_activity'
require_relative 'lib/create_map'
require_relative 'lib/edit_activity'
require_relative 'lib/create_persona'
require_relative 'lib/edit_persona'
require_relative 'lib/archive_persona'
require_relative 'lib/map_access'
require_relative 'lib/create_personal_token'
require_relative 'lib/personal_tokens'
require_relative 'lib/revoke_grant'
require_relative 'lib/map_grid'
require_relative 'lib/pairing_matrix'
require_relative 'lib/ensemble_timeline'
require_relative 'lib/solo_log'
require_relative 'lib/two_person_rule'
require_relative 'lib/record_walkthrough'
require_relative 'lib/walkthroughs'
require_relative 'lib/kickoff'
require_relative 'lib/business_days'
require_relative 'lib/inventory'
require_relative 'lib/jira_csv'
require_relative 'lib/jira_markup'
require_relative 'lib/add_scenario'
require_relative 'lib/accept_invite'
require_relative 'lib/archive_story'
require_relative 'lib/deploy_story'
require_relative 'lib/email_login'
require_relative 'lib/email_signup'
require_relative 'lib/release_story'
require_relative 'lib/remove_scenario'
require_relative 'lib/mark_scenario'
require_relative 'lib/edit_scenario'
require_relative 'lib/edit_story'
require_relative 'lib/unassign_person'
require_relative 'lib/unpromote_museum_item'
require_relative 'lib/import_to_museum'
require_relative 'lib/museum_list'
require_relative 'lib/promote_museum_item'
require_relative 'lib/discard_museum_item'
require_relative 'lib/let_go_review'
require_relative 'lib/let_go_prompt'
require_relative 'lib/add_to_story'
require_relative 'lib/story_id'
require_relative 'lib/story_picker'
require_relative 'lib/jobs/let_go_job'
require_relative 'lib/cloudflare_client_ip'
require_relative 'lib/request_size_limit'
require_relative 'lib/shared_rate_limiter'
require_relative 'lib/email_verification'
require_relative 'lib/feature_file'
require_relative 'lib/release_notes'
require_relative 'lib/never_pulled'
require_relative 'lib/first_run'
require_relative 'lib/activation'
require_relative 'lib/agent_reads'
require_relative 'lib/start_urgent_story'
require_relative 'lib/release_block'
require_relative 'lib/ci_monitor_setup'
require_relative 'lib/github_install'
require_relative 'lib/step_stubs'
require_relative 'lib/signup_timer'
require_relative 'lib/event_presenter'
require_relative 'lib/cumulative_flow'
require_relative 'lib/csrf_check'
require_relative 'lib/throughput_scatter'
require_relative 'lib/lead_time'
require_relative 'lib/send_invite_email'
require_relative 'lib/send_magic_login_email'
require_relative 'lib/invite_token'
require_relative 'lib/send_verification_email'
require_relative 'lib/assign_person'
require_relative 'lib/data_export'
require_relative 'lib/team_export'
require_relative 'lib/delete_team'
require_relative 'lib/delete_person'
require_relative 'lib/resource_cap'
require_relative 'lib/revoke_oauth_token'
require_relative 'lib/set_team_context'
require_relative 'lib/signed_state'
require_relative 'lib/bypass_rls'
require_relative 'lib/core_events'
require_relative 'lib/ci_monitor'
require_relative 'lib/rate_limiter'
require_relative 'lib/login_link_throttle'
require_relative 'lib/mcp_actor'
require_relative 'lib/oauth_setting'
require_relative 'lib/mcp_sign_in'
require_relative 'lib/mcp_access'
require_relative 'lib/oauth_request'
require_relative 'lib/sign_in_grant'
require_relative 'lib/oauth_tokens'
require_relative 'lib/oauth_revocation'
require_relative 'lib/oauth_metadata'
require_relative 'lib/sign_in_providers'
require_relative 'lib/signups'
require_relative 'lib/mcp_server'
require_relative 'lib/flash_adapter'
require_relative 'lib/request_logger'

require 'roda'
require 'rack/session'
require 'omniauth'
require 'omniauth-google-oauth2'
require 'omniauth-github'
require 'omniauth-gitlab'

require 'tilt'
require 'tilt/erubi'
require 'sentry-ruby'
require 'sidekiq'

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch('REDIS_URL') }
end

Sentry.init do |config|
  config.dsn = ENV.fetch('SENTRY_DSN')
  config.environment = ENV.fetch('SENTRY_ENVIRONMENT')
  config.traces_sample_rate = 0
end

OmniAuth.config.allowed_request_methods = [:post]

# Sign-in, MCP and deploy limits are shared through Redis, so every worker and
# instance counts together.
AUTH_RATE_LIMITER = SharedRateLimiter.new(name: 'auth', capacity: 10, refill_rate: 10.0 / 3600)

# Museum uploads per team: a person acquires a few files in a sitting, not hundreds.
MUSEUM_UPLOAD_RATE_LIMITER = RateLimiter.new(capacity: 20, refill_rate: 20.0 / 3600)
# Exports per team: building the zip reads everything the team has.
TEAM_EXPORT_RATE_LIMITER = RateLimiter.new(capacity: 10, refill_rate: 10.0 / 3600)
LOGIN_GLOBAL_LIMITER = SharedRateLimiter.new(name: 'login_global', capacity: 60, refill_rate: 1.0)
LOGIN_EMAIL_LIMITER = SharedRateLimiter.new(name: 'login_email', capacity: 5, refill_rate: 5.0 / 900)
# /mcp counts a token Mainline issued against its grant, live or not, and a
# token matching nothing against the address it came from.
MCP_GRANT_LIMITER = SharedRateLimiter.new(name: 'mcp_grant', capacity: 120, refill_rate: 120.0 / 60)
MCP_UNKNOWN_TOKEN_LIMITER = SharedRateLimiter.new(name: 'mcp_unknown_token', capacity: 600, refill_rate: 600.0 / 3600)
DEPLOY_AUTH_RATE_LIMITER = SharedRateLimiter.new(name: 'deploy_auth', capacity: 10, refill_rate: 0.05)

class Mainline < Roda
  PROVIDER_LABELS = {
    'google_oauth2' => 'Google',
    'github'        => 'GitHub',
    'gitlab'        => 'GitLab',
    'email'         => 'Email'
  }.freeze

  opts[:check_dynamic_arity] = false
  opts[:check_arity] = :warn

  use RequestSizeLimit
  use CloudflareClientIp
  use Rack::Session::Cookie,
    key:       '_Mainline.sid',
    secret:    ENV.fetch('MAINLINE_SESSION_SECRET'),
    same_site: :lax,
    secure:    ENV['RACK_ENV'] == 'production',
    httponly:  true
  use OmniAuth::Builder do
    provider :google_oauth2, ENV.fetch('GOOGLE_CLIENT_ID'), ENV.fetch('GOOGLE_CLIENT_SECRET') if SignInProviders.enabled?('google_oauth2')
    if SignInProviders.enabled?('github')
      provider :github, ENV.fetch('GH_OAUTH_CLIENT_ID'), ENV.fetch('GH_OAUTH_CLIENT_SECRET'), scope: 'user:email'
    end
    if SignInProviders.enabled?('gitlab')
      provider :gitlab, ENV.fetch('GITLAB_CLIENT_ID'), ENV.fetch('GITLAB_CLIENT_SECRET'), scope: 'read_user'
    end
  end

  plugin :default_headers,
    'Content-Type'              => 'text/html',
    'Strict-Transport-Security' => 'max-age=63072000; includeSubDomains',
    'X-Frame-Options'           => 'deny',
    'X-Content-Type-Options'    => 'nosniff'

  plugin :content_security_policy do |csp|
    csp.default_src :none
    csp.style_src :self, :unsafe_inline, 'https://cdn.jsdelivr.net', 'https://fonts.googleapis.com'
    csp.font_src :self, 'https://fonts.gstatic.com'
    csp.form_action :self, 'https://accounts.google.com', 'https://github.com', 'https://gitlab.com'
    csp.script_src :self
    csp.connect_src :self
    csp.img_src :self, 'data:'
    csp.base_uri :none
    csp.frame_ancestors :none
  end

  # :nocov:
  plugin :render_coverage if defined?(SimpleCov)
  # :nocov:

  plugin :halt
  plugin :head
  plugin :route_csrf, check_header: true, require_request_specific_tokens: false
  plugin :flash
  plugin :assets, css: 'app.css', timestamp_paths: true
  plugin :render,
    escape: true, layout: './layout', assume_fixed_locals: true,
    allowed_paths: ['views'],
    template_opts: {
      chain_appends: !defined?(SimpleCov), freeze: true,
      skip_compiled_encoding_detection: true, scope_class: self,
      default_fixed_locals: '()', extract_fixed_locals: true
    }
  plugin :public, headers: { 'Cache-Control' => 'public, max-age=604800' }
  plugin :Integer_matcher_max
  plugin :typecast_params_sized_integers, sizes: [64], default_size: 64
  plugin :hash_branch_view_subdir

  use RequestLogger, $stderr unless ENV['RACK_ENV'] == 'test'

  plugin :not_found do
    @page_title = 'Page not found'
    view(content: '<p>The page you requested does not exist.</p>')
  end

  if ENV['RACK_ENV'] == 'development'
    plugin :exception_page
    class RodaRequest
      def assets
        exception_page_assets
        super
      end
    end
  else
    def self.freeze
      Sequel::Model.freeze_descendents
      DB.freeze
      super
    end
  end

  plugin :error_handler do |e|
    case e
    when Rack::Multipart::EmptyContentError
      response.status = 400
      next 'Bad Request'
    when Roda::RodaPlugins::RouteCsrf::InvalidToken
      path = request.path_info
      if path.start_with?('/magic-login/')
        flash['error'] = 'This login link has expired. Please request a new one.'
        next redirect('/forgot-password')
      elsif path.start_with?('/verify-email/')
        flash['error'] = 'This verification link has expired. Please request a new one.'
        next redirect('/login')
      end
      @page_title = 'Invalid Security Token'
      response.status = 400
      view(content: '<p>An invalid security token was submitted with this request, and this request could not be processed.</p>')
    else
      Sentry.capture_exception(e) if Sentry.initialized?
      $stderr.print "#{e.class}: #{e.message}\n"
      warn e.backtrace
      next exception_page(e, assets: true) if ENV['RACK_ENV'] == 'development'

      @page_title = 'Internal Server Error'
      view(content: '<p>Something went wrong. Please try again or contact support.</p>')
    end
  end

  if Unreloader.autoload?
    plugin :autoload_hash_branches
    autoload_hash_branch_dir('./routes')
    autoload_hash_branch_dir('maps', './routes/maps')
    autoload_hash_branch_dir('maps/stories', './routes/maps/stories')
    autoload_hash_branch_dir('teams', './routes/teams')
    autoload_hash_branch_dir('webhooks', './routes/webhooks')
  end
  Unreloader.autoload('routes', delete_hook: proc {|f| hash_branch(File.basename(f).delete_suffix('.rb'))}) {}
  Unreloader.autoload('routes/maps', delete_hook: proc {|f| hash_branch('maps', File.basename(f).delete_suffix('.rb'))}) {}
  Unreloader.autoload('routes/maps/stories', delete_hook: proc {|f| hash_branch('maps/stories', File.basename(f).delete_suffix('.rb'))}) {}
  Unreloader.autoload('routes/teams', delete_hook: proc {|f| hash_branch('teams', File.basename(f).delete_suffix('.rb'))}) {}
  Unreloader.autoload('routes/webhooks', delete_hook: proc {|f| hash_branch('webhooks', File.basename(f).delete_suffix('.rb'))}) {}

  def self.seeding?
    ENV['RACK_ENV'] == 'development' && ENV.fetch('MAINLINE_SEED', nil)
  end

  class << self
    attr_accessor :seed_person_id
  end

  public_prefixes = %w[
    /login /signup /auth/ /api/ /mcp/ /oauth/ /invite/ /webhooks/ /.well-known/
    /forgot-password /magic-login/ /verify-email/ /confirm-email
  ]
  PUBLIC_PREFIXES = public_prefixes.freeze

  public_exact = %w[/robots.txt /mcp]
  PUBLIC_EXACT = public_exact.freeze

  def self.public_path?(path, _method)
    path == '/' || PUBLIC_EXACT.include?(path) || PUBLIC_PREFIXES.any? { |p| path.start_with?(p) }
  end

  route do |r| # rubocop:disable Metrics/BlockLength
    r.public
    r.assets

    path = r.path_info
    r.redirect(path.chomp('/'), 301) if path.length > 1 && path.end_with?('/')

    check_csrf! if CsrfCheck.on? && !self.class.seeding? && !CsrfCheck.skips?(r.path_info)

    @csp_nonce = SecureRandom.hex(16)
    content_security_policy.script_src :self, [:nonce, @csp_nonce]
    content_security_policy.connect_src :self

    if %w[test development].include?(ENV.fetch('RACK_ENV', nil)) || self.class.seeding?
      r.is '_test_login' do
        if self.class.seeding?
          self.class.seed_person_id = r.params['person_id']
        else
          person_id = r.params['person_id']
          session['person_id'] = person_id
          membership = TeamMembership.where(person_id: person_id, left_at: nil).first
          session['team_id'] = membership.team_id if membership
          session['oauth_provider'] = r.params['oauth_provider'] if r.params['oauth_provider']
          session['oauth_token'] = r.params['oauth_token'] if r.params['oauth_token']
          if r.params['ci_monitor_token']
            session['ci_monitor_token'] = r.params['ci_monitor_token']
            session['ci_monitor_token_at'] = (r.params['ci_monitor_token_at'] || Time.now.to_i).to_i
          end
          # A trial's login link names a page on this site to go on to.
          to = r.params['to'].to_s
          r.redirect(to) if to.match?(%r{\A/(?![/\\])})
        end
        'ok'
      end
    end

    r.is 'up' do
      response.status = 200
      response['Content-Type'] = 'text/plain'
      next 'OK'
    end

    # The address coding agents connect to. A request with no token is asked
    # to sign in, before any database work (McpSignIn); one with a token is
    # checked in routes/mcp.rb.
    unless McpSignIn.token?(r.env)
      r.is 'mcp' do
        response.status = 401
        response['WWW-Authenticate'] = McpSignIn.challenge
        response['Content-Type'] = 'text/plain'
        McpSignIn::BODY
      end
    end

    r.on '.well-known' do
      # The MCP server as a protected resource, at the address /mcp's request
      # to sign in links to and at the root of the well-known path; and this
      # install as the server that signs people in. Neither is there while
      # OAuth is off.
      if OauthSetting.on?
        r.get ['oauth-protected-resource/mcp', 'oauth-protected-resource'] do
          response['Content-Type'] = 'application/json'
          OAuthMetadata.protected_resource.to_json
        end

        r.get 'oauth-authorization-server' do
          response['Content-Type'] = 'application/json'
          OAuthMetadata.authorization_server.to_json
        end
      end

      r.get 'mcp.json' do
        response['Content-Type'] = 'application/json'
        server = {
          url:            "#{ENV.fetch('BASE_URL')}/mcp",
          description:    'Use a personal token from Profile, then Coding agents',
          authentication: { type: 'bearer' }
        }
        { mcpServers: { mainline: server } }.to_json
      end
    end

    r.root { r.redirect(session['person_id'] ? '/teams' : '/login') }

    r.is 'signup' do
      r.get do
        next view('signups_closed', layout: false) unless Signups.available?(invite_token: session['invite_token'])

        session['signup_plan'] = r.params['plan'] if r.params['plan']
        @authenticity_token = session['csrf'] ||= SecureRandom.base64(32)
        @form_started = SignupTimer.token
        view 'signup', layout: false
      end

      r.post do
        unless AUTH_RATE_LIMITER.allow?(request.ip)
          flash['error'] = 'Too many requests. Try again later.'
          next r.redirect('/signup')
        end
        turn_away_bot_signup(r)

        result = handle_email_signup(r.params)
        if result[:error]
          flash['error'] = result[:error]
          next r.redirect('/signup')
        end
        regenerate_session(preserve_keys: ['signup_plan'])
        session['person_id'] = result[:person].id
        flash['notice'] = "Signed in as #{result[:person].name}."
        has_team = TeamMembership.where(person_id: result[:person].id, left_at: nil).any?
        r.redirect(has_team ? '/teams' : '/teams/new')
      end
    end

    r.is 'login' do
      r.get do
        session['signup_plan'] = r.params['plan'] if r.params['plan']
        @authenticity_token = session['csrf'] ||= SecureRandom.base64(32)
        view 'login', layout: false
      end

      r.post do
        blocked = check_login_rate_limits(r)
        next blocked if blocked

        person = EmailLogin.person(email: r.params['email'], password: r.params['password'])
        if person
          accept_invite(person, r.params['email'].to_s.strip.downcase, session)
          regenerate_session(preserve_keys: %w[signup_plan oauth_return])
          session['person_id'] = person.id
          flash['notice'] = "Signed in as #{person.name}"
          has_team = TeamMembership.where(person_id: person.id, left_at: nil).any?
          r.redirect(after_sign_in(has_team))
        else
          flash['error'] = 'Invalid email or password'
          r.redirect '/login'
        end
      end
    end

    r.is 'forgot-password' do
      r.get do
        view 'forgot_password', layout: false
      end

      r.post do
        unless AUTH_RATE_LIMITER.allow?(request.ip)
          flash['error'] = 'Too many requests. Try again later.'
          next r.redirect('/forgot-password')
        end
        email = r.params['email'].to_s.strip.downcase
        person = Person.find_by_email(email) unless email.empty?
        result = nil
        if person && LoginLinkThrottle.allow?(email)
          token = SignedState.generate("magic:#{person.id}")
          result = SendMagicLoginEmail.call(person: person, token: token)
        end
        if result == :failed
          flash['error'] = 'Could not send the email. Please try again.'
        else
          flash['notice'] = 'If that email is registered, you will receive a login link shortly.'
        end
        r.redirect '/forgot-password'
      end
    end

    r.on 'magic-login' do
      r.on String do |token|
        r.get do
          next magic_login_failed(r) unless EmailLogin.person_for_link(token)

          @magic_token = token
          view 'magic_login_confirm', layout: false
        end

        r.post do
          person = EmailLogin.use_link(token)
          next magic_login_failed(r) unless person

          regenerate_session(preserve_keys: ['signup_plan'])
          session['person_id'] = person.id
          session['magic_login'] = true
          flash['notice'] = "Signed in as #{person.name}"
          r.redirect '/profile/providers'
        end
      end
    end

    r.on 'confirm-email' do
      pending = session['pending_signup']
      next r.redirect('/login') unless pending

      r.get do
        load_confirm_email(pending)
        view 'confirm_email', layout: false
      end

      r.post do
        email = r.params['email'].to_s.strip.downcase
        if email.empty? || !email.match?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
          flash['error'] = 'Please enter a valid email address.'
          next r.redirect('/confirm-email')
        end
        if Person.find_by_email(email)
          flash['error'] = 'An account with that email already exists. ' \
                           'Sign in with your original provider and link this one from Connected Accounts.'
          next r.redirect('/login')
        end
        pending['email'] = email
        session['pending_signup'] = pending
        result = generate_oauth_verify_token(pending)
        session['oauth_verify_link'] = result unless result == :failed
        flash['notice'] = 'Verification email sent. Check your inbox.' unless result == :failed
        r.redirect '/confirm-email'
      end
    end

    r.on 'verify-email' do
      r.on String do |token|
        r.get { handle_verify_email_get(r, token) }
        r.post { handle_verify_email_post(r, token) }
      end
    end

    r.post 'resend-verification' do
      person = session['person_id'] && Person[session['person_id']]
      if person && person.email_verified_at.nil? && AUTH_RATE_LIMITER.allow?(request.ip)
        token = SignedState.generate("verify:#{person.id}")
        result = SendVerificationEmail.call(person: person, token: token)
        if result == :failed
          flash['error'] = 'Could not send the verification email. Please try again.'
        else
          flash['notice'] = result.is_a?(String) ? 'New verification link ready.' : 'Verification email sent. Check your inbox.'
        end
      end
      r.redirect '/teams'
    end

    r.post 'logout' do
      RevokeOauthToken.call(session['oauth_provider'], session['oauth_token'])
      session.clear
      r.redirect '/'
    end

    r.on 'invite' do
      r.get String do |token|
        invitation = Invitation.pending(token)
        next view('invite_expired', layout: false) unless invitation

        @team = Team[invitation.team_id]
        @inviter = Person[invitation.invited_by]
        session['invite_token'] = token
        @authenticity_token = session['csrf'] ||= SecureRandom.base64(32)
        view 'invite', layout: false
      end
    end

    DB.transaction do
      authenticate!(r)
      DB.run("SELECT set_config('app.current_team_id', '', true), set_config('app.rls_bypass', 'false', true)")

      if ENV['RACK_ENV'] != 'production'
        r.get 'styleguide' do
          view 'styleguide'
        end
      end

      r.hash_branches('')
    end
  end

  def authenticate!(req)
    return if self.class.public_path?(req.path_info, req.request_method)

    if self.class.seeding?
      person_id = self.class.seed_person_id
      @current_person = person_id ? Person[person_id] : Person.first
      @current_actor = @current_person&.actor
      membership = TeamMembership.where(person_id: @current_person.id, left_at: nil).first
      @current_team = membership ? Team[membership.team_id] : nil
      return
    end

    @current_person = load_current_person(req)
    @current_actor = @current_person.actor
    @current_team = load_current_team
    @is_creator = @current_team&.creator_id == @current_person.id
    @team_count = TeamMembership.where(person_id: @current_person.id, left_at: nil).count
  end

  # A filled-in hidden website field, or a form sent back faster than anyone
  # could type, is a bot: back to the form, with no account and no email. A
  # form left open for over a day is asked for again.
  def turn_away_bot_signup(req)
    timer = SignupTimer.check(req.params['form_started'])
    return if timer == :ok && req.params['website'].to_s.empty?

    flash['error'] = 'The signup form was open for over a day. Please fill it in again.' if timer == :expired
    req.redirect('/signup')
  end

  SIGNUPS_CLOSED = 'Sign-ups are closed. Ask someone on your team to send you an invitation.'

  def handle_email_signup(params)
    name     = params['name'].to_s.strip
    email    = params['email'].to_s.strip.downcase
    password = params['password'].to_s

    return { error: SIGNUPS_CLOSED } unless Signups.allowed?(email: email, invite_token: session['invite_token'])

    signup = EmailSignup.call(name: name, email: email, password: password)
    return { error: signup.error } if signup.error

    person = signup.person
    CoreEvents.publish(:person_signed_up, person_id: person.id, provider: 'email', session: session)
    result = EmailVerification.ask(person, now: Time.now)
    flash['error'] = 'Could not send the verification email. Please try again.' if result == :failed
    accept_invite(person, email, session)
    { person: person, verification: result }
  end

  def check_login_rate_limits(req)
    unless AUTH_RATE_LIMITER.allow?(request.ip)
      flash['error'] = 'Too many requests. Try again later.'
      return req.redirect('/login')
    end
    unless LOGIN_GLOBAL_LIMITER.allow?('global')
      flash['error'] = 'Our login system is busy right now. Please wait a moment and try again.'
      return req.redirect('/login')
    end
    email_raw = req.params['email'].to_s.strip.downcase
    email_key = email_raw.empty? ? nil : Digest::SHA256.hexdigest(email_raw)
    unless email_key.nil? || LOGIN_EMAIL_LIMITER.allow?(email_key)
      flash['error'] = 'Too many failed attempts for this email. Please wait and try again.'
      return req.redirect('/login')
    end
    nil
  end

  def magic_login_failed(req)
    flash['error'] = 'This login link has expired or is invalid.'
    req.redirect('/forgot-password')
  end

  def handle_verify_email_get(req, token)
    value = SignedState.verify(token)
    unless value&.start_with?('oauth-verify:') || EmailVerification.person_for(token)
      flash['error'] = 'This verification link has expired or is invalid.'
      return req.redirect('/login')
    end
    @verify_token = token
    view 'verify_email_confirm', layout: false
  end

  def handle_verify_email_post(req, token)
    value = SignedState.verify(token)
    return handle_oauth_verify(req, value) if value&.start_with?('oauth-verify:')

    person = EmailVerification.person_for(token)
    unless person
      flash['error'] = 'This verification link has expired or is invalid.'
      return req.redirect('/login')
    end
    EmailVerification.confirm(person, now: Time.now)
    flash['notice'] = 'Email verified.'
    req.redirect session['person_id'] ? '/teams' : '/login'
  end

  def handle_oauth_verify(req, value)
    encoded = value.delete_prefix('oauth-verify:')
    pending = begin
      JSON.parse(Base64.urlsafe_decode64(encoded))
    rescue JSON::ParserError, ArgumentError
      nil
    end
    unless pending
      flash['error'] = 'This verification link has expired or is invalid.'
      return req.redirect('/login')
    end

    person = complete_oauth_signup(pending, pending['email'])
    return req.redirect('/login') unless person

    flash['notice'] = "Signed in as #{person.name}"
    has_team = TeamMembership.where(person_id: person.id, left_at: nil).any?
    req.redirect(has_team ? '/teams' : '/teams/new')
  end

  def load_confirm_email(pending)
    @pending_email = pending['email']
    if @pending_email && session['oauth_verify_link'].nil?
      result = generate_oauth_verify_token(pending)
      if result == :failed
        @send_failed = true
      else
        session['oauth_verify_link'] = result
      end
    end
    @verify_link = session['oauth_verify_link']
  end

  def generate_oauth_verify_token(pending)
    data = { 'name' => pending['name'], 'email' => pending['email'],
             'provider' => pending['provider'], 'uid' => pending['uid'] }
    encoded = Base64.urlsafe_encode64(JSON.generate(data), padding: false)
    token = SignedState.generate("oauth-verify:#{encoded}")
    SendVerificationEmail.call(person: Struct.new(:email).new(pending['email']), token: token)
  end

  def complete_oauth_signup(pending, email)
    if Person.find_by_email(email)
      clear_pending_signup
      flash['error'] = 'An account with that email already exists.'
      return nil
    end
    unless Signups.allowed?(email: email, invite_token: session['invite_token'])
      clear_pending_signup
      flash['error'] = SIGNUPS_CLOSED
      return nil
    end
    person = create_oauth_person(pending, email)
    clear_pending_signup
    CoreEvents.publish(:person_signed_up, person_id: person.id, provider: pending['provider'], session: session)
    accept_invite(person, email, session)
    establish_session(person, pending)
    person
  end

  def create_oauth_person(pending, email)
    DB.transaction {
      p = Person.create(name: pending['name'], email: email, email_verified_at: Time.now)
      PersonIdentity.create(
        person_id: p.id, provider: pending['provider'],
        provider_subject: pending['uid'], email: email
      )
      p
    }
  end

  def establish_session(person, pending)
    regenerate_session(preserve_keys: ['signup_plan'])
    session['person_id'] = person.id
    session['oauth_token'] = pending['oauth_token']
    session['oauth_provider'] = pending['provider']
  end

  def clear_pending_signup
    session.delete('pending_signup')
    session.delete('oauth_verify_link')
  end

  # Where someone goes once signed in: back to a coding agent's sign-in that
  # sent them, if one did, otherwise to their teams.
  def after_sign_in(has_team)
    back = session.delete('oauth_return').to_s
    return back if back.start_with?('/oauth/authorize?')

    has_team ? '/teams' : '/teams/new'
  end

  def regenerate_session(preserve_keys: [])
    saved = preserve_keys.to_h { |k| [k, session[k]] }
    session.clear
    saved.each { |k, v| session[k] = v unless v.nil? }
  end

  # Takes up the invitation the session holds, if it was sent to this address.
  def accept_invite(person, email, sess)
    invitation = AcceptInvite.invitation_for(token: sess.delete('invite_token'), email: email)
    return unless invitation

    AcceptInvite.join(invitation: invitation, person: person, now: Time.now)
  end

  # A suspended team the person holds the account for and still belongs to.
  def holds_suspended_team?
    Team.join(:team_memberships, team_id: :id)
      .where(Sequel[:team_memberships][:person_id] => @current_person.id, Sequel[:team_memberships][:left_at] => nil)
      .where(Sequel[:teams][:creator_id] => @current_person.id)
      .exclude(Sequel[:teams][:suspended_at] => nil)
      .any?
  end

  # The account holder sees the suspension's message and goes where it
  # points; everyone else goes back to their team list.
  def leave_suspended_team(req, team)
    flash['error'] = @is_creator ? team.suspended_message : "#{team.name} is no longer active. Contact the account holder."
    req.redirect(@is_creator ? team.suspension_destination : '/teams')
  end

  def htmx?(req)
    req.env['HTTP_HX_REQUEST']
  end

  def time_ago_label(time)
    return nil unless time

    days = (Date.today - time.to_date).to_i
    if days.zero?
      'today'
    elsif days == 1
      'yesterday'
    elsif days < 30
      "#{days}d ago"
    elsif days < 365
      "#{days / 30}mo ago"
    else
      "#{days / 365}y ago"
    end
  end

  def load_activity_history
    @activity_events = Event.where(map_id: @map.id, entity_type: 'activitie')
      .order(Sequel.desc(:event_no))
      .eager(:actor)
      .all
    personas = Persona.where(map_id: @map.id).as_hash(:id)
    @event_lookup = { people: {}, slices: {}, tasks: {}, personas: personas, activities: {} }
  end

  def person_locked?
    pref = DB[:map_view_prefs].where(
      person_id: @current_person.id, map_id: @map.id
    ).first
    pref ? pref[:locked] : false
  end

  # Extra tags for the head of public pages; core adds none.
  def public_head_tags
    head_tags = []
    head_tags.join
  end

  attr_reader :csp_nonce

  def og_tags
    t = Rack::Utils.escape_html(@og_title || @page_title ||
      'Mainline: open-source project management for continuous delivery teams')
    d = Rack::Utils.escape_html(@og_description ||
      'No backlog, no story points, no individual metrics. Built for teams that practise continuous delivery.')
    img = Rack::Utils.escape_html(@og_image || 'https://mainline.dev/og-image.png')
    url = Rack::Utils.escape_html("https://mainline.dev#{request.path_info}")
    type = Rack::Utils.escape_html(@og_type || 'website')
    <<~HTML
      <meta property="og:title" content="#{t}">
      <meta property="og:description" content="#{d}">
      <meta property="og:image" content="#{img}">
      <meta property="og:url" content="#{url}">
      <meta property="og:type" content="#{type}">
      <meta property="og:site_name" content="Mainline">
      <meta name="twitter:card" content="summary_large_image">
      <meta name="twitter:title" content="#{t}">
      <meta name="twitter:description" content="#{d}">
      <meta name="twitter:image" content="#{img}">
    HTML
  end

  # Signed in with an email address that has not been verified yet. People who
  # came in through a provider have nothing to verify.
  def email_unverified?
    @current_person && @current_person.email_verified_at.nil? &&
      PersonIdentity.where(person_id: @current_person.id, provider: 'email').any?
  end

  def load_current_team
    team_id = session['team_id']
    return unless team_id

    membership = TeamMembership.where(person_id: @current_person.id, team_id: team_id, left_at: nil).first
    membership ? Team[membership.team_id] : nil
  end

  def load_current_person(req)
    person_id = session['person_id']
    person = Person[person_id] if person_id
    return person if person

    session.delete('person_id')
    flash['notice'] = 'Please sign in'
    req.redirect '/login'
  end
end

require_relative 'lib/museum_routes'
require_relative 'lib/story_templates'
