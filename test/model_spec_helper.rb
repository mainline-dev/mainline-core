# test/model_spec_helper.rb
# frozen_string_literal: true

require_relative 'coverage_helper'
ENV['RACK_ENV'] = 'test'
require_relative '../models'
require_relative '../lib/set_team_context'
require_relative '../lib/ci_monitor'

raise "test database doesn't end with test" if DB.opts[:database] && !DB.opts[:database].end_with?('test')

require_relative 'test_helper'

if ENV['NO_AUTOLOAD']
  Sequel::Model.freeze_descendents
  DB.freeze
end
