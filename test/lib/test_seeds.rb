# frozen_string_literal: true

ENV['MT_NO_PLUGINS'] = '1'
gem 'minitest'
require 'minitest/global_expectations/autorun'
require 'sequel'
require_relative '../subprocess_helper'

# The seeds build the sample data people see first: the trial's teams on a
# self-hosted install's first start, and the teams to develop against. They
# speak the test DSL, so a rule the app gains, such as releasing a story only
# once its scenarios are done, can break them, and nothing else runs them.
# Each run gets an empty database of its own, migrated as a fresh install's
# is, and the database goes once the run is over.
describe 'The seeds' do
  # Named after this suite's own test database, so mainline's suite and the
  # core's, which share one database server, can run at the same time.
  def scratch
    "#{ENV.fetch('TEST_DATABASE_URL')[%r{/([^/?]+)\z}, 1]}_seeds"
  end

  # The test database's address, pointing at the scratch database instead.
  def url(var)
    ENV.fetch(var).sub(%r{/[^/]+\z}, "/#{scratch}")
  end

  def as_development
    { 'RACK_ENV' => 'development', 'MAINLINE_DATABASE_URL' => url('TEST_DATABASE_URL'),
      'MAINLINE_APP_DATABASE_URL' => url('TEST_APP_DATABASE_URL') }
  end

  def server(&)
    Sequel.connect(ENV.fetch('TEST_DATABASE_URL'), &)
  end

  def scratch_database
    Sequel.connect(url('TEST_DATABASE_URL')) do |db|
      db.run("SELECT set_config('app.rls_bypass', 'true', false)")
      yield db
    end
  end

  before do
    server do |db|
      db.run("DROP DATABASE IF EXISTS #{scratch}")
      db.run("CREATE DATABASE #{scratch} OWNER mainline")
      db.run("GRANT CONNECT ON DATABASE #{scratch} TO mainline_app")
    end
  end

  # Each person's login link in what the trial printed, as [label, address].
  def login_links(out)
    out.scan(/^  (.+): (\S+_test_login\S+)$/)
  end

  after do
    server { |db| db.run("DROP DATABASE IF EXISTS #{scratch} WITH (FORCE)") }
  end

  it "build the trial's sample teams on a first start, every released story with its scenarios done" do
    out, status = Subprocess.run(as_development, 'bundle', 'exec', 'rake', 'trial_up')

    assert_predicate status, :success?, out
    assert_includes out, 'Login as:'
    scratch_database do |db|
      released = db[:stories].where(status: 'released')

      refute_empty released
      assert_empty released.exclude(id: db[:scenarios].select(:story_id))
      assert_empty released.where(id: db[:scenarios].where(done_at: nil).select(:story_id))
    end
  end

  it "print the trial's login links where a newcomer finds them: no statements or requests, each person once, at this install" do
    out, status = Subprocess.run(as_development, 'bundle', 'exec', 'rake', 'trial_up')
    labels = login_links(out).map(&:first)
    sites = login_links(out).map { |_, address| address[%r{\Ahttps?://[^/]+}] }.uniq

    assert_predicate status, :success?, out
    refute_match(/(INFO|ERROR) -- :/, out)
    refute_match(%r{"(GET|POST) /}, out)
    assert_operator out.lines.length, :<, 200
    refute_empty labels
    assert_equal labels.uniq, labels
    assert_equal [ENV.fetch('BASE_URL')], sites
  end
end
