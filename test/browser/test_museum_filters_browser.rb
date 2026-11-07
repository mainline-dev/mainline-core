# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/jira_export'

describe 'Ticket Museum filters (browser)' do
  include MainlineDSL

  before do
    setup_team
    add_person(name: 'Alice')
    import_jira_csv(JiraExport.csv(
      { key: 'SHOP-1', id: '1', summary: 'Guest checkout' },
      { key: 'SHOP-2', id: '2', type: 'Bug', summary: 'Refunds fail' }
    ))
  end

  it 'applies a filter as soon as it changes, keeping it in the address' do
    use_browser!
    visit "/teams/#{@team.id}/museum"

    find('[data-test-id="museum-filter-type"] option[value="Bug"]').select_option

    assert_no_selector '[data-test-id="museum-item"][data-key="SHOP-1"]'
    assert_selector '[data-test-id="museum-item"][data-key="SHOP-2"]'
    assert_current_path(/type=Bug/, url: true)
  end

  it 'offers the reasons once storage is chosen, and takes them away again' do
    MuseumItem.where(team_id: @team.id, source_key: 'SHOP-2').update(discarded_at: Time.now, storage_note: 'vague')
    use_browser!
    visit "/teams/#{@team.id}/museum"

    assert_no_selector '[data-test-id="museum-filter-why"]'

    find('[data-test-id="museum-filter-status"] option[value="in-storage"]').select_option

    assert_selector '[data-test-id="museum-filter-why"]'
    find('[data-test-id="museum-filter-why"] option[value="vague"]').select_option

    assert_current_path(/why=vague/, url: true)
    assert_selector '[data-test-id="museum-item"][data-key="SHOP-2"]'

    find('[data-test-id="museum-filter-status"] option[value=""]').select_option

    assert_no_selector '[data-test-id="museum-filter-why"]'
    refute_match(/why=/, current_url)
  end

  it 'searches as you type' do
    use_browser!
    visit "/teams/#{@team.id}/museum"

    find('[data-test-id="museum-search"]').set('refund')

    assert_no_selector '[data-test-id="museum-item"][data-key="SHOP-1"]'
    assert_selector '[data-test-id="museum-item"][data-key="SHOP-2"]'
  end
end
