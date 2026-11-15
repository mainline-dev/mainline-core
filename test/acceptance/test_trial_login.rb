# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

# The quick start's trial prints a login link for each sample person. A link
# signs that person in and takes them to a page on this site, so the first
# thing a trial shows is the product.
describe 'Trial login links' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
  end

  it 'signs the person in and takes them to the page the link names' do
    follow_login_link(@alice, to: '/teams')

    assert_sent_on_to('/teams')
  end

  it 'never sends anyone off the site' do
    ['https://example.com/', '//example.com/'].each do |elsewhere|
      follow_login_link(@alice, to: elsewhere)

      refute_sent_anywhere
    end
  end
end
