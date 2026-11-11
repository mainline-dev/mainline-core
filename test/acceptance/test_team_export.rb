# frozen_string_literal: true

require 'json_schemer'
require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/jira_export'

# A team can take everything it has in Mainline away with it: one zip, for any
# member to download, holding files a person, Jira and a coding agent can use.
describe 'Team export' do
  include MainlineDSL

  before do
    TEAM_EXPORT_RATE_LIMITER.reset
    MUSEUM_UPLOAD_RATE_LIMITER.reset
    setup_team(name: 'Checkout Crew')
    @alice = add_person(name: 'Alice', email: 'alice@example.com')
    create_map(name: 'Shop')
    @purchase = create_activity('Purchase', for_personas: [create_persona('Shopper')])
    @checkout = create_task('Checkout', under_activity: @purchase)
    @story = create_story('Guests can check out', under_task: @checkout)
    create_scenario(@story, name: 'A guest pays', given_text: 'I have no account', when_text: 'I pay',
      then_text: 'my order is placed')
  end

  it 'offers the download to any member of the team' do
    visit_export_page

    assert_shown('export-download')
  end

  it 'downloads one zip, named for the team and the day' do
    download = download_export

    assert_equal 200, download.status
    assert_equal 'application/zip', download['Content-Type']
    assert_match(/filename="mainline-checkout-crew-\d{4}-\d{2}-\d{2}\.zip"/, download['Content-Disposition'])
    assert_includes exported_files.keys, 'README.md'
    assert_includes exported_files.keys, 'export.json'
  end

  it "keeps a team name's odd characters out of the file name" do
    @team.update(name: "bad\r\nname\"here")

    assert_match(/filename="mainline-bad-name-here-\d{4}-\d{2}-\d{2}\.zip"/, download_export['Content-Disposition'])
  end

  it 'lets the account holder who is not working on the team download it too' do
    holder = Person.create(name: 'Buyer', email: 'buyer@corp.co')
    TeamMembership.create(team_id: @team.id, person_id: holder.id, working: false)
    @team.update(creator_id: holder.id)
    login_as(holder)

    assert_equal 200, download_export.status
  end

  it 'explains every file in the zip in its README' do
    readme = exported_files.fetch('README.md')

    exported_files.each_key { |name| assert_includes readme, name.split('/').first }
  end

  it 'holds the full record in export.json, under a format version, passing the published schema' do
    record = JSON.parse(exported_files.fetch('export.json'))
    schema = JSONSchemer.schema(JSON.parse(File.read(File.expand_path('../../public/schemas/export-1.json', __dir__))))

    assert_equal 1, record['format_version']
    assert_empty(schema.validate(record).map { |error| [error['data_pointer'], error['type']] })
    assert_equal(['Shop'], record['maps'].map { |map| map['name'] })
    assert_equal(['Checkout'], record['steps'].map { |step| step['name'] })
    assert_equal([['A guest pays']], record['stories'].map { |story| story['scenarios'].map { |scenario| scenario['name'] } })
    refute_empty record['events']
  end

  describe 'for a coding agent' do
    before do
      @payment = create_task('Payment', under_activity: @purchase)
      @first = create_release_slice('First release')
      @later = create_release_slice('Later')
      @receipt = create_story('Shoppers get a receipt', under_task: @payment)
      @wishlist = create_story('Shoppers keep a wishlist', under_task: @checkout)
      move_story_to_slice(@receipt, release_slice_id: @first.id)
      move_story_to_slice(@story, release_slice_id: @first.id)
      move_story_to_slice(@wishlist, release_slice_id: @later.id)
    end

    it 'lists every story in stories.md in map order: slice by slice, then left to right' do
      assert_equal({ 'First release' => ['Guests can check out', 'Shoppers get a receipt'],
                     'Later'         => ['Shoppers keep a wishlist'] }, stories_listed)
    end

    it 'gives each line the story ID and status' do
      line = story_line('Guests can check out')

      assert_includes line, @story.id
      assert_includes line, 'planned'
    end

    it 'gives a story with scenarios the feature file its own download gives, linked from its line' do
      path = "features/#{@story.id}-guests-can-check-out.feature"

      assert_equal download_feature_file(@story).body, exported_files.fetch(path)
      assert_includes story_line('Guests can check out'), "(#{path})"
    end

    it 'lists a story with no scenarios without a feature file, and says so' do
      assert_equal ["features/#{@story.id}-guests-can-check-out.feature"], exported_files.keys.grep(%r{\Afeatures/})
      refute_includes story_line('Shoppers keep a wishlist'), 'features/'
      assert_includes story_line('Shoppers keep a wishlist'), 'no scenarios yet'
    end

    it 'leaves a story that was archived off the list' do
      archive_story(@wishlist)

      assert_equal ['First release'], stories_listed.keys
    end

    it 'lists a story that has no release slice under a heading of its own, first' do
      create_story('Shoppers see the total', under_task: @checkout)

      assert_equal ['Shoppers see the total'], stories_listed.values.first
      assert_equal 3, stories_listed.size
    end
  end

  describe "for Jira's CSV importer" do
    it 'writes stories.csv with a row for each story in map order, under columns the importer can be told about' do
      create_story('Shoppers keep a wishlist', under_task: @checkout)

      assert_equal ['Summary', 'Issue Type', 'Description', 'Status', 'Labels', 'Labels', 'Mainline ID', 'Original Jira Key'],
        exported_csv_headers('stories.csv')
      assert_equal(['Guests can check out', 'Shoppers keep a wishlist'], exported_csv('stories.csv').map { |row| row['Summary'] })
    end

    it "gives each row the story's ID, its place on the map as labels, and the type Story" do
      row = exported_csv('stories.csv').first

      assert_equal [@story.id, 'Story', %w[Purchase Checkout]], row.values_at('Mainline ID', 'Issue Type', 'Labels')
    end

    it 'writes the scenarios into the description as plain text' do
      assert_equal "Scenario: A guest pays\nGiven I have no account\nWhen I pay\nThen my order is placed",
        exported_csv('stories.csv').first['Description']
    end

    it "says how far each story has got in Jira's own words" do
      started = create_story('Started', under_task: @checkout)
      finished = create_story('Finished', under_task: @checkout)
      assign_person(finished, person: @alice)
      deploy_story(finished)
      release_story(finished)
      assign_person(started, person: @alice)

      assert_equal({ 'Guests can check out' => 'To Do', 'Started' => 'In Progress', 'Finished' => 'Done' },
        exported_csv('stories.csv').to_h { |row| row.values_at('Summary', 'Status') })
    end

    it 'joins the words of a name to make a label, since a Jira label cannot hold a space' do
      account = create_activity('Manage account', for_personas: [driver.persona_named(@map, 'Shopper')])
      create_story('Change my address', under_task: create_task('Address book', under_activity: account))

      assert_equal %w[Manage-account Address-book], exported_csv('stories.csv').last['Labels']
    end

    it 'carries the key of the Jira ticket a story was promoted from, in a column Jira does not take for its own key' do
      import_jira_csv(JiraExport.csv({ key: 'SHOP-7', summary: 'Postcode lookup' }))
      promote_museum_item('SHOP-7', title: 'Shoppers find their address by postcode', task: @checkout)

      assert_equal({ 'Guests can check out' => '', 'Shoppers find their address by postcode' => 'SHOP-7' },
        exported_csv('stories.csv').to_h { |row| row.values_at('Summary', 'Original Jira Key') })
      assert_empty(exported_csv_headers('stories.csv').grep(/\A(issue|work item) ?key\z/i))
    end

    it 'keeps a cell that begins like a formula from being run by a spreadsheet' do
      ['=1+1', '+1', '-1', '@SUM(A1)'].each { |title| create_story(title, under_task: @checkout) }

      assert_equal ["'=1+1", "'+1", "'-1", "'@SUM(A1)"], exported_csv('stories.csv').map { |row| row['Summary'] }.last(4)
    end

    it 'lists every exhibit in museum.csv as the museum keeps it, with the story it was promoted to' do
      import_jira_csv(JiraExport.csv({ key: 'SHOP-7', summary: 'Postcode lookup', labels: %w[checkout] },
        { key: 'SHOP-8', summary: 'Dark mode', description: 'As a user, I want "dark" mode' }))
      promote_museum_item('SHOP-7', title: 'Shoppers find their address by postcode', task: @checkout)
      promoted = driver.story_under(@checkout, 'Shoppers find their address by postcode')

      rows = exported_csv('museum.csv')

      assert_equal(%w[SHOP-7 SHOP-8], rows.map { |row| row['Key'] })
      assert_equal([promoted.id, ''], rows.map { |row| row['Promoted To'] })
      assert_equal ['Postcode lookup', 'Story', 'checkout'], rows.first.values_at('Summary', 'Type', 'Labels')
      assert_equal 'As a user, I want "dark" mode', rows.last['Description']
    end
  end

  describe 'taking the stories to another team' do
    it "brings the exported stories.csv into that team's museum with every title and description as it was" do
      titles = ['Shoppers pay, then "confirm" the order', 'Les clientes reçoivent un reçu, 領収書', 'Shoppers see 🎉 when the order lands']
      import_jira_csv(JiraExport.csv({ key: 'SHOP-1' }, { key: 'SHOP-2' }, { key: 'SHOP-3' }))
      titles.each_with_index do |title, at|
        promote_museum_item("SHOP-#{at + 1}", title: title, task: @checkout,
          scenarios: [['I have "two" items, one saved', 'I pay för allt', 'I see a reçu 🎉, and a "thank you"', "Case #{at + 1}"],
                      ['the order is placed', 'I open it', 'I see what I bought', 'The order shows its items']])
      end
      rows = exported_csv('stories.csv').to_h { |row| row.values_at('Summary', 'Description') }

      move_to_a_new_team
      import_jira_csv(exported_files.fetch('stories.csv'))

      assert_equal ['Guests can check out', *titles].sort, rows.keys.sort
      assert_includes rows.fetch(titles.first),
        %(Given I have "two" items, one saved\nWhen I pay för allt\nThen I see a reçu 🎉, and a "thank you")
      assert_equal rows, museum_summaries_and_descriptions
    end
  end

  describe 'the record of who exported' do
    it 'records each export as an event: who and when' do
      download_export

      event = assert_event_recorded(entity: @team, action: 'exported')

      assert_equal @alice.actor_id, event.actor_id
    end

    it 'shows the last few exports on the page, newest first, with who made each' do
      bob = add_person(name: 'Bob')
      download_export
      login_as(bob)
      download_export

      visit_export_page

      assert_equal %w[Bob Alice], recent_exports_shown
    end

    it 'shows no more than the last five' do
      6.times { download_export }

      visit_export_page

      assert_equal 5, recent_exports_shown.size
    end

    it 'records nothing when the download is refused' do
      login_as(other_team_member)
      download_export

      assert_empty driver.events_of(@team, action: 'exported')
    end
  end

  it 'stops a team that has exported too often for now, without holding up another team' do
    refused = (1..50).find { download_export.status != 200 }
    theirs = other_team_member

    login_as(theirs)

    refute_nil refused, 'the team was never stopped'
    refute_equal 'application/zip', download_export['Content-Type']
    assert_equal 200, download_export(driver.team_of(theirs)).status
  end

  it 'names people by their display names only' do
    everything = exported_files.values.join

    assert_includes everything, 'Alice'
    refute_includes everything, 'alice@example.com'
  end

  it 'gives a member of another team nothing' do
    download_export
    outsider = other_team_member

    login_as(outsider)
    download = download_export

    assert_equal 403, download.status
    refute_equal 'application/zip', download['Content-Type']
  end

  it 'sends the old export address on to the export page' do
    holder = Person.create(name: 'Buyer', email: 'buyer@corp.co')
    TeamMembership.create(team_id: @team.id, person_id: holder.id, working: false)
    @team.update(creator_id: holder.id)
    login_as(holder)

    assert_equal "/teams/#{@team.id}/export", old_export_address_leads_to
  end
end
