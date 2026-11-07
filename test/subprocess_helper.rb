# frozen_string_literal: true

require 'open3'

# Runs a command from the repository root, the way the boot tests do: with an
# environment overlay (nil removes a variable) and the output captured.
module Subprocess
  ROOT = File.expand_path('..', __dir__)

  # Returns [stdout+stderr, status].
  def self.run(env, *cmd)
    Open3.capture2e(env, *cmd, chdir: ROOT)
  end

  # Returns [stdout, stderr, status].
  def self.capture(env, *cmd)
    Open3.capture3(env, *cmd, chdir: ROOT)
  end
end
