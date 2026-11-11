# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/import_to_museum'
require_relative '../dsl/jira_export'

describe ImportToMuseum do
  cover 'ImportToMuseum*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
  end

  def jira_csv(*issues, headers: JiraExport::HEADERS, col_sep: ',')
    JiraExport.csv(*issues, headers: headers, col_sep: col_sep)
  end

  def with_header(from, to)
    JiraExport::HEADERS.map { |header| header == from ? to : header }
  end

  def stage(csv, file_name: 'jira.csv')
    ImportToMuseum.stage(team: @team, actor: @person.actor, csv: csv, file_name: file_name)
  end

  # Stages the file and applies it, as someone pressing Import would.
  def import(csv)
    staged = stage(csv)
    return staged unless staged.success?

    ImportToMuseum.apply(import: staged.import, actor: @person.actor)
  end

  def item(key)
    MuseumItem.where(source_key: key).first
  end

  it 'stages a file without changing the museum' do
    staged = stage(jira_csv({}), file_name: 'shop.csv')

    assert_predicate staged, :success?
    assert_equal ['staged', 'shop.csv'], [staged.import.status, staged.import.file_name]
    assert_equal 0, MuseumItem.count
  end

  it 'previews what importing would do' do
    import(jira_csv({ key: 'SHOP-1' }))

    staged = stage(jira_csv({ key: 'SHOP-1', summary: 'Renamed' }, { key: 'SHOP-2' }, { key: 'SHOP-3', resolution: 'Done' },
      { key: 'SHOP-4', summary: '' }))
    preview = ImportToMuseum.preview(staged.import)

    assert_equal [1, 1, 1, 1], [preview.added, preview.updated, preview.finished, preview.skipped]
    assert_equal 'Search by postcode', item('SHOP-1').summary
  end

  it 'names each row it cannot keep, with the reason and the row as it was' do
    staged = stage(jira_csv({ key: 'SHOP-1' }, { key: 'SHOP-2', summary: '' }, { key: 'n/a' }))

    problems = staged.import.problems.map { |problem| [problem['row'], problem['reason'], problem['cells'][1]] }

    assert_equal [[3, 'no_summary', 'SHOP-2'], [4, 'not_a_key', 'n/a']], problems
    assert_equal JiraExport::HEADERS, staged.import.header.to_a
  end

  it 'imports a staged file once' do
    staged = stage(jira_csv({}))

    assert_predicate ImportToMuseum.apply(import: staged.import, actor: @person.actor), :success?
    refute_predicate ImportToMuseum.apply(import: staged.import, actor: @person.actor), :success?
    assert_equal 1, MuseumItem.count
  end

  it "turns down a file still waiting when another comes in, leaving other teams' files alone" do
    first = stage(jira_csv({ key: 'SHOP-1' })).import
    other = Team.create(name: 'Other')
    theirs = BypassRLS.call {
      ImportToMuseum.stage(team: other, actor: @person.actor, csv: jira_csv({ key: 'THEM-1' }), file_name: 'x.csv').import
    }

    second = stage(jira_csv({ key: 'SHOP-2' })).import

    assert_equal %w[cancelled staged], [first.refresh.status, second.refresh.status]
    assert_nil first.items
    assert_equal('staged', BypassRLS.call { theirs.refresh.status })
  end

  it 'cancels a staged file, leaving the museum as it was' do
    staged = stage(jira_csv({}))

    assert_predicate ImportToMuseum.cancel(import: staged.import), :success?
    refute_predicate ImportToMuseum.apply(import: staged.import, actor: @person.actor), :success?
    assert_equal ['cancelled', 0], [staged.import.refresh.status, MuseumItem.count]
  end

  it 'records who imported, when, and what it did' do
    staged = stage(jira_csv({ key: 'SHOP-1' }, { key: 'SHOP-2', resolution: 'Done' }))
    ImportToMuseum.apply(import: staged.import, actor: @person.actor)
    record = staged.import.refresh
    event = Event.where(entity_id: record.id, action: 'imported').first

    assert_equal ['imported', @person.actor_id, 1, 1], [record.status, record.actor_id, record.added, record.finished]
    assert record.imported_at
    assert_equal [@person.actor_id, 'museum_import', 1], [event.actor_id, event.entity_type, event.after_state['added']]
  end

  def undo(import)
    ImportToMuseum.undo(import: import, actor: @person.actor)
  end

  def latest_import
    MuseumImport.where(team_id: @team.id).exclude(imported_at: nil).order(:imported_at).last
  end

  it 'undoes an import, removing what it added and putting back what it refreshed' do
    import(jira_csv({ key: 'SHOP-1', summary: 'First', labels: ['old'], updated: '01/Feb/24 9:00 AM' }))
    import(jira_csv({ key: 'SHOP-1', summary: 'Second', labels: ['new'], updated: '01/Mar/24 9:00 AM' }, { key: 'SHOP-2' }))

    result = undo(latest_import)

    assert_predicate result, :success?
    assert_equal [1, 1, 0], [result.removed, result.restored, result.kept]
    assert_nil item('SHOP-2')
    assert_equal ['First', ['old'], Time.utc(2024, 2, 1, 9)],
      [item('SHOP-1').summary, item('SHOP-1').labels.to_a, item('SHOP-1').source_updated_at]
    assert_equal 'undone', latest_import.status
  end

  it 'keeps items promoted or discarded since the import' do
    import(jira_csv({ key: 'SHOP-1', summary: 'First' }))
    import(jira_csv({ key: 'SHOP-1', summary: 'Second' }, { key: 'SHOP-2' }))
    item('SHOP-1').update(discarded_at: Time.now)
    task = create_task
    story = Story.create(task_id: task.id, map_id: task.map_id, team_id: @team.id, title: 'Promoted', position: 1000,
      created_by_id: @person.id)
    item('SHOP-2').update(story_id: story.id, promoted_at: Time.now)

    result = undo(latest_import)

    assert_equal [0, 0, 2], [result.removed, result.restored, result.kept]
    assert_equal 'Second', item('SHOP-1').summary
    assert item('SHOP-2')
  end

  it 'undoes only the most recent import, once; an earlier one is final once another is acquired' do
    import(jira_csv({ key: 'SHOP-1' }))
    first = latest_import
    import(jira_csv({ key: 'SHOP-2' }))
    second = latest_import

    refute_predicate undo(first), :success?
    assert_predicate undo(second), :success?
    refute_predicate undo(second), :success?
    refute_predicate undo(first), :success?
    refute ImportToMuseum.undoable?(first.refresh)
    assert_nil ImportToMuseum.undoable_id(@team.id)
    assert_equal ['SHOP-1'], MuseumItem.select_map(:source_key)
  end

  it 'refuses to undo an upload that was never imported' do
    staged = stage(jira_csv({}))

    refute_predicate undo(staged.import), :success?
  end

  it 'records who undid an import' do
    import(jira_csv({ key: 'SHOP-1' }))
    undo(latest_import)

    event = Event.where(entity_id: latest_import.id, action: 'undone').first

    assert_equal [@person.actor_id, 1], [event.actor_id, event.after_state['removed']]
  end

  it 'puts an open issue in the museum' do
    result = import(jira_csv({}))

    assert_predicate result, :success?
    assert_equal 1, result.added
    museum_item = item('SHOP-1')

    assert_equal ['Story', 'Search by postcode', 'As a shopper', false],
      [museum_item.issue_type, museum_item.summary, museum_item.description, museum_item.in_progress]
    assert_equal Time.utc(2024, 1, 2, 10, 15), museum_item.source_created_at
    assert_nil museum_item.story_id
  end

  it 'leaves finished issues out' do
    result = import(jira_csv({ key: 'SHOP-1', resolution: 'Done' },
      { key: 'SHOP-2', status: 'Closed', category: 'Done' },
      { key: 'SHOP-3' }))

    assert_equal 1, result.added
    assert_equal 2, result.finished
    assert_equal ['SHOP-3'], MuseumItem.select_map(:source_key)
  end

  it 'marks issues that were in progress' do
    import(jira_csv({ key: 'SHOP-1', status: 'Doing', category: 'In Progress' }, { key: 'SHOP-2' }))

    assert item('SHOP-1').in_progress
    refute item('SHOP-2').in_progress
  end

  it 'keeps every label' do
    import(jira_csv({ key: 'SHOP-1', labels: %w[checkout mobile] }, { key: 'SHOP-2', labels: ['checkout'] }))

    assert_equal %w[checkout mobile], item('SHOP-1').labels.to_a
    assert_equal ['checkout'], item('SHOP-2').labels.to_a
  end

  it 'keeps what comments said and when, without who said it' do
    import(jira_csv({ comments: ['05/Feb/24 3:30 PM;accountid:557058abc;Needs a design; ask first', '06/Feb/24 9:00 AM;bob;Agreed'] }))

    assert_equal [{ 'at' => '2024-02-05T15:30:00Z', 'text' => 'Needs a design; ask first' },
                  { 'at' => '2024-02-06T09:00:00Z', 'text' => 'Agreed' }],
      item('SHOP-1').comments.to_a
  end

  it 'keeps no people' do
    import(jira_csv({ description: 'Ask [~accountid:557058abc] about it',
                      comments: ['05/Feb/24 3:30 PM;bob;Thanks [~bob.jones]!'] }))

    museum_item = item('SHOP-1')

    assert_equal 'Ask about it', museum_item.description
    assert_equal 'Thanks!', museum_item.comments.first['text']
    refute_match(/Alice|Bob|accountid/, museum_item.values.to_s)
  end

  it 'removes email addresses' do
    import(jira_csv({ description: "Mail ana@shop.example or [mailto:bob.jones@shop.example] today\nThanks",
                      comments: ['05/Feb/24 3:30 PM;bob;Copy [Kim|mailto:kim@shop.example] please'] }))

    museum_item = item('SHOP-1')

    assert_equal "Mail or today\nThanks", museum_item.description
    assert_equal 'Copy please', museum_item.comments.first['text']
  end

  it 'keeps package versions that look like email addresses' do
    import(jira_csv({ description: 'Upgrade to react@18.3.1 and @scope/pkg@2.0.0' }))

    assert_equal 'Upgrade to react@18.3.1 and @scope/pkg@2.0.0', item('SHOP-1').description
  end

  it 'keeps a comment that is not in date;author;text form as text without a date' do
    import(jira_csv({ comments: ['Needs a design; ask first', 'Plain note'] }))

    assert_equal [{ 'at' => nil, 'text' => 'Needs a design; ask first' }, { 'at' => nil, 'text' => 'Plain note' }],
      item('SHOP-1').comments.to_a
  end

  it 'skips rows it cannot keep, and counts them' do
    result = import(jira_csv(
      { key: 'SHOP-1' },
      { key: '', summary: 'No key' },
      { key: 'not a key' },
      { key: "SHOP-#{'9' * 50}" },
      { key: 'SHOP-5', summary: '' },
      { key: 'SHOP-6', type: '' },
      { key: 'SHOP-7', type: 'x' * 51 },
      { key: 'SHOP-8', summary: 'x' * 256 },
      { key: 'SHOP-9', summary: 'x' * 255 }
    ))

    assert_predicate result, :success?
    assert_equal [2, 7], [result.added, result.skipped]
    assert_equal %w[SHOP-1 SHOP-9], MuseumItem.select_map(:source_key).sort
  end

  it 'upper-cases issue keys, parents and links' do
    import(jira_csv({ key: 'shop-1', id: '1' }, { key: 'Shop-2', id: '2', parent: 'shop-1', blocked_by: 'shop-3' }))

    assert_equal 'SHOP-1', item('SHOP-2').parent_key
    link_keys = item('SHOP-2').links.map { |link| link['key'] }

    assert_equal ['SHOP-3'], link_keys
  end

  it 'drops link cells that are not issue keys' do
    import(jira_csv({ blocked_by: 'see the wiki' }))

    assert_empty item('SHOP-1').links.to_a
  end

  it 'cleans control characters and line endings, and puts summaries on one line' do
    import(jira_csv({ summary: "Search\r\nby   postcode\u0000", description: "One\r\nTwo\rThree\u0007\tdone\u0000",
                      labels: ["mob\u0000ile"], comments: ["05/Feb/24 3:30 PM;bob;Line\r\nnext\u0000"] }))

    museum_item = item('SHOP-1')

    assert_equal 'Search by postcode', museum_item.summary
    assert_equal "One\nTwo\nThree\tdone", museum_item.description
    assert_equal ['mobile'], museum_item.labels.to_a
    assert_equal "Line\nnext", museum_item.comments.first['text']
  end

  it 'keeps each label once' do
    import(jira_csv({ labels: %w[mobile mobile] }))

    assert_equal ['mobile'], item('SHOP-1').labels.to_a
  end

  it 'keeps links to other issues by key' do
    import(jira_csv({ blocked_by: 'SHOP-9', relates_to: 'SHOP-7' }))

    assert_equal [{ 'type' => 'Blocks', 'direction' => 'inward', 'key' => 'SHOP-9' },
                  { 'type' => 'Relates', 'direction' => 'outward', 'key' => 'SHOP-7' }],
      item('SHOP-1').links.to_a
  end

  it 'finds each parent by key, whether the export names it by key or by id' do
    import(jira_csv({ key: 'SHOP-1', id: '10001', type: 'Epic' },
      { key: 'SHOP-2', id: '10002', parent: '10001' },
      { key: 'SHOP-3', id: '10003', parent: 'SHOP-1' },
      { key: 'SHOP-4', id: '10004', parent: '99999' }))

    assert_nil item('SHOP-1').parent_key
    assert_equal 'SHOP-1', item('SHOP-2').parent_key
    assert_equal 'SHOP-1', item('SHOP-3').parent_key
    assert_nil item('SHOP-4').parent_key
  end

  it 'refreshes items still in the museum from a newer export and adds new ones' do
    import(jira_csv({ key: 'SHOP-1' }, { key: 'SHOP-2' }, { key: 'SHOP-3' }))
    task = create_task
    story = Story.create(task_id: task.id, map_id: task.map_id, team_id: @team.id, title: 'Promoted', position: 1000,
      created_by_id: @person.id)
    item('SHOP-2').update(story_id: story.id, promoted_at: Time.now)

    result = import(jira_csv({ key: 'SHOP-1', summary: 'Renamed' }, { key: 'SHOP-2', summary: 'Renamed' }, { key: 'SHOP-4' }))

    assert_equal [1, 1, 1, 0], [result.added, result.updated, result.promoted, result.discarded]
    assert_equal 'Renamed', item('SHOP-1').summary
    assert_equal 'Search by postcode', item('SHOP-2').summary
    assert_equal 'Search by postcode', item('SHOP-3').summary
    assert item('SHOP-4')
  end

  it 'leaves discarded items discarded' do
    import(jira_csv({ key: 'SHOP-1' }))
    item('SHOP-1').update(discarded_at: Time.now)

    result = import(jira_csv({ key: 'SHOP-1', summary: 'Renamed' }))

    assert_equal [0, 0, 1], [result.added, result.updated, result.discarded]
    assert_equal 'Search by postcode', item('SHOP-1').summary
    assert item('SHOP-1').discarded_at
  end

  it 'takes the last row when an export lists a key twice' do
    result = import(jira_csv({ summary: 'First' }, { summary: 'Second' }))

    assert_equal 1, result.added
    assert_equal 'Second', item('SHOP-1').summary
  end

  it 'refuses a file that is not a Jira export, naming the missing columns' do
    result = import(jira_csv({}, headers: with_header('Issue key', 'Key').map { |h| h == 'Summary' ? 'Title' : h }))

    refute_predicate result, :success?
    assert_equal 1, result.errors.size
    assert_equal ['Issue key', 'Summary'], result.missing_columns
    assert_equal 0, MuseumItem.count
  end

  it 'reads semicolon and tab separated exports' do
    assert_predicate import(jira_csv({ key: 'SHOP-1', labels: %w[a b] }, col_sep: ';')), :success?
    assert_predicate import(jira_csv({ key: 'SHOP-2', description: 'Pay; then ship' }, col_sep: "\t")), :success?

    assert_equal %w[a b], item('SHOP-1').labels.to_a
    assert_equal 'Pay; then ship', item('SHOP-2').description
  end

  it 'finds parents in a Parent id or Epic Link column' do
    import(jira_csv({ key: 'SHOP-1', id: '1', type: 'Epic' }, { key: 'SHOP-2', id: '2', parent: '1' },
      headers: with_header('Parent', 'Parent id')))
    import(jira_csv({ key: 'SHOP-3', id: '3', parent: 'SHOP-1' }, headers: with_header('Parent', 'Custom field (Epic Link)')))

    assert_equal 'SHOP-1', item('SHOP-2').parent_key
    assert_equal 'SHOP-1', item('SHOP-3').parent_key
  end

  it 'reads the date formats Jira and spreadsheets write' do
    import(jira_csv({ key: 'SHOP-1', created: '02/Jan/2024 10:15 AM' }, { key: 'SHOP-2', created: '02/Jan/24 10:15' },
      { key: 'SHOP-3', created: '2024-01-02 10:15' }, { key: 'SHOP-4', created: '2024-01-02T10:15:00' },
      { key: 'SHOP-5', created: '02/01/2024 10:15' }, { key: 'SHOP-6', created: 'sometime' }))

    times = %w[SHOP-1 SHOP-2 SHOP-3 SHOP-4 SHOP-5].map { |key| item(key).source_created_at }

    assert_equal [Time.utc(2024, 1, 2, 10, 15)] * 5, times
    assert_nil item('SHOP-6').source_created_at
  end

  it 'keeps when Jira last updated each issue' do
    import(jira_csv({ key: 'SHOP-1', updated: '05/Mar/24 9:00 AM' }, { key: 'SHOP-2', updated: '' }))

    assert_equal Time.utc(2024, 3, 5, 9), item('SHOP-1').source_updated_at
    assert_nil item('SHOP-2').source_updated_at
  end

  it 'reads numeric dates month first when an updated date shows that is the order' do
    import(jira_csv({ key: 'SHOP-1', created: '01/02/2024 10:15', updated: '01/13/2024 10:15' }))

    assert_equal Time.utc(2024, 1, 2, 10, 15), item('SHOP-1').source_created_at
    assert_equal Time.utc(2024, 1, 13, 10, 15), item('SHOP-1').source_updated_at
  end

  it 'reads numeric dates month first when the file shows that is its order' do
    import(jira_csv({ key: 'SHOP-1', created: '01/02/2024 10:15' }, { key: 'SHOP-2', created: '01/13/2024 10:15' }))

    assert_equal Time.utc(2024, 1, 2, 10, 15), item('SHOP-1').source_created_at
    assert_equal Time.utc(2024, 1, 13, 10, 15), item('SHOP-2').source_created_at
  end

  it 'takes at most 1000 issues from one file' do
    issues = Array.new(1000) { |n| { key: "SHOP-#{n}", id: n.to_s } }

    assert_predicate import(jira_csv(*issues)), :success?

    over = import(jira_csv(*issues, { key: 'SHOP-1000', id: '1000', resolution: 'Done' }))

    refute_predicate over, :success?
    assert_equal 1, over.errors.size
  end

  it 'refuses a file that is not CSV' do
    result = import("Summary,Issue key,Issue Type\n\"broken,SHOP-1,Story\n")

    refute_predicate result, :success?
    assert_equal 1, result.errors.size
  end

  it 'reads an export that starts with a byte order mark' do
    assert_predicate import("\uFEFF#{jira_csv({})}".b), :success?
    assert item('SHOP-1')
  end

  it 'skips blank lines' do
    assert_predicate import("#{jira_csv({})}\n,,\n\n"), :success?
    assert_equal ['SHOP-1'], MuseumItem.select_map(:source_key)
  end

  it 'refuses a file over 10 MB' do
    base = jira_csv({ description: 'x' }).bytesize
    exactly = jira_csv({ description: 'x' * (1 + (10 * 1024 * 1024) - base) })

    assert_predicate import(exactly), :success?
    refute_predicate import("#{exactly}\n"), :success?
  end

  it 'refuses to hold more than 20,000 items for a team' do
    now = Time.now
    DB[:museum_items].multi_insert(Array.new(19_999) { |n|
      { team_id: @team.id, source_key: "OLD-#{n}", issue_type: 'Story', summary: 'Old', created_at: now, updated_at: now }
    })

    assert_predicate import(jira_csv({ key: 'SHOP-1' })), :success?
    over = import(jira_csv({ key: 'SHOP-2' }))

    refute_predicate over, :success?
    assert_equal 1, over.errors.size
    assert_predicate import(jira_csv({ key: 'SHOP-1', summary: 'Renamed' })), :success?
  end

  def create_task
    map = Map.create(team_id: @team.id, name: 'Map', position: 1000)
    activity = Activity.create(map_id: map.id, team_id: @team.id, name: 'Browse', position: 1000)
    Task.create(activity_id: activity.id, map_id: map.id, team_id: @team.id, name: 'Search', position: 1000)
  end
end
