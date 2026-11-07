# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Style guide' do
  include MainlineDSL

  it 'renders the style guide page' do
    setup_team
    add_person(name: 'Alice')

    resp = driver.visit_styleguide

    assert_equal 200, resp.status
    assert_includes resp.body, 'data-test-id="styleguide"'
  end
end
