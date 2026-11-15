# frozen_string_literal: true

require_relative 'env_requirements'
require_relative 'ci_monitor_setup'

missing = EnvRequirements.missing(ENV)
missing.each { |var| warn "FATAL: required environment variable #{var} is missing or empty" }
half_off = CIMonitorSetup.half_off(ENV)
half_off.each { |var| warn "FATAL: #{var} is set while other CI Monitor settings are disabled; set all six, or disable all six" }
exit 1 unless missing.empty? && half_off.empty?
