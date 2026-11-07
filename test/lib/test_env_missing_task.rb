# frozen_string_literal: true

ENV['MT_NO_PLUGINS'] = '1'
gem 'minitest'
require 'minitest/global_expectations/autorun'
require_relative '../subprocess_helper'

describe 'rake env:missing' do
  # Returns [stdout, status]; the report goes to stdout, so warnings from
  # ruby or bundler on stderr cannot be mistaken for a listed variable.
  def run_task(env)
    out, _err, status = Subprocess.capture(env, 'rake', 'env:missing')
    [out, status]
  end

  it 'lists a missing variable with what it is for' do
    out, status = run_task('SMTP_HOST' => nil)

    refute_predicate status, :success?
    assert_match(/^SMTP_HOST\s+\S/, out)
  end

  it 'reports nothing missing when every variable is set' do
    out, status = run_task({})

    assert_predicate status, :success?, out
    assert_empty out.lines.grep(/^[A-Z][A-Z0-9_]+\s/), 'variables listed as missing'
  end
end
