# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/jira_export'
require_relative '../dsl/mainline_file'

describe 'Ticket Museum import (browser)' do
  include MainlineDSL

  before do
    setup_team
    add_person(name: 'Alice')
  end

  def drag(event, csv = 'Issue key')
    page.execute_script(<<~JS, event, csv)
      const files = new DataTransfer();
      files.items.add(new File([arguments[1]], 'shop.csv', { type: 'text/csv' }));
      document.body.dispatchEvent(new DragEvent(arguments[0], { dataTransfer: files, bubbles: true, cancelable: true }));
    JS
  end

  it 'shows where a dragged file will land, until it leaves' do
    import_jira_csv(JiraExport.csv({ key: 'SHOP-1' }))
    use_browser!
    visit "/teams/#{@team.id}/museum"

    assert_no_selector '[data-test-id="museum-drop-overlay"]'

    drag('dragover')

    assert_selector '[data-test-id="museum-drop-overlay"]'

    drag('dragleave')

    assert_no_selector '[data-test-id="museum-drop-overlay"]'
  end

  it 'takes a file dropped on the museum list straight to the preview' do
    import_jira_csv(JiraExport.csv({ key: 'SHOP-1' }))
    use_browser!
    visit "/teams/#{@team.id}/museum"

    drag('drop', JiraExport.csv({ key: 'SHOP-2' }, { key: 'SHOP-3' }))

    assert_selector '[data-test-id="museum-import-preview"][data-added="2"]'
  end

  it 'takes no notice of something other than a file dragged over the page' do
    import_jira_csv(JiraExport.csv({ key: 'SHOP-1' }))
    use_browser!
    visit "/teams/#{@team.id}/museum"

    page.execute_script(<<~JS)
      document.body.dispatchEvent(new DragEvent('dragover', { dataTransfer: new DataTransfer(), bubbles: true, cancelable: true }));
    JS

    assert_no_selector '[data-test-id="museum-drop-overlay"]'
  end

  it 'takes a file dropped on the page straight to the preview' do
    use_browser!
    visit "/teams/#{@team.id}/museum/import"

    page.execute_script(<<~JS, JiraExport.csv({ key: 'SHOP-1' }, { key: 'SHOP-2' }))
      const files = new DataTransfer();
      files.items.add(new File([arguments[0]], 'shop.csv', { type: 'text/csv' }));
      document.body.dispatchEvent(new DragEvent('drop', { dataTransfer: files, bubbles: true, cancelable: true }));
    JS

    assert_selector '[data-test-id="museum-import-preview"][data-added="2"]'
  end

  it 'brings up the prompt to let go without a reload, once the curator has looked' do
    path = File.join(Dir.tmpdir, "shop-#{SecureRandom.hex(4)}.csv")
    File.write(path, JiraExport.csv(*(10..21).map { |n| { key: "OLD-#{n}", id: n.to_s, summary: "Old ticket about thing #{n}" } }))
    use_browser!
    visit "/teams/#{@team.id}/museum/import"
    attach_file('museum-csv', path, make_visible: true)
    find('[data-test-id="museum-import-apply"]').click

    assert_selector '[data-test-id="museum-item"]', minimum: 1
    assert_selector '[data-test-id="let-go-watching"]', visible: :all
    let_the_curator_look

    assert_selector '[data-test-id="let-go-prompt"]', wait: 10
  ensure
    FileUtils.rm_f(path) if path
  end

  it 'takes a chosen Mainline file to the preview of its proposed backbone, and acquires what is ticked' do
    use_browser!
    visit "/teams/#{@team.id}/museum/import"
    find('[data-test-id="museum-source"][data-source="mainline"]').click
    path = File.join(Dir.tmpdir, "stories-#{SecureRandom.hex(4)}.json")
    File.write(path, MainlineFileFixture.json({ key: 'RB-1' }, map: 'RepoBoard', personas: ['Team member'],
      activities: [{ name: 'Track work', personas: ['Team member'], steps: ['Find an item', 'Change an item'] }]))

    attach_file('museum-csv', path, make_visible: true)

    assert_selector '[data-test-id="museum-import-preview"][data-added="1"]'
    find('[data-test-id="museum-backbone-step"][data-name="Change an item"] input').uncheck
    find('[data-test-id="museum-import-apply"]').click

    assert_selector '[data-test-id="museum-item"][data-key="RB-1"][data-source="mainline"]'
    assert_equal({ personas: ['Team member'], activities: { 'Track work' => ['Find an item'] } }, map_laid_out('RepoBoard'))
  ensure
    FileUtils.rm_f(path) if path
  end

  it 'takes a chosen file straight to the preview' do
    use_browser!
    visit "/teams/#{@team.id}/museum/import"
    path = File.join(Dir.tmpdir, "shop-#{SecureRandom.hex(4)}.csv")
    File.write(path, JiraExport.csv({ key: 'SHOP-1' }))

    attach_file('museum-csv', path, make_visible: true)

    assert_selector '[data-test-id="museum-import-preview"][data-added="1"]'
  ensure
    FileUtils.rm_f(path) if path
  end
end
