# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

# The read-only demo is gone: the 14-day trial lets people try Mainline on
# their own work.
describe 'No demo' do
  include MainlineDSL

  it 'answers 404 where the demo was' do
    setup_team
    add_person(name: 'Alice')

    %w[/demo /demo/ci /demo/teamwork].each do |path|
      err = assert_raises(RuntimeError) { driver.get(path) }

      assert_match(/404/, err.message, path)
    end
  end
end
