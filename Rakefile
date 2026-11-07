# frozen_string_literal: true

# Migrate

# Migrations connect as the database owner. The child process itself hands
# the owner URL to db.rb under the app URL's name, so the URL (and its
# password) is never part of rake's command line or its "Command failed"
# message. verbose: false keeps the script out of the logs.
as_owner = lambda do |env, script|
  owner_var, app_var = if env == 'test'
                         %w[TEST_DATABASE_URL TEST_APP_DATABASE_URL]
                       else
                         %w[MAINLINE_DATABASE_URL MAINLINE_APP_DATABASE_URL]
                       end
  sh({ 'RACK_ENV' => env }, FileUtils::RUBY, '-e', <<~RUBY, verbose: false)
    owner_url = ENV.fetch(#{owner_var.inspect}, '')
    abort 'FATAL: required environment variable #{owner_var} is missing or empty' if owner_url.empty?
    ENV[#{app_var.inspect}] = owner_url
    require './db'
    #{script}
  RUBY
end

migrate = lambda do |env, version|
  as_owner.call(env, <<~RUBY)
    require 'logger'
    Sequel.extension :migration
    DB.loggers << Logger.new($stdout) if DB.loggers.empty?
    Sequel::Migrator.apply(DB, 'migrate', #{version.inspect})
  RUBY
end

desc 'Migrate test database to latest version'
task :test_up do
  migrate.call('test', nil)
end

desc 'Migrate test database all the way down'
task :test_down do
  migrate.call('test', 0)
end

desc 'Migrate test database all the way down and then back up'
task :test_bounce do
  migrate.call('test', 0)
  migrate.call('test', nil)
end

desc 'Migrate development database to latest version'
task :dev_up do
  migrate.call('development', nil)
end

desc 'Migrate development database to all the way down'
task :dev_down do
  migrate.call('development', 0)
end

desc 'Drop and recreate development database schema'
task :dev_bounce do
  as_owner.call('development', 'DB.tables.each { |t| DB.drop_table(t, cascade: true) }')
  migrate.call('development', nil)
end

desc 'List required environment variables that are missing or empty'
task 'env:missing' do
  require_relative 'lib/env_requirements'
  lines = EnvRequirements.missing_report(ENV)
  puts lines
  abort "#{lines.size} required environment variable(s) missing" unless lines.empty?
  puts 'All required environment variables are set'
end

desc 'Migrate production database to latest version'
task :prod_up do
  require_relative 'lib/env_check'
  migrate.call('production', nil)
end

# Shell

irb = proc do |env|
  trap('INT', 'IGNORE')
  dir, base = File.split(FileUtils::RUBY)
  cmd = if base.sub!(/\Aruby/, 'irb')
          [File.join(dir, base)]
        else
          [FileUtils::RUBY, '-S', 'irb']
        end
  cmd.unshift({ 'RACK_ENV' => env })
  cmd << '-r' << './models'
  sh(*cmd)
end

desc 'Open irb shell in test mode'
task :test_irb do
  irb.call('test')
end

desc 'Open irb shell in development mode'
task :dev_irb do
  irb.call('development')
end

desc 'Open irb shell in production mode'
task :prod_irb do
  irb.call('production')
end

# Tests

warn_flags = "-w #{'-W:strict_unused_block' if RUBY_VERSION >= '3.4'}"

desc 'Run model and lib tests'
task :test_models do
  files = Dir['test/models/test_*.rb'] + Dir['test/lib/test_*.rb']
  sh "#{FileUtils::RUBY} #{warn_flags} -e 'ARGV.each{|f| require_relative f}' #{files.join(' ')}"
end

desc 'Run acceptance tests'
task :test_acceptance do
  files = Dir['test/acceptance/test_*.rb']
  sh "#{FileUtils::RUBY} #{warn_flags} -e 'ARGV.each{|f| require_relative f}' #{files.join(' ')}"
end

desc 'Run browser tests (requires Chrome, local only)'
task :test_browser do
  files = Dir['test/browser/test_*.rb']
  sh "#{FileUtils::RUBY} #{warn_flags} -e 'ARGV.each{|f| require_relative f}' #{files.join(' ')}"
end

desc 'Run model and lib tests with coverage'
task :test_models_cov do
  files = Dir['test/models/test_*.rb'] + Dir['test/lib/test_*.rb']
  sh({ 'COVERAGE' => 'models', 'RODA_RENDER_COMPILED_METHOD_SUPPORT' => 'no' },
    FileUtils::RUBY, '-e', 'ARGV.each{|f| require_relative f}', *files)
end

desc 'Run acceptance tests with coverage'
task :test_acceptance_cov do
  sh({ 'COVERAGE' => 'acceptance', 'RODA_RENDER_COMPILED_METHOD_SUPPORT' => 'no' },
    FileUtils::RUBY, '-e', 'ARGV.each{|f| require_relative f}', *Dir['test/acceptance/test_*.rb'])
end

desc 'Run all tests'
task default: [:lint, :test_models, :test_acceptance]

desc 'Run all tests with coverage'
task :test_cov do
  FileUtils.rm_r('coverage') if File.directory?('coverage')
  Dir.mkdir('coverage')
  Rake::Task['_test_cov'].invoke
end
task _test_cov: [:test_models_cov, :test_acceptance_cov]

# Mutation testing

mutant_lib = %w[
  AssignPerson BusinessDays BypassRLS
  CumulativeFlow DataExport DeleteTeam EncryptedEmail EnsembleTimeline
  EventPresenter FlashAdapter Inventory LeadTime MapGrid PairingMatrix
  RateLimiter RecordEvent ReorderActivities ReorderStories
  ReorderTasks ResourceCap RevokeOauthToken SetTeamContext SoloLog
  SplitCandidate ThroughputScatter
]
MUTANT_LIB = mutant_lib.freeze

MUTANT_MODELS = %w[
  ActivityPersona Activity Actor Event Invitation Map PersonIdentity Person
  Persona ReleaseSlice Scenario StoryAssignment Story Task TeamConstraint
  TeamMembership Team
].freeze

desc 'Run mutant on all lib and model code'
task :mutant do
  subjects = (MUTANT_LIB + MUTANT_MODELS).map { |s| "'#{s}*'" }.join(' ')
  sh "bundle exec mutant run #{subjects}"
end

desc 'Run mutant on a single class (usage: rake "mutant_one[BypassRLS]")'
task :mutant_one, [:subject] do |_t, args|
  abort 'Usage: rake "mutant_one[ClassName]"' unless args[:subject]
  sh "bundle exec mutant run '#{args[:subject]}*'"
end

desc 'Run mutant on RLS code (BypassRLS, SetTeamContext, PinConnection)'
task :mutant_rls do
  sh "bundle exec mutant run 'BypassRLS*' 'SetTeamContext*' 'PinConnection*'"
end

# Lint

desc 'Run RuboCop'
task :lint do
  sh 'bundle exec rubocop'
end

# Seed

desc 'Seed development database with sample team history'
task :dev_seed do
  sh({ 'RACK_ENV' => 'development' }, FileUtils::RUBY, '-r', './test_data/dev_seed', '-e', 'DevSeed.call')
end

desc 'Seed a compact team for map screenshots'
task :screenshot_seed do
  sh({ 'RACK_ENV' => 'development' }, FileUtils::RUBY, '-r', './test_data/screenshot_seed', '-e', 'ScreenshotSeed.call')
end

desc 'Remove seed data from development database'
task :dev_teardown do
  sh({ 'RACK_ENV' => 'development' }, FileUtils::RUBY, '-r', './test_data/dev_teardown', '-e', 'DevTeardown.call')
end

# Other

desc 'Send MCP announcement to all verified users (DRY_RUN=1 to preview)'
task :announce_mcp do
  sh({ 'RACK_ENV' => 'production' }, FileUtils::RUBY, '-r', './models',
    '-r', './lib/send_announcement_email', '-e', <<~RUBY)
      dry = ENV['DRY_RUN'] == '1'
      people = Person.where(Sequel.~(email_verified_at: nil)).all
      puts "\#{people.size} verified users"
      people.each do |p|
        email = p.email
        if dry
          puts "  [dry-run] would send to \#{email}"
        else
          result = SendAnnouncementEmail.call(to: email)
          status = result == :failed ? 'FAILED' : 'sent'
          puts "  \#{status}: \#{email}"
          sleep 0.2
        end
      end
      puts dry ? 'Dry run complete. Run without DRY_RUN=1 to send.' : 'Done.'
    RUBY
end

desc 'Export team data as JSON (usage: rake "export[TEAM_ID]")'
task :export, [:team_id] do |_t, args|
  abort 'Usage: rake "export[TEAM_ID]"' unless args[:team_id]
  sh({ 'RACK_ENV' => 'production' }, FileUtils::RUBY, '-r', './db', '-r', './models',
    '-r', './lib/data_export', '-e', "puts DataExport.to_json(team_id: '#{args[:team_id]}')")
end

desc 'Annotate Sequel models'
task 'annotate' do
  sh({ 'RACK_ENV' => 'test' }, FileUtils::RUBY, '-r', './models', '-r', 'sequel/annotate', '-e', <<~RUBY)
    DB.loggers.clear
    Sequel::Annotate.annotate(Dir['models/**/*.rb'])
  RUBY
end
