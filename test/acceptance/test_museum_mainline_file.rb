# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/mainline_file'
require_relative '../dsl/jira_export'

# Stories proposed from a specification arrive the way Jira tickets do: staged
# and previewed first, then exhibits a person promotes one at a time.
describe 'Ticket Museum - a Mainline file' do
  include MainlineDSL

  before do
    MUSEUM_UPLOAD_RATE_LIMITER.reset
    setup_team
    add_person(name: 'Alice')
  end

  def scenario(**parts)
    { name: 'Both changes are kept', given: 'two people have an item open', when: 'each changes a different field',
      then: 'the item shows both changes' }.merge(parts).compact
  end

  it 'stages a file and shows what acquiring it would add, changing nothing yet' do
    upload_mainline_file(MainlineFileFixture.json({ key: 'RB-1' }, { key: 'RB-SAVE-02', draft_scenarios: [scenario] }))

    assert_shown('museum-import-preview')
    assert_equal({ 'added' => 2 }, museum_ledger_shown)

    visit_museum

    assert_empty museum_keys_shown
  end

  it 'refuses a file that does not fit the schema, naming every problem and which entry has it' do
    upload_mainline_file(MainlineFileFixture.json({ key: 'RB-1', title: nil }, { key: 'RB-2', title: 'x' * 201 },
      { key: 'RB-3', draft_scenarios: [scenario, scenario(then: nil)] }))

    refute_shown('museum-import-preview')
    assert_equal [%w[RB-1 title missing], %w[RB-2 title too_long], ['RB-3', 'scenario 2 then', 'missing']],
      file_problems_shown
    assert_shown('museum-file-problems-copy')
  end

  it 'refuses a file that is not JSON' do
    upload_mainline_file('Summary,Issue key')

    refute_shown('museum-import-preview')
    assert_equal [['', 'file', 'not_json']], file_problems_shown
  end

  it 'refuses a file saved with its code fence, and says that is what is wrong' do
    upload_mainline_file("```json\n#{MainlineFileFixture.json({ key: 'RB-1' })}\n```")

    refute_shown('museum-import-preview')
    assert_equal [['', 'file', 'fenced']], file_problems_shown
  end

  it 'refuses a file from a version it does not know' do
    upload_mainline_file(JSON.generate(mainline: 2, entries: [MainlineFileFixture::ENTRY]))

    assert_equal [['', 'mainline', 'wrong_value']], file_problems_shown
  end

  it 'refuses a file that uses a key twice' do
    upload_mainline_file(MainlineFileFixture.json({ key: 'RB-1' }, { key: 'RB-2' }, { key: 'RB-1' }))

    assert_equal [%w[RB-1 key repeated]], file_problems_shown
  end

  it 'refuses a file with more entries than a project should start with' do
    upload_mainline_file(MainlineFileFixture.json(*(1..201).map { |n| { key: "RB-#{n}" } }))

    assert_equal [['', 'entries', 'too_many']], file_problems_shown
  end

  it 'refuses a file whose key is already an exhibit from somewhere else' do
    import_jira_csv(JiraExport.csv({ key: 'SHOP-1' }))

    upload_mainline_file(MainlineFileFixture.json({ key: 'SHOP-1' }, { key: 'RB-2' }))

    refute_shown('museum-import-preview')
    assert_equal [%w[SHOP-1 key taken]], file_problems_shown
  end

  describe 'once acquired' do
    it 'puts each entry on display as an exhibit marked as proposed, not as a ticket' do
      import_jira_csv(JiraExport.csv({ key: 'SHOP-1' }))
      import_mainline_file(MainlineFileFixture.json({ key: 'RB-1' }, { key: 'RB-2' }))

      assert_notice_shown
      assert_equal({ 'RB-1' => 'mainline', 'RB-2' => 'mainline', 'SHOP-1' => 'jira' }, museum_sources_shown)
      assert_equal %w[RB-1 RB-2], museum_keys_marked_proposed
    end

    it 'shows where an entry came from, and why, when it is opened' do
      import_mainline_file(MainlineFileFixture.json({ key: 'RB-1', source: 'Research report, section 3',
                                                      why: 'Jira silently keeps the last save.' }))

      open_museum_case('RB-1')

      assert_shown('museum-origin')
      assert_page_includes('Research report, section 3')
      assert_page_includes('Jira silently keeps the last save.')
    end

    it 'shows no origin on a Jira ticket' do
      import_jira_csv(JiraExport.csv({ key: 'SHOP-1' }))

      open_museum_case('SHOP-1')

      refute_shown('museum-origin')
    end

    it 'refreshes entries by key when a revised file is acquired, adding none twice' do
      import_mainline_file(MainlineFileFixture.json({ key: 'RB-1', title: 'First wording' }))
      import_mainline_file(MainlineFileFixture.json({ key: 'RB-1', title: 'Second wording' }, { key: 'RB-2' }))

      assert_equal %w[RB-1 RB-2], museum_keys_shown.sort
      assert_page_includes('Second wording')
      refute_page_includes('First wording')
    end

    it 'offers the source as a filter once the museum holds exhibits from more than one' do
      import_jira_csv(JiraExport.csv({ key: 'SHOP-1' }))
      visit_museum

      refute_shown('museum-filter-source')

      import_mainline_file(MainlineFileFixture.json({ key: 'RB-1' }))

      assert_shown('museum-filter-source')
    end

    it 'narrows the museum to the exhibits from one source' do
      import_jira_csv(JiraExport.csv({ key: 'SHOP-1' }))
      import_mainline_file(MainlineFileFixture.json({ key: 'RB-1' }, { key: 'RB-2' }))

      visit_museum(source: 'mainline')

      assert_equal %w[RB-1 RB-2], museum_keys_shown.sort

      visit_museum(source: 'jira')

      assert_equal %w[SHOP-1], museum_keys_shown
    end

    it 'takes its exhibits out again when the acquisition is returned' do
      import_mainline_file(MainlineFileFixture.json({ key: 'RB-1' }, { key: 'RB-2' }))

      undo_last_museum_import
      visit_museum

      assert_empty museum_keys_shown
    end
  end

  describe 'promoting a proposed exhibit' do
    before do
      create_map(name: 'RepoBoard')
      track = create_activity('Track work', for_personas: [create_persona('Team member')])
      @find = create_task('Find an item', under_activity: track)
      @change = create_task('Change an item', under_activity: track)
    end

    def proposed(**entry)
      MainlineFileFixture.json({ key: 'RB-1', title: 'Two people change the same item',
                                 suggested: { activity: 'track work', step: 'Change an item' },
                                 draft_scenarios: [scenario, scenario(name: 'Same field', then: 'the later change wins')] }
                                 .merge(entry))
    end

    it 'opens the form with the suggested title, step and draft scenarios filled in' do
      import_mainline_file(proposed)

      visit_museum_promote('RB-1')

      form = promote_form_shown

      assert_equal ['Two people change the same item', @change.id], form.values_at(:title, :task_id)
      assert_equal [['Both changes are kept', 'two people have an item open', 'each changes a different field',
                     'the item shows both changes'],
                    ['Same field', 'two people have an item open', 'each changes a different field',
                     'the later change wins']], form[:scenarios]
      assert_shown('museum-drafted-note')
    end

    it 'starts on the title written out, so the title the file suggests is kept' do
      import_mainline_file(proposed)

      visit_museum_promote('RB-1')

      assert_equal 'written', promote_title_shown[:template]
      assert_equal 'Two people change the same item', promote_form_shown[:title]
    end

    it 'fills the form in the same way when the exhibit is opened in place' do
      import_mainline_file(proposed)

      open_museum_case('RB-1')

      assert_equal ['Two people change the same item', @change.id], promote_form_shown.values_at(:title, :task_id)
    end

    it 'makes nothing a story or a scenario until a person promotes' do
      import_mainline_file(proposed)
      visit_museum_promote('RB-1')

      assert_nil story_titled('Two people change the same item')

      promote_museum_item('RB-1', title: 'Two people change the same item', task: @change,
        scenarios: [['two people have an item open', 'each changes a different field', 'the item shows both changes']])

      assert_equal 1, story_scenarios('Two people change the same item').size
    end

    it 'asks for a step when the suggested one is not on the map' do
      import_mainline_file(proposed(suggested: { activity: 'Track work', step: 'Archive an item' }))

      visit_museum_promote('RB-1')

      assert_nil promote_form_shown[:task_id]
    end

    it "leaves a Jira ticket's form as it was: nothing filled in" do
      import_jira_csv(JiraExport.csv({ key: 'SHOP-1' }))

      visit_museum_promote('SHOP-1')

      assert_equal ['', [['', '', '', '']]], promote_form_shown.values_at(:title, :scenarios)
      refute_shown('museum-drafted-note')
    end
  end

  describe 'a file that proposes a backbone' do
    def with_backbone(*entries, **top)
      MainlineFileFixture.json(*entries, map: 'RepoBoard', personas: ['Team member', 'Admin'],
        activities: [{ name: 'Track work', personas: ['Team member'], steps: ['Find an item', 'Change an item'] },
                     { name: 'Run the board', personas: %w[Admin], steps: ['Invite people'] }], **top)
    end

    it 'shows it in the preview, for a new map, with everything ticked' do
      upload_mainline_file(with_backbone({ key: 'RB-1' }))

      backbone = backbone_shown

      assert_equal 'new', backbone[:map]
      assert_equal({ 'Track work'    => ['ticked', { 'Find an item' => 'ticked', 'Change an item' => 'ticked' }],
                     'Run the board' => ['ticked', { 'Invite people' => 'ticked' }] }, backbone[:activities])
    end

    it 'offers a map the team already has, with what is there marked and the rest unticked' do
      create_map(name: 'repoboard')
      track = create_activity('Track work', for_personas: [create_persona('Team member')])
      create_task('Find an item', under_activity: track)

      upload_mainline_file(with_backbone({ key: 'RB-1' }))

      backbone = backbone_shown

      assert_equal @map.id, backbone[:map]
      assert_equal({ 'Track work'    => ['there', { 'Find an item' => 'there', 'Change an item' => 'unticked' }],
                     'Run the board' => ['unticked', { 'Invite people' => 'unticked' }] }, backbone[:activities])
    end

    it 'says how many entries suggest a place the backbone and the map do not have' do
      upload_mainline_file(with_backbone({ key: 'RB-1', suggested: { activity: 'Track work', step: 'Change an item' } },
        { key: 'RB-2', suggested: { activity: 'Track work', step: 'Archive an item' } }, { key: 'RB-3' }))

      assert_equal 1, backbone_shown[:unplaced]
    end

    it 'creates the new map and everything ticked when the file is acquired' do
      import_mainline_file(with_backbone({ key: 'RB-1', suggested: { activity: 'Track work', step: 'Change an item' } }))

      assert_equal({ personas:   ['Admin', 'Team member'],
                     activities: { 'Track work' => ['Find an item', 'Change an item'], 'Run the board' => ['Invite people'] } },
        map_laid_out('RepoBoard'))

      visit_museum_promote('RB-1')

      assert_equal step_named('RepoBoard', 'Change an item').id, promote_form_shown[:task_id]
    end

    it 'records what it lays out as the work of the person who acquired the file' do
      import_mainline_file(with_backbone({ key: 'RB-1' }))

      event = assert_event_recorded(entity: step_named('RepoBoard', 'Find an item'), action: 'created')

      assert_equal @_login_person.actor_id, event.actor_id
    end

    it 'creates only what is ticked, with the personas those activities are for' do
      upload_mainline_file(with_backbone({ key: 'RB-1' }))
      apply_museum_import(tick: { activities: ['Track work'], steps: ['Find an item'] })

      assert_equal({ personas: ['Team member'], activities: { 'Track work' => ['Find an item'] } }, map_laid_out('RepoBoard'))
      assert_equal %w[RB-1], museum_keys_shown
    end

    it 'makes no map when nothing is ticked, and still acquires the exhibits' do
      upload_mainline_file(with_backbone({ key: 'RB-1' }))
      apply_museum_import(tick: { activities: [], steps: ['Invite people'] })

      assert_nil map_laid_out('RepoBoard')
      assert_equal %w[RB-1], museum_keys_shown
    end

    it 'adds only what is ticked to a map the team already has' do
      create_map(name: 'RepoBoard')
      track = create_activity('Track work', for_personas: [create_persona('Team member')])
      create_task('Find an item', under_activity: track)
      upload_mainline_file(with_backbone({ key: 'RB-1' }))

      apply_museum_import(tick: { activities: [], steps: ['Change an item'] })

      assert_equal({ personas: ['Team member'], activities: { 'Track work' => ['Find an item', 'Change an item'] } },
        map_laid_out('RepoBoard'))
    end

    it 'lays it out on another of the team\'s maps when that one is chosen' do
      create_map(name: 'Other')
      upload_mainline_file(with_backbone({ key: 'RB-1' }))

      apply_museum_import(onto: @map.id)

      assert_nil map_laid_out('RepoBoard')
      assert_equal ['Track work', 'Run the board'], map_laid_out('Other')[:activities].keys
    end

    it "lays nothing out on another team's map, and acquires nothing" do
      theirs = other_team_map
      upload_mainline_file(with_backbone({ key: 'RB-1' }))

      apply_museum_import(onto: theirs.id)

      assert_error_shown
      assert_empty museum_keys_shown
      assert_equal 0, activities_on(theirs)
    end

    it 'leaves the backbone in place when the acquisition is returned' do
      import_mainline_file(with_backbone({ key: 'RB-1' }))

      undo_last_museum_import
      visit_museum

      assert_empty museum_keys_shown
      assert_equal ['Track work', 'Run the board'], map_laid_out('RepoBoard')[:activities].keys
    end

    it 'shows no backbone for a file that proposes none' do
      upload_mainline_file(MainlineFileFixture.json({ key: 'RB-1' }))

      refute_shown('museum-backbone')
    end

    it 'refuses a file whose activity is for a persona it does not list' do
      upload_mainline_file(with_backbone({ key: 'RB-1' }, personas: ['Admin']))

      assert_equal [['', 'activity 1 personas', 'not_listed']], file_problems_shown
    end

    it 'refuses a backbone that names no map' do
      upload_mainline_file(with_backbone({ key: 'RB-1' }, map: nil))

      assert_equal [['', 'map', 'missing']], file_problems_shown
    end
  end

  describe 'the acquire page' do
    before do
      create_map(name: 'RepoBoard')
      track = create_activity('Track work', for_personas: [create_persona('Team member')])
      create_task('Change an item', under_activity: track)
    end

    it 'offers Jira and a Mainline file as sources, starting on Jira with how to export from it' do
      visit_museum_import_page

      assert_equal({ offered: %w[jira mainline], chosen: 'jira', sends: 'jira' }, acquire_sources_shown)
      assert_shown('museum-import-guide')
      refute_shown('museum-instructions')
    end

    it "for a Mainline file, gives instructions to copy for a model, naming the team's steps" do
      visit_museum_import_page(source: 'mainline')

      assert_equal({ offered: %w[jira mainline], chosen: 'mainline', sends: 'mainline' }, acquire_sources_shown)
      assert_shown('museum-instructions')
      assert_includes instructions_to_copy, 'Track work: Change an item'
      refute_shown('museum-import-guide')
    end

    it 'links to the guide beside the Mainline file source, and not beside a Jira export' do
      visit_museum_import_page(source: 'mainline')

      assert_page_includes('data-test-id="museum-how-it-works" href="https://mainline.dev/docs/spec-to-map"')
      visit_museum_import_page

      refute_shown('museum-how-it-works')
    end

    it 'takes a .json file dropped anywhere as a Mainline file without being told' do
      drop_file_on_museum(MainlineFileFixture.json({ key: 'RB-1' }), named: 'stories.json')

      assert_shown('museum-import-preview')
      assert_equal({ 'added' => 1 }, museum_ledger_shown)
    end

    it 'stays on the Mainline file source when a file is refused' do
      upload_mainline_file('not json')

      assert_equal 'mainline', acquire_sources_shown[:chosen]
    end
  end

  it 'still takes a Jira export as before' do
    import_jira_csv(JiraExport.csv({ key: 'SHOP-1' }))

    assert_equal %w[SHOP-1], museum_keys_shown
  end
end
