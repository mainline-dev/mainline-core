# frozen_string_literal: true

# The environment variables the app needs before it may start, each with
# what it is for.
module EnvRequirements
  CORE = {
    'MAINLINE_DATABASE_URL'               => 'Postgres URL for the database owner, used only to run migrations',
    'MAINLINE_APP_DATABASE_URL'           => 'Postgres URL for the mainline_app role the app connects as (row-level security applies)',
    'MAINLINE_SESSION_SECRET'             => 'Session cookie secret, at least 64 random characters (openssl rand -hex 32)',
    'LOCKBOX_MASTER_KEY'                  => '64 hex characters used to encrypt email addresses at rest (openssl rand -hex 32)',
    'SMTP_HOST'                           => 'Mail server host name',
    'SMTP_PORT'                           => 'Mail server port, usually 587',
    'SMTP_USERNAME'                       => 'Mail server user name',
    'SMTP_PASSWORD'                       => 'Mail server password',
    'SMTP_TLS'                            => 'starttls (port 587) or tls (encrypted from the start, port 465)',
    'MAIL_FROM'                           => 'Sender for all email, for example Mainline <noreply@example.org>',
    'GOOGLE_CLIENT_ID'                    => 'Google sign-in client ID; disabled leaves Google sign-in out',
    'GOOGLE_CLIENT_SECRET'                => 'Google sign-in client secret',
    'GH_OAUTH_CLIENT_ID'                  => 'GitHub sign-in client ID; disabled leaves GitHub sign-in out',
    'GH_OAUTH_CLIENT_SECRET'              => 'GitHub sign-in client secret',
    'GITLAB_CLIENT_ID'                    => 'GitLab sign-in client ID; disabled leaves GitLab sign-in out',
    'GITLAB_CLIENT_SECRET'                => 'GitLab sign-in client secret',
    'BASE_URL'                            => 'Public URL of the app, for example https://mainline.example.org',
    'MAINLINE_HOST'                       => 'Host name of the app, for example mainline.example.org',
    'REDIS_URL'                           => 'Redis URL for the job queue, for example redis://redis:6379/0',
    'SENTRY_DSN'                          => 'Sentry DSN for error reports; a plain word such as disabled turns sending off',
    'SENTRY_ENVIRONMENT'                  => 'Label on error reports, for example production',
    'CI_MONITOR_GITHUB_APP_ID'            => 'CI Monitor GitHub App ID',
    'CI_MONITOR_GITHUB_APP_SLUG'          => 'CI Monitor GitHub App URL name, used for the install link',
    'CI_MONITOR_GITHUB_APP_CLIENT_ID'     => 'CI Monitor GitHub App client ID',
    'CI_MONITOR_GITHUB_APP_CLIENT_SECRET' => 'CI Monitor GitHub App client secret',
    'CI_MONITOR_GITHUB_PRIVATE_KEY'       => 'CI Monitor GitHub App private key (PEM)',
    'CI_MONITOR_GITHUB_WEBHOOK_SECRET'    => 'CI Monitor GitHub App webhook signing secret'
  }.freeze

  @added = {}

  # Variables a deployment adds on top of the core list.
  def self.add(vars)
    @added.merge!(vars)
  end

  def self.required
    CORE.merge(@added)
  end

  def self.missing(env)
    required.keys.select { |var| env.fetch(var, nil).to_s.empty? }
  end

  # One line per missing variable: its name and what it is for.
  def self.missing_report(env)
    missing = missing(env)
    width = missing.map(&:length).max
    missing.map { |var| "#{var.ljust(width)}  #{required[var]}" }
  end
end
