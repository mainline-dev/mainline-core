# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/mainline_file'
require_relative '../../lib/add_scenario'
require_relative '../../lib/create_story'
require_relative '../dsl/mainline_file'

describe MainlineFile do
  cover 'MainlineFile*'

  def read(*entries, **top)
    MainlineFile.read(MainlineFileFixture.json(*entries, **top))
  end

  it 'reads each entry as an item the museum can hold, with its origin and suggestions' do
    scenario = { name: 'Both kept', given: 'two people', when: 'each changes a field', then: 'both show' }
    item = read({ key: 'RB-SAVE-01', title: 'Racing saves', source: 'Report, section 3', why: 'Jira keeps the last save.',
                  suggested: { activity: 'Track work', step: 'Change an item' }, draft_scenarios: [scenario] }).items.first

    assert_equal ['RB-SAVE-01', 'Proposal', 'Racing saves', 'Jira keeps the last save.', 'Report, section 3'],
      item.values_at(:source_key, :issue_type, :summary, :description, :origin)
    assert_equal({ 'activity' => 'Track work', 'step' => 'Change an item',
                   'scenarios' => [scenario.transform_keys(&:to_s)] }, item[:suggested])
    assert_equal [[], [], [], false, nil], item.values_at(:labels, :comments, :links, :in_progress, :parent_key)
  end

  it 'reads the proposed backbone, tidied, with names said twice kept once' do
    backbone = read({ key: 'RB-1' }, map: " RepoBoard\n", personas: ['Team member', 'team member', 'Admin'],
      activities: [{ name: 'Track work', personas: ['Team member'], steps: ['Find an item', 'find an item', 'Change an item'] }]).backbone

    assert_equal({ 'map' => 'RepoBoard', 'personas' => ['Team member', 'Admin'],
                   'activities' => [{ 'name' => 'Track work', 'personas' => ['Team member'],
                                      'steps' => ['Find an item', 'Change an item'] }] }, backbone)
  end

  it 'has no backbone when the file proposes none' do
    assert_nil read({ key: 'RB-1' }).backbone
  end

  it 'reads an entry that suggests nothing' do
    item = read({ key: 'RB-1' }).items.first

    assert_equal '', item[:description]
    assert_equal({ 'activity' => nil, 'step' => nil, 'scenarios' => [] }, item[:suggested])
  end

  it 'keeps titles, origins and scenario parts on one line, and takes out control characters' do
    file = read({ key: 'RB-1', title: "Racing\n saves\u0007", source: "Report,\tsection 3",
                  draft_scenarios: [{ name: "Both\nkept", given: 'a', when: 'b', then: "c\r\nd" }] })
    item = file.items.first

    assert_equal ['Racing saves', 'Report, section 3'], item.values_at(:summary, :origin)
    assert_equal ['Both kept', 'c d'], item[:suggested]['scenarios'].first.values_at('name', 'then')
  end

  it 'says a file saved with a code fence round it is fenced, where it would otherwise say it is not JSON' do
    fenced = MainlineFile.read("```json\n#{MainlineFileFixture.json({ key: 'RB-1' })}\n```\n")

    refute_predicate fenced, :success?
    assert_equal [{ 'entry' => '', 'field' => 'file', 'problem' => 'fenced' }], fenced.problems
    assert_equal 1, fenced.errors.size
  end

  it 'says so too when the fence has no language named or is indented' do
    fenced = MainlineFile.read("  ```\n#{MainlineFileFixture.json({ key: 'RB-1' })}\n```")

    assert_equal [{ 'entry' => '', 'field' => 'file', 'problem' => 'fenced' }], fenced.problems
  end

  it 'still says a file that is neither JSON nor fenced is not JSON' do
    assert_equal [{ 'entry' => '', 'field' => 'file', 'problem' => 'not_json' }], MainlineFile.read('Summary,Issue key').problems
  end

  it 'refuses a file over 10 MB without reading it' do
    read = MainlineFile.read('x' * (MainlineFile::MAX_BYTES + 1))

    refute_predicate read, :success?
    assert_equal [{ 'entry' => '', 'field' => 'file', 'problem' => 'too_big' }], read.problems
  end

  it 'names a problem by the entry key when it has one, and by its place when it has not' do
    problems = read({ key: nil, title: 'A' }, { key: 'rb 2' }, { key: 'RB-3', colour: 'red' }).problems

    found = problems.map { |problem| problem.values_at('entry', 'field', 'problem') }

    assert_equal [['entry 1', 'key', 'missing'], ['entry 2', 'key', 'wrong_shape'], ['RB-3', 'colour', 'unknown']], found
  end

  it 'says each problem in words a model can act on' do
    problems = read({ key: 'RB-1', title: nil }, { key: 'RB-2', draft_scenarios: [{ name: 'n', given: 'g', when: 'w' }] }).problems

    assert_equal ['Entry RB-1 has no title', 'Entry RB-2, scenario 1 has no then'], MainlineFile.sentences(problems)
  end

  it "allows what the app allows: a story's title and a scenario's name and parts" do
    schema = JSON.parse(File.read(MainlineFile::SCHEMA_PATH))
    entry = schema.dig('$defs', 'entry', 'properties')
    scenario = schema.dig('$defs', 'scenario', 'properties')

    assert_equal MainlineFile::TITLE_LENGTH, entry.dig('title', 'maxLength')
    assert_equal AddScenario::NAME_LENGTH, scenario.dig('name', 'maxLength')
    assert_equal([AddScenario::MAX_LENGTH] * 3, %w[given when then].map { |part| scenario.dig(part, 'maxLength') })
    assert_equal MainlineFile::MAX_ENTRIES, schema.dig('properties', 'entries', 'maxItems')
  end
end
