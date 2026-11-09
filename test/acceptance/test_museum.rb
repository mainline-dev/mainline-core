# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/jira_export'

describe 'Ticket Museum' do
  include MainlineDSL

  before do
    MUSEUM_UPLOAD_RATE_LIMITER.reset
    setup_team
    add_person(name: 'Alice')
  end

  it 'is linked from the team nav' do
    visit_team_dashboard

    assert_shown('nav-museum')
  end

  it 'links to an import page that explains how to export from Jira' do
    visit_museum

    assert_shown('museum-import-link')

    visit_museum_import_page

    assert_shown('museum-import-guide')
    assert_shown('museum-import-form')
  end

  it 'starts empty' do
    visit_museum

    assert_shown('museum-empty')
  end

  it 'shows the open issues from a Jira export' do
    import_jira_csv(JiraExport.csv({ key: 'SHOP-1' }, { key: 'SHOP-2' }, { key: 'SHOP-3', resolution: 'Done' }))

    assert_notice_shown
    assert_equal %w[SHOP-1 SHOP-2], museum_keys_shown.sort
    refute_shown('museum-empty')
  end

  it 'lists issues that were in progress first' do
    import_jira_csv(JiraExport.csv({ key: 'SHOP-1', created: '01/Mar/24 9:00 AM' },
      { key: 'SHOP-2', created: '01/Jan/24 9:00 AM', category: 'In Progress' },
      { key: 'SHOP-3', created: '01/Feb/24 9:00 AM' }))

    assert_equal %w[SHOP-2 SHOP-1 SHOP-3], museum_keys_shown
    assert_page_includes('data-key="SHOP-2" data-in-progress')
  end

  it 'shows what an upload will do before changing anything' do
    upload_jira_csv(JiraExport.csv({ key: 'SHOP-1' }, { key: 'SHOP-2' }, { key: 'SHOP-3', resolution: 'Done' },
      { key: 'SHOP-4', summary: '' }))

    assert_shown('museum-import-preview')
    assert_page_includes('data-added="2" data-updated="0" data-finished="1" data-skipped="1"')
    assert_page_includes('data-test-id="museum-import-problem" data-row="5"')
    visit_museum

    assert_shown('museum-empty')
  end

  it 'hands back the rows it could not import, to fix and import again' do
    upload_jira_csv(JiraExport.csv({ key: 'SHOP-1' }, { key: 'SHOP-2', summary: '' }))
    problems = download_museum_import_problems(driver.museum_import_shown)

    import_jira_csv(problems.sub(/^No summary,,/, 'No summary,Fixed summary,'))

    assert_equal %w[SHOP-2], museum_keys_shown
  end

  it 'keeps the last ten acquisitions on the import page' do
    11.times { |n| import_jira_csv(JiraExport.csv({ key: "SHOP-#{n}", id: n.to_s })) }

    visit_museum_import_page

    assert_equal 10, museum_import_rows_shown
  end

  it 'lists recent uploads on the import page, with undo on the latest import only' do
    import_jira_csv(JiraExport.csv({ key: 'SHOP-1' }))
    import_jira_csv(JiraExport.csv({ key: 'SHOP-2' }))
    upload_jira_csv(JiraExport.csv({ key: 'SHOP-3' }))

    visit_museum_import_page

    assert_equal 2, page_body.scan('data-test-id="museum-import-row" data-status="imported"').size
    assert_equal 1, page_body.scan('data-test-id="museum-import-row" data-status="staged"').size
    assert_equal 1, page_body.scan('data-test-id="museum-import-undo"').size
  end

  it 'heads the columns of past acquisitions' do
    import_jira_csv(JiraExport.csv({ key: 'SHOP-1' }))

    visit_museum_import_page

    assert_shown('museum-imports-head')
  end

  it 'says a CSV can be dropped on the list, whether the galleries are empty or not' do
    visit_museum

    assert_shown('museum-drop-caption')
    import_jira_csv(JiraExport.csv({ key: 'SHOP-1' }))
    visit_museum

    assert_shown('museum-drop-caption')
  end

  it 'keeps one file waiting at a time, turning down the earlier one' do
    upload_jira_csv(JiraExport.csv({ key: 'SHOP-1' }))
    upload_jira_csv(JiraExport.csv({ key: 'SHOP-2' }))

    visit_museum_import_page

    assert_equal 1, page_body.scan('data-test-id="museum-import-row" data-status="staged"').size
    assert_equal 1, page_body.scan('data-test-id="museum-import-row" data-status="cancelled"').size
  end

  it 'turns away uploads sent faster than a person would' do
    20.times { |n| upload_jira_csv(JiraExport.csv({ key: "SHOP-#{n}" })) }

    upload_jira_csv(JiraExport.csv({ key: 'SHOP-99' }))

    assert_error_shown
    assert_nil driver.museum_import_shown
  end

  it 'undoes the last import from the import page' do
    import_jira_csv(JiraExport.csv({ key: 'SHOP-1' }))
    visit_museum_import_page

    undo_museum_import_shown

    assert_notice_shown
    assert_shown('museum-empty')
  end

  it 'offers no return on an earlier acquisition once the latest has been returned' do
    import_jira_csv(JiraExport.csv({ key: 'SHOP-1' }))
    import_jira_csv(JiraExport.csv({ key: 'SHOP-2' }))
    undo_last_museum_import
    visit_museum_import_page

    refute_page_includes('data-test-id="museum-import-undo"')
    follow_museum_link('museum-import-link-row')

    refute_page_includes('data-test-id="museum-import-undo"')
  end

  it 'undoes the last import from its page' do
    import_jira_csv(JiraExport.csv({ key: 'SHOP-1' }))

    undo_last_museum_import

    assert_notice_shown
    assert_shown('museum-empty')
  end

  it 'leaves the museum as it was when an upload is cancelled' do
    upload_jira_csv(JiraExport.csv({ key: 'SHOP-1' }))

    cancel_museum_import

    assert_notice_shown
    assert_shown('museum-empty')
  end

  it 'refuses a file that is not a Jira export' do
    import_jira_csv("name,email\nAlice,alice@example.com\n")

    assert_error_shown
    assert_shown('museum-import-form')
    visit_museum

    assert_shown('museum-empty')
  end

  it 'asks for a file when none is chosen' do
    import_jira_csv(nil)

    assert_error_shown
    assert_shown('museum-import-form')
    visit_museum

    assert_shown('museum-empty')
  end

  it 'keeps each team to its own museum' do
    import_jira_csv(JiraExport.csv({ key: 'SHOP-1' }))

    setup_team(name: 'Other')
    login_as(add_person(name: 'Bob'))
    visit_museum

    assert_shown('museum-empty')
  end

  it 'filters by type, label, epic and age' do
    recent = Time.now.utc.strftime('%d/%b/%y %I:%M %p')
    import_jira_csv(JiraExport.csv(
      { key: 'SHOP-1', id: '1', type: 'Epic' },
      { key: 'SHOP-2', id: '2', type: 'Bug', parent: '1', created: recent },
      { key: 'SHOP-3', id: '3', labels: ['mobile'], created: recent },
      { key: 'SHOP-4', id: '4', created: '01/Jan/20 9:00 AM' }
    ))

    visit_museum(type: 'Bug')

    assert_equal ['SHOP-2'], museum_keys_shown

    visit_museum(label: 'mobile')

    assert_equal ['SHOP-3'], museum_keys_shown

    visit_museum(epic: 'SHOP-1')

    assert_equal ['SHOP-2'], museum_keys_shown

    visit_museum(age: 'over-a-year')

    assert_equal ['SHOP-4'], museum_keys_shown
  end

  it 'searches the museum, keeping the search across pages' do
    issues = Array.new(105) { |n| { key: "SHOP-#{n}", id: n.to_s, summary: 'Guest checkout' } }
    import_jira_csv(JiraExport.csv(*issues, { key: 'SHOP-999', id: '999', summary: 'Wishlist' }))

    visit_museum(search: 'checkout')

    assert_page_includes('data-test-id="museum-total" data-count="105"')
    assert_page_includes('data-test-id="museum-search" value="checkout"')

    follow_museum_link('museum-next')

    assert_equal 5, museum_keys_shown.size
    refute_includes museum_keys_shown, 'SHOP-999'
  end

  it 'points to an upload waiting to be catalogued' do
    upload_jira_csv(JiraExport.csv({ key: 'SHOP-1' }))

    visit_museum

    assert_shown('museum-waiting')
    refute_shown('museum-import-row')

    follow_museum_link('museum-waiting-review')
    apply_museum_import

    visit_museum

    refute_shown('museum-waiting')
  end

  it 'counts the whole museum by status' do
    import_jira_csv(JiraExport.csv({ key: 'SHOP-1', id: '1' }, { key: 'SHOP-2', id: '2' }, { key: 'SHOP-3', id: '3', type: 'Bug' }))
    discard_museum_item('SHOP-1')

    visit_museum(type: 'Bug')

    assert_page_includes('data-test-id="museum-catalogue" data-on-display="2" data-promoted="0" data-stored="1"')
  end

  it 'says where else the search matches when nothing on display does' do
    import_jira_csv(JiraExport.csv({ key: 'SHOP-1', id: '1', summary: 'Refund a card' }, { key: 'SHOP-2', id: '2' }))
    discard_museum_item('SHOP-1')

    visit_museum(search: 'refund')

    assert_page_includes('data-test-id="museum-no-match" data-promoted="0" data-stored="1"')
  end

  it 'sends just the results when filtering in place' do
    import_jira_csv(JiraExport.csv({ key: 'SHOP-1', id: '1' }, { key: 'SHOP-2', id: '2', type: 'Bug' }))

    filter_museum_in_place(type: 'Bug')

    assert_equal ['SHOP-2'], museum_keys_shown
    assert_page_includes('data-test-id="museum-total" data-count="1"')
    refute_shown('nav-museum')
    refute_shown('museum-filters')
  end

  it 'shows sub-tasks under their parent' do
    import_jira_csv(JiraExport.csv({ key: 'SHOP-1', id: '1' }, { key: 'SHOP-2', id: '2', type: 'Sub-task', parent: '1' }))

    visit_museum

    assert_equal ['SHOP-1'], museum_keys_shown
    assert_page_includes('data-test-id="museum-sub-task" data-key="SHOP-2" data-parent="SHOP-1"')
  end

  it 'pages through a big museum, keeping the filters' do
    issues = Array.new(105) { |n| { key: "SHOP-#{n}", id: n.to_s } }
    import_jira_csv(JiraExport.csv(*issues, { key: 'BUG-1', id: 'b1', type: 'Bug' }))

    visit_museum(type: 'Story')

    assert_shown('museum-total')
    assert_page_includes('data-test-id="museum-total" data-count="105"')
    assert_equal 100, museum_keys_shown.size
    refute_shown('museum-previous')

    follow_museum_link('museum-next')

    assert_equal 5, museum_keys_shown.size
    refute_includes museum_keys_shown, 'BUG-1'
    refute_shown('museum-next')

    follow_museum_link('museum-previous')

    assert_equal 100, museum_keys_shown.size
  end

  describe 'promoting an item to a story' do
    before do
      create_map(name: 'Shop')
      activity = create_activity('Checkout', for_personas: [create_persona('Shopper')])
      @task = create_task('Pay', under_activity: activity)
      import_jira_csv(JiraExport.csv(
        { key: 'SHOP-10', id: '10', summary: 'Guest checkout', description: 'A long Jira essay' },
        { key: 'SHOP-11', id: '11', type: 'Sub-task', parent: '10' }
      ))
    end

    it 'offers promote on listed items only' do
      visit_museum

      refute_page_includes('data-test-id="museum-no-tasks"')

      assert_page_includes('data-test-id="museum-promote" data-key="SHOP-10"')
      refute_page_includes('data-test-id="museum-promote" data-key="SHOP-11"')
    end

    it 'shows the Jira record beside the story form, the title left to write with the summary as a hint' do
      visit_museum_promote('SHOP-10')

      assert_shown('museum-promote-form')
      assert_page_includes('data-test-id="museum-case" data-key="SHOP-10"')
      assert_page_includes('name="title" value="" placeholder="Guest checkout"')
      assert_page_includes(%(value="#{@task.id}"))
    end

    it 'creates the story on the map and comes back to the list where it left off' do
      visit_museum(type: 'Story')
      promote_museum_item('SHOP-10', title: 'Buy without an account', task: @task, return_to: last_museum_path)

      assert_notice_shown
      assert_includes last_museum_path, 'type=Story'
      assert_map_shows('Buy without an account')
      visit_museum

      assert_empty museum_keys_shown
    end

    it 'refuses an archived task' do
      archive_task(@task)

      promote_museum_item('SHOP-10', title: 'Buy without an account', task: @task)

      assert_error_shown
      assert_nil museum_item('SHOP-10').story_id
    end

    it "shows nothing of another team's exhibit" do
      theirs = other_team_museum_item

      assert_raises(RuntimeError) { open_museum_case_of(theirs) }
      assert_raises(RuntimeError) { visit_museum_promote_of(theirs) }
    end

    it 'gives the story the scenarios written while promoting' do
      promote_museum_item('SHOP-10', title: 'Buy without an account', task: @task,
        scenarios: [['a basket', 'I continue as a guest', 'I can pay'], ['', '', '']])

      assert_equal [['a basket', 'I continue as a guest', 'I can pay']], story_scenarios('Buy without an account')
    end

    it 'keeps the names given to scenarios written while promoting' do
      promote_museum_item('SHOP-10', title: 'Buy without an account', task: @task,
        scenarios: [['a basket', 'I continue as a guest', 'I can pay', 'Guest pays by email']])

      names = BypassRLS.call { Scenario.where(story_id: Story.where(title: 'Buy without an account').select(:id)).select_map(:name) }

      assert_equal ['Guest pays by email'], names
    end

    it 'refuses to promote with a scenario that has no name' do
      promote_museum_item('SHOP-10', title: 'Buy without an account', task: @task,
        scenarios: [['a basket', 'I continue as a guest', 'I can pay', '']])

      assert_error_shown
      assert_equal(0, BypassRLS.call { Story.where(title: 'Buy without an account').count })
    end

    it 'remembers the task last promoted under' do
      other = create_task('Track', under_activity: create_activity('After', for_personas: [create_persona('Buyer')]))
      import_jira_csv(JiraExport.csv({ key: 'SHOP-20', id: '20', summary: 'Order tracking' }))
      promote_museum_item('SHOP-10', title: 'Buy without an account', task: other)

      visit_museum_promote('SHOP-20')

      assert_page_includes(%(value="#{other.id}" selected))
    end

    it 'offers the rewrite form beside the record in an open case' do
      open_museum_case('SHOP-10')

      assert_page_includes('data-test-id="museum-case" data-key="SHOP-10"')
      assert_shown('museum-promote-form')
      assert_page_includes('name="title" value="" placeholder="Guest checkout"')
      assert_page_includes(%(value="#{@task.id}"))
    end

    it 'offers the rewrite form in the case named in the address' do
      visit_museum(open: 'SHOP-10')

      assert_shown('museum-promote-form')
    end

    it 'leaves the form out of a case that cannot be promoted' do
      import_jira_csv(JiraExport.csv({ key: 'SHOP-20', id: '20', summary: 'Order tracking' }))
      discard_museum_item('SHOP-20')
      promote_museum_item('SHOP-10', title: 'Buy without an account', task: @task)

      %w[SHOP-10 SHOP-11 SHOP-20].each do |key|
        open_museum_case(key)

        refute_page_includes('data-test-id="museum-promote-form"')
      end
    end

    it 'comes back to the list where it left off after promoting from an open case' do
      visit_museum(type: 'Story')
      open_museum_case('SHOP-10', from: last_museum_path)
      promote_from_open_case('SHOP-10', title: 'Buy without an account', task: @task)

      assert_notice_shown
      assert_includes last_museum_path, 'type=Story'
      assert_map_shows('Buy without an account')
    end

    it 'comes back without the case open after promoting from the case named in the address' do
      visit_museum(type: 'Story', open: 'SHOP-10')
      promote_from_open_case('SHOP-10', title: 'Buy without an account', task: @task)

      assert_includes last_museum_path, 'type=Story'
      refute_includes last_museum_path, 'open='
    end

    it 'only goes back to somewhere in this museum' do
      open_museum_case('SHOP-10', from: 'https://elsewhere.test/museum')
      promote_from_open_case('SHOP-10', title: 'Buy without an account', task: @task)

      assert_equal "/teams/#{@team.id}/museum", last_museum_path
    end

    it 'remembers the task last promoted under in an open case' do
      other = create_task('Track', under_activity: create_activity('After', for_personas: [create_persona('Buyer')]))
      import_jira_csv(JiraExport.csv({ key: 'SHOP-20', id: '20', summary: 'Order tracking' }))
      promote_museum_item('SHOP-10', title: 'Buy without an account', task: other)

      open_museum_case('SHOP-20')

      assert_page_includes(%(value="#{other.id}" selected))
    end

    it 'sends an exhibit to storage from its open case and comes back to the list' do
      import_jira_csv(JiraExport.csv({ key: 'SHOP-20', id: '20', summary: 'Order tracking' }))
      visit_museum(type: 'Story')
      open_museum_case('SHOP-10', from: last_museum_path)
      press_store('SHOP-10')

      assert_notice_shown
      assert_includes last_museum_path, 'type=Story'
      assert_equal ['SHOP-20'], museum_keys_shown
    end

    it 'keeps the record under show promoted, linked to the story' do
      promote_museum_item('SHOP-10', title: 'Buy without an account', task: @task)

      visit_museum(status: 'promoted')

      assert_equal ['SHOP-10'], museum_keys_shown
      assert_shown('museum-story-link')
    end

    it 'sends a promoted exhibit back to the museum from its row, and comes back to the list' do
      promote_museum_item('SHOP-10', title: 'Buy without an account', task: @task)
      visit_museum(status: 'promoted')

      send_back_to_museum('SHOP-10')

      assert_page_includes('data-test-id="flash-notice" data-story="archived"')
      assert_includes last_museum_path, 'status=promoted'
      visit_museum

      assert_equal ['SHOP-10'], museum_keys_shown
      assert_page_includes('data-test-id="museum-promote" data-key="SHOP-10"')
      refute_page_includes('data-test-id="museum-unpromote"')
      visit_map

      refute_page_includes('Buy without an account')
    end

    it 'says the story stays when it still has another exhibit' do
      import_jira_csv(JiraExport.csv({ key: 'SHOP-20', id: '20', summary: 'Order tracking' }))
      promote_museum_item('SHOP-10', title: 'Buy without an account', task: @task)
      add_to_story('SHOP-20', to: 'Buy without an account')
      visit_museum(status: 'promoted')

      send_back_to_museum('SHOP-10')

      assert_page_includes('data-test-id="flash-notice" data-story="kept"')
      assert_map_shows('Buy without an account')
    end

    it 'says so when an exhibit has nothing to be sent back from' do
      visit_museum

      send_back_to_museum('SHOP-10')

      assert_error_shown
    end

    it 'names the story in the toast after promoting, linked to it' do
      promote_museum_item('SHOP-10', title: 'Buy without an account', task: @task)

      assert_page_includes('Buy without an account')
      follow_museum_link('museum-toast-story')

      assert_includes last_museum_path, museum_item('SHOP-10').story_id
    end

    it 'undoes a promote from the toast, back on the same list' do
      visit_museum(type: 'Story')
      promote_museum_item('SHOP-10', title: 'Buy without an account', task: @task, return_to: last_museum_path)

      press_toast_undo

      assert_notice_shown
      assert_includes last_museum_path, 'type=Story'
      assert_equal ['SHOP-10'], museum_keys_shown
      refute_page_includes('data-test-id="museum-toast-undo"')
      visit_map

      refute_page_includes('Buy without an account')
    end

    it 'undoes sending an exhibit to storage from the toast, back on the same list' do
      visit_museum(type: 'Story')
      open_museum_case('SHOP-10', from: last_museum_path)
      press_store('SHOP-10')

      press_toast_undo

      assert_notice_shown
      assert_includes last_museum_path, 'type=Story'
      assert_equal ['SHOP-10'], museum_keys_shown
    end

    it 'offers no undo once an exhibit is sent back' do
      promote_museum_item('SHOP-10', title: 'Buy without an account', task: @task)
      visit_museum(status: 'promoted')

      send_back_to_museum('SHOP-10')

      assert_notice_shown
      refute_page_includes('data-test-id="museum-toast-undo"')
    end

    it 'promotes in place, the list coming back with the toast and the filters kept' do
      import_jira_csv(JiraExport.csv({ key: 'SHOP-20', id: '20', summary: 'Order tracking' },
        { key: 'SHOP-30', id: '30', type: 'Bug', summary: 'Broken link' }))
      visit_museum(type: 'Story')
      open_museum_case('SHOP-10', from: last_museum_path)

      promote_in_place('SHOP-10', title: 'Buy without an account', task: @task)

      refute_page_includes('<html')
      assert_equal ['SHOP-20'], museum_keys_shown
      assert_shown('museum-toast-undo')
      assert_page_includes('id="mu-tally"')
      assert_map_shows('Buy without an account')
    end

    it 'leaves the exhibit where it was when a promote in place is refused' do
      open_museum_case('SHOP-10', from: "/teams/#{@team.id}/museum")

      promote_in_place('SHOP-10', title: '', task: @task)
      visit_museum

      assert_equal ['SHOP-10'], museum_keys_shown
    end

    it 'gives every row something to open its case from the keyboard, promoted and stored rows too' do
      import_jira_csv(JiraExport.csv({ key: 'SHOP-20', id: '20', summary: 'Order tracking' }))
      promote_museum_item('SHOP-10', title: 'Guests can check out', task: @task)
      discard_museum_item('SHOP-20')

      visit_museum(status: 'everything')

      assert_page_includes('data-test-id="museum-open-case" data-key="SHOP-10"')
      assert_page_includes('data-test-id="museum-open-case" data-key="SHOP-20"')
    end

    it 'comes back to the same list after storing from a row and bringing out from a row' do
      visit_museum(type: 'Story')
      press_store('SHOP-10')

      assert_includes last_museum_path, 'type=Story'

      visit_museum(status: 'in-storage')
      press_bring_out('SHOP-10')

      assert_includes last_museum_path, 'status=in-storage'
    end

    it 'refuses a story without a title and keeps the item' do
      promote_museum_item('SHOP-10', title: '', task: @task)

      assert_error_shown
      visit_museum

      assert_equal ['SHOP-10'], museum_keys_shown
    end
  end

  describe 'letting go' do
    before do
      recent = (Date.today - 30).strftime('%d/%b/%y 10:15 AM')
      import_jira_csv(JiraExport.csv(
        { key: 'SHOP-1', id: '1', summary: 'Fix login', description: '', created: recent },
        { key: 'SHOP-2', id: '2', summary: 'Gift cards at the till', created: '02/Jan/24 10:15 AM' },
        { key: 'SHOP-3', id: '3', summary: 'Shoppers filter results by price', description: 'Detail', created: recent }
      ))
    end

    it 'shows the suggestions by group, ticked, each with its evidence' do
      let_the_curator_look
      visit_let_go

      assert_equal ['SHOP-2'], let_go_keys('stale')
      assert_equal ['SHOP-1'], let_go_keys('vague')
      assert_shown('let-go-evidence')
      assert_page_includes('data-key="SHOP-2" checked')
      refute_page_includes('data-key="SHOP-3"')
    end

    it 'sends what stays ticked to storage and leaves the rest on display' do
      let_the_curator_look
      visit_let_go

      let_go_of('SHOP-2')

      assert_shown('let-go-done')
      visit_museum

      assert_equal %w[SHOP-1 SHOP-3], museum_keys_shown.sort
      visit_museum(status: 'in-storage')

      assert_equal ['SHOP-2'], museum_keys_shown
    end

    describe 'with two tickets that look the same' do
      before do
        recent = (Date.today - 30).strftime('%d/%b/%y 10:15 AM')
        import_jira_csv(JiraExport.csv(
          { key: 'SHOP-5', id: '5', summary: 'Trailing whitespace breaks the search', description: '', created: recent },
          { key: 'SHOP-6', id: '6', summary: 'Trailing whitespace breaks the search', description: 'Steps to reproduce', created: recent }
        ))
        let_the_curator_look
        visit_let_go
      end

      it 'offers to keep the one with more detail and let the other go' do
        assert_shown('let-go-pair')
        assert_page_includes('data-keeps="SHOP-6" checked')
      end

      it 'stops suggesting a pair once both are kept' do
        keep_both('SHOP-5')

        assert_notice_shown
        let_the_curator_look
        visit_let_go

        refute_page_includes('data-test-id="let-go-pair"')
      end

      it 'lets go of the side chosen' do
        let_go_keeping('SHOP-5', of: 'SHOP-6')

        assert_shown('let-go-done')
        visit_museum(status: 'in-storage')

        assert_equal ['SHOP-6'], museum_keys_shown
      end
    end

    it 'starts with everything suggested going and says what would stay' do
      let_the_curator_look
      visit_let_go

      assert_page_includes('data-test-id="let-go-going" data-count="2"')
      assert_page_includes('data-test-id="let-go-staying" data-count="1"')
    end

    it 'stops suggesting an exhibit once kept, until that is undone' do
      let_the_curator_look
      visit_let_go

      keep_exhibit('SHOP-2')

      assert_shown('let-go-kept')
      let_the_curator_look
      visit_let_go

      assert_empty let_go_keys('stale')

      unkeep_exhibit('SHOP-2')
      let_the_curator_look
      visit_let_go

      assert_equal ['SHOP-2'], let_go_keys('stale')
    end

    it 'lists what was kept, where a keep can be undone after the page is gone' do
      let_the_curator_look
      visit_let_go
      keep_exhibit('SHOP-2')

      visit_museum(status: 'kept')

      assert_equal ['SHOP-2'], museum_keys_shown
      press_unkeep('SHOP-2')

      assert_includes last_museum_path, 'status=kept'
      assert_empty museum_keys_shown
      let_the_curator_look
      visit_let_go

      assert_equal ['SHOP-2'], let_go_keys('stale')
    end

    it 'only keeps what the curator suggested' do
      let_the_curator_look

      assert_raises(RuntimeError) { keep_exhibit('SHOP-3') }
    end

    it 'shows what was held back in a group, a page at a time' do
      import_jira_csv(JiraExport.csv(*(10..16).map { |n| { key: "OLD-#{n}", id: n.to_s, summary: "Old ticket about thing #{n}" } }))
      let_the_curator_look
      visit_let_go

      assert_equal 5, let_go_keys('stale').size
      assert_shown('let-go-rest')

      show_rest_of_let_go('stale', offset: 5)

      assert_equal %w[OLD-15 OLD-16 SHOP-2], let_go_row_keys
      refute_page_includes('data-test-id="let-go-rest"')
    end

    it 'says how many went and how many remain' do
      let_the_curator_look

      let_go_of('SHOP-2')

      assert_page_includes('data-test-id="let-go-done" data-gone="1" data-left="2"')
    end

    it 'has no done page to come back to' do
      visit_let_go_done

      assert_equal "/teams/#{@team.id}/museum", last_museum_path
    end

    it 'brings the whole batch back from the done page' do
      let_the_curator_look
      let_go_of('SHOP-1', 'SHOP-2')

      assert_shown('let-go-undo')
      undo_let_go

      assert_notice_shown
      assert_equal %w[SHOP-1 SHOP-2 SHOP-3], museum_keys_shown.sort
      visit_museum(status: 'in-storage')

      assert_empty museum_keys_shown
    end

    it 'offers the undo in a toast back on the museum' do
      let_the_curator_look
      let_go_of('SHOP-1', 'SHOP-2')
      visit_museum

      press_toast_undo

      assert_equal %w[SHOP-1 SHOP-2 SHOP-3], museum_keys_shown.sort
    end

    it 'only undoes a batch once' do
      let_the_curator_look
      let_go_of('SHOP-2')
      undo_let_go

      undo_let_go

      assert_error_shown
    end

    it 'shows why an exhibit is in storage under Everything as well' do
      let_the_curator_look
      let_go_of('SHOP-1', 'SHOP-2')

      visit_museum(status: 'everything')

      assert_page_includes('data-test-id="museum-storage-note" data-why="vague"')
    end

    it 'shows why an exhibit is in storage, and narrows storage to one reason' do
      let_the_curator_look
      let_go_of('SHOP-1', 'SHOP-2')
      visit_museum(status: 'in-storage')

      assert_page_includes('data-test-id="museum-storage-note" data-why="vague"')
      assert_page_includes('data-test-id="museum-filter-why"')
      assert_page_includes('<option value="vague"')

      visit_museum(status: 'in-storage', why: 'vague')

      assert_equal ['SHOP-1'], museum_keys_shown
    end

    it 'only asks why in storage, and ignores it anywhere else' do
      let_the_curator_look
      let_go_of('SHOP-1')
      visit_museum

      refute_page_includes('data-test-id="museum-filter-why"')

      visit_museum(why: 'vague')

      assert_equal %w[SHOP-2 SHOP-3], museum_keys_shown.sort
    end

    it 'says so when the curator has nothing to suggest' do
      visit_let_go

      assert_shown('let-go-nothing')
    end
  end

  describe 'the acquisition page' do
    it 'counts only what is in the file, always saying how many are new' do
      upload_jira_csv(JiraExport.csv({ key: 'SHOP-1', id: '1', category: 'Done' }))

      assert_equal({ 'added' => 0, 'finished' => 1 }, museum_ledger_shown)
    end

    it 'counts promoted and stored together as left as they are' do
      import_jira_csv(JiraExport.csv({ key: 'SHOP-1', id: '1' }, { key: 'SHOP-2', id: '2' }))
      discard_museum_item('SHOP-1')

      upload_jira_csv(JiraExport.csv({ key: 'SHOP-1', id: '1' }, { key: 'SHOP-2', id: '2', summary: 'Changed' }))

      assert_equal({ 'added' => 0, 'updated' => 1, 'left' => 1 }, museum_ledger_shown)
    end

    it 'has nothing to offer when nothing in the file can be acquired' do
      upload_jira_csv(JiraExport.csv({ key: 'SHOP-1', id: '1', category: 'Done' }))

      assert_page_includes('data-test-id="museum-import-apply" disabled')
    end

    it 'says how long a waiting file has before it is turned down' do
      upload_jira_csv(JiraExport.csv({ key: 'SHOP-1', id: '1' }))
      path = last_museum_path

      Timecop.travel(Time.now + (5 * 60 * 60)) { visit_path(path) }

      assert_page_includes('data-test-id="museum-import-expires" data-hours="19"')
    end

    it 'shows five rows turned away and keeps the others a click away' do
      upload_jira_csv(JiraExport.csv(*(1..7).map { |n| { key: "SHOP-#{n}", id: n.to_s, summary: '' } }))

      assert_page_includes('data-test-id="museum-import-problems-more" data-count="2"')
      assert_equal 7, museum_import_problems_shown
    end

    it 'says who acquired a file and when, and offers to return it' do
      import_jira_csv(JiraExport.csv({ key: 'SHOP-1', id: '1' }))
      visit_museum_import_page
      follow_museum_link('museum-import-link-row')

      assert_page_includes('data-status="imported"')
      assert_shown('museum-import-by')
      assert_shown('museum-import-undo')
    end

    it 'says a returned file left the museum as it was' do
      import_jira_csv(JiraExport.csv({ key: 'SHOP-1', id: '1' }))
      undo_last_museum_import
      visit_museum_import_page
      follow_museum_link('museum-import-link-row')

      assert_page_includes('data-status="undone"')
      refute_page_includes('data-test-id="museum-import-undo"')
    end

    it 'says nothing entered from a file turned down' do
      upload_jira_csv(JiraExport.csv({ key: 'SHOP-1', id: '1' }))
      cancel_museum_import
      visit_museum_import_page
      follow_museum_link('museum-import-link-row')

      assert_page_includes('data-status="cancelled"')
      refute_page_includes('data-test-id="museum-import-apply"')
    end
  end

  describe 'promoting together' do
    before do
      create_map(name: 'Shop')
      @task = create_task('Pay', under_activity: create_activity('Checkout', for_personas: [create_persona('Shopper')]))
      import_jira_csv(JiraExport.csv(
        { key: 'SHOP-1', id: '1', summary: 'Guest checkout' },
        { key: 'SHOP-2', id: '2', summary: 'Guest token on orders' },
        { key: 'SHOP-3', id: '3', type: 'Sub-task', parent: '1', summary: 'Store the guest email' },
        { key: 'SHOP-4', id: '4', type: 'Bug', summary: 'Refunds fail' }
      ))
    end

    it 'shows every exhibit beside one form, with sub-tasks leaving with their parent' do
      visit_together('SHOP-1', 'SHOP-2')

      assert_equal %w[SHOP-1 SHOP-2], together_cards_shown
      assert_equal %w[SHOP-1 SHOP-3 SHOP-2], leaving_keys_shown
      assert_shown('museum-promote-form')
    end

    it 'counts the exhibits on the button, as the title does, with sub-tasks listed rather than counted' do
      visit_together('SHOP-1', 'SHOP-2')

      assert_page_includes('data-test-id="museum-promote-submit" data-count="2"')
    end

    it 'leaves out what cannot be promoted' do
      promote_museum_item('SHOP-2', title: 'Tokens on orders', task: @task)

      visit_together('SHOP-1', 'SHOP-2', also: [other_team_museum_item.id])

      assert_equal ['SHOP-1'], together_cards_shown
    end

    it 'goes back with an error when there is nothing to promote' do
      promote_museum_item('SHOP-2', title: 'Tokens on orders', task: @task)

      visit_together('SHOP-2')

      assert_error_shown
      assert_includes last_museum_path, '/museum'
    end

    it 'makes one story of them and comes back to the list where it left off' do
      visit_museum(type: 'Story')
      promote_together('SHOP-1', 'SHOP-2', title: 'Buy without an account', task: @task, return_to: last_museum_path)

      assert_notice_shown
      assert_includes last_museum_path, 'type=Story'
      assert_equal 2, story_exhibits('Buy without an account')
      assert_map_shows('Buy without an account')
    end

    it 'counts what was linked to the story, leaving sub-tasks out' do
      promote_together('SHOP-1', 'SHOP-2', title: 'Buy without an account', task: @task)

      assert_page_includes('data-test-id="flash-notice" data-count="2"')
    end

    it 'names the story in the toast, linked to it' do
      promote_together('SHOP-1', 'SHOP-2', title: 'Buy without an account', task: @task)

      assert_page_includes('Buy without an account')
      follow_museum_link('museum-toast-story')

      assert_includes last_museum_path, museum_item('SHOP-1').story_id
    end

    it 'sends all of them back from the toast, and the story goes' do
      visit_museum(type: 'Story')
      promote_together('SHOP-1', 'SHOP-2', title: 'Buy without an account', task: @task, return_to: last_museum_path)

      press_toast_undo

      assert_page_includes('data-story="archived" data-toast')
      assert_includes last_museum_path, 'type=Story'
      assert_equal %w[SHOP-1 SHOP-2], museum_keys_shown.sort
      visit_map

      refute_page_includes('Buy without an account')
    end

    it 'keeps the set and what was written when refused' do
      promote_together('SHOP-1', 'SHOP-2', title: '', task: @task, scenarios: [['a basket', 'I pay', 'it works']])

      assert_error_shown
      assert_equal %w[SHOP-1 SHOP-2], together_cards_shown
      assert_page_includes('a basket')
    end
  end

  describe 'adding to a story' do
    before do
      create_map(name: 'Shop')
      @task = create_task('Pay', under_activity: create_activity('Checkout', for_personas: [create_persona('Shopper')]))
      import_jira_csv(JiraExport.csv(
        { key: 'SHOP-1', id: '1', summary: 'Guest checkout' },
        { key: 'SHOP-2', id: '2', summary: 'Guest token on orders' },
        { key: 'SHOP-3', id: '3', summary: 'Hide the password fields' },
        { key: 'SHOP-4', id: '4', type: 'Bug', summary: 'Refunds fail' }
      ))
      promote_museum_item('SHOP-1', title: 'Buy without an account', task: @task)
    end

    it 'finds stories on the maps' do
      search_stories('account')

      assert_equal ['Buy without an account'], story_hits_shown
      search_stories('nothing like this')

      assert_empty story_hits_shown
      assert_shown('museum-no-stories')
    end

    it 'says there are no stories yet, rather than no match, before anything is typed' do
      unpromote_museum_item('SHOP-1')

      search_stories('')

      assert_shown('museum-no-stories-yet')
      refute_shown('museum-no-stories')
      search_stories('account')

      assert_shown('museum-no-stories')
    end

    it 'offers it in the open case and on the promote page' do
      open_museum_case('SHOP-2')

      assert_shown('museum-add-form')
      visit_museum_promote('SHOP-2')

      assert_shown('museum-add-form')
    end

    it 'opens on it when asked from the selection bar' do
      visit_together('SHOP-2', 'SHOP-3', mode: 'add')

      assert_shown('museum-add-form')
      assert_page_includes('data-panel="new" hidden')
    end

    it 'links the exhibit and comes back to the list where it left off' do
      visit_museum(type: 'Story')

      add_to_story('SHOP-2', to: 'Buy without an account', return_to: last_museum_path)

      assert_notice_shown
      assert_includes last_museum_path, 'type=Story'
      assert_equal 2, story_exhibits('Buy without an account')
      refute_includes museum_keys_shown, 'SHOP-2'
    end

    it 'sends back one exhibit from the toast, and the story stays' do
      add_to_story('SHOP-2', to: 'Buy without an account')

      press_toast_undo

      assert_notice_shown
      assert_equal 1, story_exhibits('Buy without an account')
      assert_map_shows('Buy without an account')
    end

    it 'sends back only what was added together from the toast' do
      add_to_story('SHOP-2', 'SHOP-3', to: 'Buy without an account')

      assert_equal 3, story_exhibits('Buy without an account')
      press_toast_undo

      assert_equal 1, story_exhibits('Buy without an account')
    end

    it 'adds in place, the list coming back with the toast' do
      visit_museum(type: 'Story')
      open_museum_case('SHOP-2', from: last_museum_path)

      add_to_story_in_place('SHOP-2', to: 'Buy without an account')

      refute_page_includes('<html')
      assert_shown('museum-toast-undo')
      assert_equal 2, story_exhibits('Buy without an account')
    end

    it 'selects the story Jira links to, and says why' do
      import_jira_csv(JiraExport.csv({ key: 'SHOP-5', id: '5', summary: 'Linked ticket', relates_to: 'SHOP-1' }))

      search_stories('', for_keys: ['SHOP-5'])

      assert_shown('museum-story-suggestion')
      assert_page_includes(%(value="#{museum_item('SHOP-1').story_id}" required checked))
    end

    it 'puts the story it suggests first, the reason above the list' do
      promote_museum_item('SHOP-3', title: 'Hide the password fields', task: @task)
      import_jira_csv(JiraExport.csv({ key: 'SHOP-5', id: '5', summary: 'Linked ticket', relates_to: 'SHOP-3' }))

      search_stories('', for_keys: ['SHOP-5'])

      assert_equal 'Hide the password fields', story_hits_shown.first
      assert_shown_before('museum-story-suggestion', 'museum-story-hit')
    end

    it 'suggests nothing for an exhibit with no such link' do
      search_stories('', for_keys: ['SHOP-2'])

      refute_page_includes('data-test-id="museum-story-suggestion"')
    end

    it 'says so when no story is chosen' do
      add_to_story('SHOP-2', to: nil)

      assert_error_shown
      assert_equal 1, story_exhibits('Buy without an account')
    end
  end

  describe 'the prompt to let go' do
    before do
      import_jira_csv(JiraExport.csv(*(10..21).map { |n| { key: "OLD-#{n}", id: n.to_s, summary: "Old ticket about thing #{n}" } }))
    end

    it 'leads from the list to the review' do
      let_the_curator_look
      visit_museum

      assert_page_includes('data-test-id="let-go-prompt" data-count="12"')
      follow_museum_link('let-go-review')

      assert_equal 5, let_go_keys('stale').size
    end

    it 'goes away after Not now, back on the same list' do
      let_the_curator_look
      visit_museum(type: 'Story')

      press_not_now

      assert_includes last_museum_path, 'type=Story'
      refute_page_includes('data-test-id="let-go-prompt"')
    end

    it 'watches for the curator right after an acquisition, and only then' do
      assert_shown('let-go-watching')

      visit_museum

      refute_page_includes('data-test-id="let-go-watching"')
    end

    it 'turns up while watching, once the curator has looked' do
      check_for_let_go_prompt(tries: 1)

      assert_shown('let-go-watching')
      let_the_curator_look
      check_for_let_go_prompt(tries: 2)

      assert_shown('let-go-prompt')
      refute_page_includes('data-test-id="let-go-watching"')
    end

    it 'stops watching after a while' do
      check_for_let_go_prompt(tries: 15)

      refute_page_includes('data-test-id="let-go-watching"')
    end
  end

  describe 'reading an exhibit in place' do
    before do
      import_jira_csv(JiraExport.csv(
        { key: 'SHOP-10', id: '10', summary: 'Guest checkout', description: "h2. Background\nCustomers abandon at the account step",
          comments: ['02/Jan/24 10:15 AM;alice;Blocked on the orders migration'], blocked_by: 'SHOP-14' },
        { key: 'SHOP-11', id: '11', type: 'Sub-task', parent: '10', summary: 'Store the guest email' },
        { key: 'SHOP-14', id: '14', summary: 'Guest token on orders', description: '' }
      ))
    end

    it "opens an exhibit's whole record: description, sub-tasks, links and comments" do
      open_museum_case('SHOP-10')

      assert_page_includes('data-test-id="museum-case" data-key="SHOP-10"')
      assert_page_includes('<h4 class="mu-md-h">Background</h4>')
      assert_page_includes('data-test-id="museum-case-sub-task" data-key="SHOP-11"')
      assert_page_includes('data-test-id="museum-case-link" data-key="SHOP-14"')
      assert_shown('museum-case-comment')
    end

    it 'says so when an exhibit has nothing but its summary, and not otherwise' do
      open_museum_case('SHOP-14')

      assert_shown('museum-relic-empty')
      open_museum_case('SHOP-10')

      refute_shown('museum-relic-empty')
    end

    it 'says so in an open case when there are no tasks to promote into, pointing at the maps' do
      open_museum_case('SHOP-10')

      assert_shown('museum-no-tasks')
      assert_shown('museum-add-task-link')
    end

    it 'says so on the list before the first promote is tried' do
      visit_museum

      assert_shown('museum-no-tasks')
    end

    it 'opens the exhibit named in the address, under its row' do
      visit_museum(open: 'SHOP-10')

      assert_page_includes('data-test-id="museum-case" data-key="SHOP-10"')
      refute_page_includes('data-test-id="museum-case" data-key="SHOP-14"')
    end

    it 'takes a linked ticket to its own case' do
      open_museum_case('SHOP-10')

      follow_museum_link('museum-case-link')

      assert_page_includes('data-test-id="museum-case" data-key="SHOP-14"')
    end
  end

  describe 'sending ticked exhibits to storage' do
    before do
      import_jira_csv(JiraExport.csv({ key: 'SHOP-1', id: '1' }, { key: 'SHOP-2', id: '2' }, { key: 'SHOP-3', id: '3', type: 'Bug' }))
    end

    it 'puts a tick box on each exhibit' do
      visit_museum

      assert_page_includes('data-test-id="museum-select" data-key="SHOP-1"')
    end

    it 'stores them together and comes back to the same view' do
      visit_museum(type: 'Story')

      send_museum_items_to_storage('SHOP-1', 'SHOP-3')

      assert_notice_shown
      assert_includes last_museum_path, 'type=Story'
      assert_equal ['SHOP-2'], museum_keys_shown
      visit_museum(status: 'in-storage')

      assert_equal %w[SHOP-1 SHOP-3], museum_keys_shown.sort
    end

    it 'brings them all back from the toast, on the same view' do
      visit_museum(type: 'Story')
      send_museum_items_to_storage('SHOP-1', 'SHOP-3')

      press_toast_undo

      assert_notice_shown
      assert_includes last_museum_path, 'type=Story'
      visit_museum

      assert_equal %w[SHOP-1 SHOP-2 SHOP-3], museum_keys_shown.sort
    end

    it "leaves promoted exhibits and other teams' exhibits alone" do
      create_map(name: 'Shop')
      task = create_task('Pay', under_activity: create_activity('Checkout', for_personas: [create_persona('Shopper')]))
      promote_museum_item('SHOP-1', title: 'Buy without an account', task: task)
      theirs = other_team_museum_item

      send_museum_items_to_storage('SHOP-1', 'SHOP-2', also: [theirs.id])

      visit_museum(status: 'in-storage')

      assert_equal ['SHOP-2'], museum_keys_shown
      assert_nil(BypassRLS.call { theirs.refresh.discarded_at })
    end

    it "brings nothing back for another team's batch" do
      theirs = other_team_museum_item
      batch = BypassRLS.call { DiscardMuseumItem.many(items: [theirs], actor: @_login_person.actor).batch }

      undo_storage_batch(batch)

      assert_error_shown
      refute_nil(BypassRLS.call { theirs.refresh.discarded_at })
    end

    it 'goes back only to a page in the museum' do
      send_museum_items_to_storage('SHOP-2', return_to: 'https://evil.example/museum')

      assert_equal "/teams/#{@team.id}/museum", last_museum_path
    end
  end

  describe 'discarding an item' do
    before do
      import_jira_csv(JiraExport.csv({ key: 'SHOP-31', id: '31' }, { key: 'SHOP-40', id: '40' }))
    end

    it 'takes the item off the list' do
      discard_museum_item('SHOP-31')

      assert_notice_shown
      assert_equal ['SHOP-40'], museum_keys_shown
    end

    it 'keeps it discarded when a newer export still has it' do
      discard_museum_item('SHOP-31')
      import_jira_csv(JiraExport.csv({ key: 'SHOP-31', id: '31' }, { key: 'SHOP-40', id: '40' }))

      assert_equal ['SHOP-40'], museum_keys_shown
    end

    it 'shows stored items on request, ready to restore' do
      discard_museum_item('SHOP-31')

      visit_museum(status: 'in-storage')

      assert_equal ['SHOP-31'], museum_keys_shown
      assert_page_includes('data-test-id="museum-restore" data-key="SHOP-31"')
      refute_page_includes('data-test-id="museum-promote" data-key="SHOP-31"')
    end

    it 'puts a restored item back on the list' do
      discard_museum_item('SHOP-31')

      restore_museum_item('SHOP-31')

      assert_notice_shown
      assert_equal %w[SHOP-31 SHOP-40], museum_keys_shown.sort
    end
  end
end
