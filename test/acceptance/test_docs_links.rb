# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

# The docs live in one place, the hosted site; core's pages link there.
describe 'Docs links' do
  include MainlineDSL

  it 'point at the hosted docs from core pages' do
    setup_team
    add_person(name: 'Alice')
    create_map

    body = driver.visit_map(@map).body

    assert_includes body, 'href="https://mainline.dev/docs'
    refute_includes body, 'href="/docs'
  end
end
