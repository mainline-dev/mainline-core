# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/jira_export'

describe 'Ticket Museum promote form (browser)' do
  include MainlineDSL

  before do
    setup_team
    add_person(name: 'Alice')
    create_map(name: 'Shop')
    create_task('Pay', under_activity: create_activity('Checkout', for_personas: [create_persona('Shopper')]))
    import_jira_csv(JiraExport.csv({ key: 'SHOP-22', id: '22', summary: 'As a user I want to filter by price so that I save' }))
  end

  def open_promote_page
    use_browser!
    visit "/teams/#{@team.id}/museum/#{museum_item('SHOP-22').id}/promote"
  end

  def write_scenario(card, *parts)
    card.all('textarea').zip(parts).each { |box, text| box.set(text) }
  end

  def title_field
    find('[data-test-id="museum-promote-form"] input[name="title"]')
  end

  def promote_row(key)
    find(%([data-test-id="museum-promote"][data-key="#{key}"])).click

    assert_selector %([data-test-id="museum-case"][data-key="#{key}"])
  end

  def assert_draft_shown(task)
    assert_selector '[data-test-id="museum-scenario"]', count: 2
    assert_equal 'Shoppers can filter results by price', title_field.value
    assert_equal ['a filtered search', 'I share the link', 'the range is applied'],
      all('[data-test-id="museum-scenario"]')[1].all('textarea').map(&:value)
    assert_equal task.id, find('select[name="task_id"]').value
  end

  it "opens the form from a row's Promote, ready to type, and comes back to the list" do
    use_browser!
    visit "/teams/#{@team.id}/museum?type=Story"

    find('[data-test-id="museum-promote"][data-key="SHOP-22"]').click

    assert_selector '[data-test-id="museum-case"][data-key="SHOP-22"] [data-test-id="museum-promote-form"]'
    assert_current_path(/open=SHOP-22/, url: true)
    assert_equal 'title', evaluate_script('document.activeElement.name')

    title_field.set('Shoppers can filter results by price')
    find('[data-test-id="museum-promote-submit"]').click

    assert_selector '[data-test-id="flash-notice"]'
    assert_current_path(/type=Story/, url: true)
    refute_match(/open=/, current_url)
  end

  describe 'a half-written story in an open case' do
    before do
      import_jira_csv(JiraExport.csv({ key: 'SHOP-23', id: '23', summary: 'Sort by rating' }))
      @track = create_task('Track', under_activity: create_activity('After', for_personas: [create_persona('Buyer')]))
      use_browser!
      visit "/teams/#{@team.id}/museum"
    end

    it 'comes back after opening another exhibit, and after a reload' do
      promote_row('SHOP-22')
      title_field.set('Shoppers can filter results by price')
      find('[data-test-id="museum-add-scenario"]').click
      write_scenario(all('[data-test-id="museum-scenario"]')[1], 'a filtered search', 'I share the link', 'the range is applied')
      select 'After / Track', from: 'task_id'

      promote_row('SHOP-23')

      assert_equal '', title_field.value
      assert_selector '[data-test-id="museum-scenario"]', count: 1

      promote_row('SHOP-22')

      assert_draft_shown(@track)

      page.refresh

      assert_draft_shown(@track)
    end

    it 'keeps what the buttons did as well as what was typed' do
      promote_row('SHOP-22')
      find('[data-test-id="museum-fill-title"]').click
      find('[data-test-id="museum-add-scenario"]').click
      all('[data-test-id="museum-scenario"] [data-remove-scenario]').first.click

      promote_row('SHOP-23')
      promote_row('SHOP-22')

      assert_selector '[data-test-id="museum-case"][data-key="SHOP-22"]'
      assert_equal 'As a user I want to filter by price so that I save', title_field.value
      assert_selector '[data-test-id="museum-scenario"]', count: 1
    end

    it 'is forgotten once the story is promoted' do
      promote_row('SHOP-22')
      title_field.set('Shoppers can filter results by price')
      find('[data-test-id="museum-promote-submit"]').click

      assert_selector '[data-test-id="flash-notice"]'

      unpromote_museum_item('SHOP-22')
      visit "/teams/#{@team.id}/museum"
      promote_row('SHOP-22')

      assert_selector '[data-test-id="museum-case"][data-key="SHOP-22"]'
      assert_equal '', title_field.value
    end
  end

  it 'adds an exhibit to a story from its open case, and opens the next one' do
    import_jira_csv(JiraExport.csv({ key: 'SHOP-23', id: '23', summary: 'Sort by rating' },
      { key: 'SHOP-24', id: '24', summary: 'Sort by date' }))
    promote_museum_item('SHOP-22', title: 'Shoppers can filter results by price', task: Task.where(team_id: @team.id).first)
    use_browser!
    visit "/teams/#{@team.id}/museum"
    first, second = all('[data-test-id="museum-item"]').map { |row| row['data-key'] }
    promote_row(first)

    find('[data-test-id="museum-segment-add"]').click

    assert_equal 'q', evaluate_script('document.activeElement.name')
    find('[data-test-id="museum-story-hit"]').click
    find('[data-test-id="museum-add-submit"]').click

    assert_selector '[data-test-id="museum-toast-undo"]'
    assert_no_selector %([data-test-id="museum-item"][data-key="#{first}"])
    assert_selector %([data-test-id="museum-case"][data-key="#{second}"])
    assert_equal 2, story_exhibits('Shoppers can filter results by price')
  end

  it 'keeps the chosen story while the search changes' do
    task = Task.where(team_id: @team.id).first
    promote_museum_item('SHOP-22', title: 'Shoppers can filter results by price', task: task)
    import_jira_csv(JiraExport.csv({ key: 'SHOP-23', id: '23', summary: 'Sort by rating' }))
    use_browser!
    visit "/teams/#{@team.id}/museum"
    promote_row('SHOP-23')
    find('[data-test-id="museum-segment-add"]').click
    find('[data-test-id="museum-story-hit"]').click

    find('[data-test-id="museum-story-search"]').set('price')

    assert_selector '[data-test-id="museum-story-hit"] input:checked', visible: :all, wait: 5
    find('[data-test-id="museum-add-submit"]').click

    assert_selector '[data-test-id="museum-toast-undo"]'
  end

  it 'selects the story Jira links an exhibit to' do
    promote_museum_item('SHOP-22', title: 'Shoppers can filter results by price', task: Task.where(team_id: @team.id).first)
    import_jira_csv(JiraExport.csv({ key: 'SHOP-23', id: '23', summary: 'Sort by rating', relates_to: 'SHOP-22' }))
    use_browser!
    visit "/teams/#{@team.id}/museum"
    promote_row('SHOP-23')

    find('[data-test-id="museum-segment-add"]').click

    assert_selector '[data-test-id="museum-story-suggestion"]'
    find('[data-test-id="museum-add-submit"]').click

    assert_selector '[data-test-id="museum-toast-undo"]'
    assert_equal 2, story_exhibits('Shoppers can filter results by price')
  end

  describe 'promoting in place' do
    before do
      import_jira_csv(JiraExport.csv({ key: 'SHOP-23', id: '23', summary: 'Sort by rating' }))
      use_browser!
      visit "/teams/#{@team.id}/museum"
      @first, @second = all('[data-test-id="museum-item"]').map { |row| row['data-key'] }
      execute_script('window.stayed = true')
    end

    it 'stays on the page and opens the next exhibit ready to type' do
      promote_row(@first)
      title_field.set('Shoppers can filter results by price')
      find('[data-test-id="museum-promote-submit"]').click

      assert_selector '[data-test-id="museum-toast-undo"]'
      assert_no_selector %([data-test-id="museum-item"][data-key="#{@first}"])
      assert_selector %([data-test-id="museum-case"][data-key="#{@second}"] [data-test-id="museum-promote-form"])
      assert_current_path(/open=#{@second}/, url: true)
      assert_equal 'title', evaluate_script('document.activeElement.name')
      assert evaluate_script('window.stayed')
    end

    it 'shows a refusal and keeps what was written' do
      promote_row(@first)
      title_field.set('   ')
      write_scenario(find('[data-test-id="museum-scenario"]'), 'a filtered search', 'I share the link', 'the range is applied')
      find('[data-test-id="museum-promote-submit"]').click

      assert_selector '[data-test-id="flash-error"]'
      assert_selector %([data-test-id="museum-case"][data-key="#{@first}"])
      assert_equal 'a filtered search', find('[data-test-id="museum-scenario"] textarea', match: :first).value
      assert evaluate_script('window.stayed')
    end
  end

  # A toast that would go in 400ms instead of 8s, so holding it can be seen
  # without waiting 8s.
  def promote_with_a_short_toast
    use_browser!
    visit "/teams/#{@team.id}/museum"
    execute_script('window.museumToastDelay = 400')
    promote_row('SHOP-22')
    title_field.set('Shoppers can filter results by price')
    find('[data-test-id="museum-promote-submit"]').click
  end

  it 'holds the toast while hovered, then lets it go' do
    promote_with_a_short_toast

    find('[data-test-id="flash-notice"]').hover
    sleep 0.8

    assert_selector '[data-test-id="museum-toast-undo"]'

    find('[data-test-id="museum-filters"]').hover

    assert_no_selector '[data-test-id="flash-notice"]', wait: 5
  end

  it 'holds the toast while its Undo has focus, then lets it go' do
    promote_with_a_short_toast

    execute_script('document.querySelector(\'[data-test-id="museum-toast-undo"]\').focus()')
    sleep 0.8

    assert_selector '[data-test-id="museum-toast-undo"]'

    find('[data-test-id="museum-search"]').click

    assert_no_selector '[data-test-id="flash-notice"]', wait: 5
  end

  it 'counts the title once, leaving the generic counter to the scenario boxes' do
    open_promote_page

    title_field.click

    assert_no_selector 'input[name="title"] + .char-counter', visible: :all
    assert_selector 'textarea + .char-counter', visible: :all
  end

  it 'starts from the Jira summary when asked, counting the title' do
    open_promote_page

    find('[data-test-id="museum-fill-title"]').click

    assert_equal 'As a user I want to filter by price so that I save', title_field.value
    assert_selector '[data-counter][data-length="50"]'
  end

  it 'warns about ticket-speak and goes quiet once the title says what someone can do' do
    open_promote_page

    title_field.set('As a user I want to filter by price')

    assert_selector '[data-test-id="museum-hint"]'

    title_field.set('Shoppers can filter results by price')

    assert_no_selector '[data-test-id="museum-hint"]'
  end

  it 'leaves a title alone when a ticket is the thing someone gets' do
    open_promote_page
    title_field.set('Implement the price filter')

    assert_selector '[data-test-id="museum-hint"]'

    title_field.set('Fans can buy a ticket for the show')

    assert_no_selector '[data-test-id="museum-hint"]'
  end

  it 'adds and removes scenario cards, and the story gets the ones written' do
    open_promote_page
    title_field.set('Shoppers can filter results by price')

    find('[data-test-id="museum-add-scenario"]').click
    find('[data-test-id="museum-add-scenario"]').click

    assert_selector '[data-test-id="museum-scenario"]', count: 3
    all('[data-test-id="museum-scenario"] [data-remove-scenario]').first.click

    assert_selector '[data-test-id="museum-scenario"]', count: 2
    cards = all('[data-test-id="museum-scenario"]')
    write_scenario(cards[0], 'results from $20 to $300', 'I set $50 to $120', 'only $50 to $120 show')
    write_scenario(cards[1], 'a filtered search', 'I share the link', 'the range is applied')
    find('[data-test-id="museum-promote-form"] button[type="submit"]').click

    assert_selector '[data-test-id="flash-notice"]'
    assert_equal [['results from $20 to $300', 'I set $50 to $120', 'only $50 to $120 show'],
                  ['a filtered search', 'I share the link', 'the range is applied']],
      story_scenarios('Shoppers can filter results by price')
  end
end
