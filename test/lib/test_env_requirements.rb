# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/env_requirements'

describe EnvRequirements do
  def complete_env
    EnvRequirements.required.keys.to_h { |var| [var, 'x'] }
  end

  it 'reports a variable that is missing or empty' do
    env = complete_env.except('SMTP_HOST').merge('MAIL_FROM' => '')

    assert_equal %w[SMTP_HOST MAIL_FROM].sort, EnvRequirements.missing(env).sort
  end

  it 'reports nothing when every variable is set' do
    assert_empty EnvRequirements.missing(complete_env)
  end

  it 'describes each missing variable' do
    env = complete_env.except('SMTP_HOST', 'CI_MONITOR_GITHUB_APP_ID')

    lines = EnvRequirements.missing_report(env)

    assert_equal 2, lines.size
    assert_match(/^SMTP_HOST\s+#{Regexp.escape(EnvRequirements.required['SMTP_HOST'])}$/, lines[0])
    assert_match(/^CI_MONITOR_GITHUB_APP_ID\s+#{Regexp.escape(EnvRequirements.required['CI_MONITOR_GITHUB_APP_ID'])}$/, lines[1])
  end
end
