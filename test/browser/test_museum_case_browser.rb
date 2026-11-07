# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/jira_export'

describe 'Ticket Museum cases (browser)' do
  include MainlineDSL

  before do
    setup_team
    add_person(name: 'Alice')
    import_jira_csv(JiraExport.csv(
      { key: 'SHOP-10', id: '10', summary: 'Guest checkout', description: "h2. Background\nCustomers abandon at the account step" },
      { key: 'SHOP-14', id: '14', summary: 'Guest token on orders' }
    ))
  end

  def row(key)
    %([data-test-id="museum-item"][data-key="#{key}"])
  end

  def case_of(key)
    %([data-test-id="museum-case"][data-key="#{key}"])
  end

  it 'opens a row in place, one at a time, and closes it again' do
    use_browser!
    visit "/teams/#{@team.id}/museum"

    find(row('SHOP-10')).click

    assert_selector case_of('SHOP-10')
    assert_current_path(/open=SHOP-10/, url: true)

    find(row('SHOP-14')).click

    assert_selector case_of('SHOP-14')
    assert_no_selector case_of('SHOP-10')

    find(row('SHOP-14')).click

    assert_no_selector case_of('SHOP-14')
    refute_match(/open=/, current_url)
  end

  def press_enter_on(selector)
    execute_script(%(document.querySelector('#{selector}').focus()))
    page.driver.browser.keyboard.type(:Enter)
  end

  it 'opens and closes a case from the keyboard' do
    use_browser!
    visit "/teams/#{@team.id}/museum"

    press_enter_on('[data-test-id="museum-open-case"][data-key="SHOP-10"]')

    assert_selector case_of('SHOP-10')
    assert_selector %([data-test-id="museum-open-case"][data-key="SHOP-10"][aria-expanded="true"])

    press_enter_on('[data-test-id="museum-open-case"][data-key="SHOP-10"]')

    assert_no_selector case_of('SHOP-10')
    assert_selector %([data-test-id="museum-open-case"][data-key="SHOP-10"][aria-expanded="false"])
  end

  it 'leaves the row shut when its tick box is used' do
    use_browser!
    visit "/teams/#{@team.id}/museum"

    find(%([data-test-id="museum-select"][data-key="SHOP-10"])).click

    assert_selector '[data-test-id="museum-selection"]'
    assert_no_selector case_of('SHOP-10')
  end
end
