# frozen_string_literal: true

require_relative 'machine_paths'

# Whether the app checks the security token a form carries. It does on every
# request outside tests. Most tests post forms without a token, so in tests it
# is off until a test turns it on; the switch does nothing anywhere else.
module CsrfCheck
  @in_tests = false

  class << self
    attr_writer :in_tests

    def on?(env = ENV)
      env['RACK_ENV'] != 'test' || @in_tests
    end

    # The paths machines call answer for themselves, and a sign-in provider
    # coming back to /auth/ is checked by OmniAuth.
    def skips?(path)
      path.start_with?('/auth/') || MachinePaths.machine?(path)
    end
  end
end
