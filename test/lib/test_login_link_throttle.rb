# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/login_link_throttle'

describe LoginLinkThrottle do
  before { @prefix = LoginLinkThrottle.prefix }

  after do
    LoginLinkThrottle.reset
    LoginLinkThrottle.prefix = @prefix
  end

  def in_run(name, &)
    LoginLinkThrottle.prefix = "login_link_sent:#{name}:"
    yield
  end

  it "clearing one run's marks leaves another run's alone" do
    in_run('a') { LoginLinkThrottle.allow?('alice@acme.co') }
    in_run('b') { LoginLinkThrottle.reset }

    in_run('a') { refute LoginLinkThrottle.allow?('alice@acme.co') }
  end
end
