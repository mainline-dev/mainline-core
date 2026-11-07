# frozen_string_literal: true

require_relative 'env_requirements'

missing = EnvRequirements.missing(ENV)
missing.each { |var| warn "FATAL: required environment variable #{var} is missing or empty" }
exit 1 unless missing.empty?
