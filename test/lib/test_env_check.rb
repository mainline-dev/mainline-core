# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../subprocess_helper'
require_relative '../../lib/env_requirements'

describe 'Environment check' do
  # Every variable the check demands, core and plugin, each set to something.
  def required_env
    vars = EnvRequirements.required.keys
    vars.to_h { |var| [var, 'x'] }
  end

  def boot(env)
    unset = required_env.keys.to_h { |var| [var, nil] }
    Subprocess.run(unset.merge(env), 'ruby', '-e', "load './lib/env_check.rb'")
  end

  it 'refuses to boot when a required variable is missing' do
    out, status = boot({})

    refute_predicate status, :success?
    assert_includes out, 'FATAL'
    assert_includes out, 'MAINLINE_SESSION_SECRET'
  end

  it 'boots when every required variable is set' do
    _, status = boot(required_env)

    assert_predicate status, :success?
  end

  it 'refuses to boot without mail settings' do
    out, status = boot(required_env.except('SMTP_HOST'))

    refute_predicate status, :success?
    assert_includes out, 'SMTP_HOST'
  end

  it 'refuses to boot without the job queue or error reporting settings' do
    %w[REDIS_URL SENTRY_DSN SENTRY_ENVIRONMENT].each do |var|
      out, status = boot(required_env.except(var))

      refute_predicate status, :success?, "booted without #{var}"
      assert_includes out, var
    end
  end
end
