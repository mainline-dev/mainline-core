# frozen_string_literal: true

ENV['MT_NO_PLUGINS'] = '1'
gem 'minitest'
require 'minitest/global_expectations/autorun'
require 'date'
require 'yaml'
require_relative '../../lib/mutation_baseline'

MUTANT_REPORT = <<~REPORT
  Mutant environment:
  Usage:           opensource
  Subjects:        4
  Results:         51
  Kills:           36
  Alive:           15
  Timeouts:        0
  Runtime:         5.27s
  Coverage:        70.59%
REPORT

MUTANT_LISTING = <<~LISTING
  warning: parser/current is loading parser/ruby34
  Subjects in environment: 3
  AssignPerson.people_at_limit
  AssignPerson.call
  DataExport::Writer#rows
LISTING

MUTANT_SURVIVORS = <<~REPORT
  evil:AssignPerson.people_at_limit:/app/lib/assign_person.rb:20:a2e44
  -----------------------
  @@ -1,3 +1,3 @@
  -  limit >= 1
  +  limit > 1
  -----------------------
  (14 more alive mutation(s), use `mutant session subject AssignPerson.people_at_limit` to see all details)
  evil:AssignPerson.wip_limit:/app/lib/assign_person.rb:15:0abaf
  -----------------------
  @@ -1,3 +1,3 @@
  -  default: 1
  +  default: nil
  -----------------------
  Results:         2
REPORT

describe MutationBaseline do
  def score(**parts)
    MutationBaseline::Score.new(subject: 'BypassRLS', mutations: 51, killed: 36, alive: 15, problem: nil, **parts)
  end

  it "reads a class's score from the report mutant prints" do
    assert_equal score, MutationBaseline.read('BypassRLS', MUTANT_REPORT)
  end

  it 'takes the last report when mutant printed progress before it' do
    earlier = MUTANT_REPORT.sub('Kills:           36', 'Kills:           10').sub('Alive:           15', 'Alive:           41')

    assert_equal score, MutationBaseline.read('BypassRLS', earlier + MUTANT_REPORT)
  end

  it 'notes a class mutant could not run, with what it said first' do
    crashed = MutationBaseline.read('AssignPerson', "binary.rb:55: undefined method 'type' for nil (NoMethodError)\n\tfrom somewhere\n")

    assert_equal [nil, nil, nil, "binary.rb:55: undefined method 'type' for nil (NoMethodError)"],
      crashed.to_a.last(4)
  end

  it 'writes a line for each class that reads back as its numbers' do
    written = MutationBaseline.render([score, score(subject: 'ResourceCap', mutations: 77, killed: 77, alive: 0)],
      on: Date.new(2026, 11, 12), hosted: [])

    assert_equal({ 'BypassRLS'   => { 'mutations' => 51, 'killed' => 36, 'alive' => 15 },
                   'ResourceCap' => { 'mutations' => 77, 'killed' => 77, 'alive' => 0 } },
      YAML.safe_load(written)['classes'])
    assert_equal '2026-11-12', YAML.safe_load(written)['measured_on']
  end

  it 'writes what went wrong for a class that could not be run' do
    written = MutationBaseline.render([score(mutations: nil, killed: nil, alive: nil, problem: 'it crashed')],
      on: Date.new(2026, 11, 12), hosted: [])

    assert_equal({ 'problem' => 'it crashed' }, YAML.safe_load(written)['classes']['BypassRLS'])
  end

  it 'marks the line of a hosted class, so the public export leaves it out' do
    written = MutationBaseline.render([score, score(subject: 'ResourceCap')], on: Date.new(2026, 11, 12), hosted: ['BypassRLS'])

    assert_equal([true, false], %w[BypassRLS ResourceCap].map { |name| written[/^  #{name}:.*$/].end_with?('# hosted') })
  end

  it 'adds the classes up' do
    assert_equal({ mutations: 128, killed: 113, alive: 15 },
      MutationBaseline.total([score, score(subject: 'ResourceCap', mutations: 77, killed: 77, alive: 0),
                              score(subject: 'Broken', mutations: nil, killed: nil, alive: nil, problem: 'x')]))
  end

  describe 'after a change' do
    def baseline
      MutationBaseline.render([score, score(subject: 'ResourceCap', mutations: 77, killed: 77, alive: 0)],
        on: Date.new(2026, 11, 1), hosted: [])
    end

    it 'names the subjects mutant says have changed' do
      assert_equal ['AssignPerson.people_at_limit', 'AssignPerson.call', 'DataExport::Writer#rows'],
        MutationBaseline.changed_subjects(MUTANT_LISTING)
    end

    it 'names the measured classes those subjects belong to, each once' do
      assert_equal %w[AssignPerson DataExport],
        MutationBaseline.changed_classes(MUTANT_LISTING, %w[Assign AssignPerson BusinessDays DataExport])
    end

    it 'finds no class changed when mutant lists no subjects' do
      assert_empty MutationBaseline.changed_classes("Subjects in environment: 0\n", %w[AssignPerson])
    end

    it 'picks out what survived in the changed subjects, leaving the rest of the class out' do
      assert_equal [['AssignPerson.people_at_limit', "-  limit >= 1\n+  limit > 1", 14]],
        MutationBaseline.survivors(MUTANT_SURVIVORS, ['AssignPerson.people_at_limit'])
    end

    it 'counts no more survivors for a subject mutant showed in full' do
      assert_equal [0], MutationBaseline.survivors(MUTANT_SURVIVORS, ['AssignPerson.wip_limit']).map(&:last)
    end

    it 'says which classes kill a smaller share than their baseline, by more than the slack' do
      scores = [score(killed: 30, alive: 21), score(subject: 'ResourceCap', mutations: 80, killed: 80, alive: 0)]

      assert_equal [{ subject: 'BypassRLS', was: 70.6, now: 58.8 }], MutationBaseline.worse(scores, baseline)
    end

    it 'lets a class grow: more surviving at the same share is no worse' do
      assert_empty MutationBaseline.worse([score(mutations: 102, killed: 72, alive: 30)], baseline)
    end

    it 'allows a drop within the slack' do
      assert_empty MutationBaseline.worse([score(killed: 35, alive: 16)], baseline)
    end

    it 'holds nothing against a class that is the same, better, new, or could not be run' do
      scores = [score, score(subject: 'ResourceCap', mutations: 77, killed: 77, alive: 0),
                score(subject: 'Brand new', mutations: 10, killed: 1, alive: 9),
                score(subject: 'BypassRLS', mutations: nil, killed: nil, alive: nil, problem: 'it crashed')]

      assert_empty MutationBaseline.worse(scores, baseline)
    end

    it 'holds nothing against a class with no mutations, then or now' do
      empty = MutationBaseline.render([score(mutations: 0, killed: 0, alive: 0)], on: Date.new(2026, 11, 1), hosted: [])

      assert_empty MutationBaseline.worse([score(killed: 0, alive: 51)], empty)
      assert_empty MutationBaseline.worse([score(mutations: 0, killed: 0, alive: 0)], baseline)
    end

    it 'takes new scores into the baseline for the classes measured again, keeping the others' do
      measured = [score(alive: 9, killed: 42), score(subject: 'Brand new', mutations: 4, killed: 4, alive: 0)]
      merged = MutationBaseline.merge(baseline, measured, on: Date.new(2026, 11, 12), hosted: ['Brand new'])
      classes = YAML.safe_load(merged)['classes']

      assert_equal ['BypassRLS', 'ResourceCap', 'Brand new'], classes.keys
      assert_equal([9, 0, 0], classes.values.map { |numbers| numbers['alive'] })
      assert_equal '2026-11-12', YAML.safe_load(merged)['measured_on']
      assert merged[/^  Brand new:.*$/].end_with?('# hosted')
    end
  end
end
