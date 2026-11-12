# frozen_string_literal: true

require 'date'
require 'open3'
require 'yaml'

# Mutation testing, one class at a time, with each class's score kept in a
# file in the repository. Each class runs on its own, so one that mutant
# cannot handle is noted and the rest still run. The file is a floor and
# nothing more: after a change, the classes it touched are run again, what
# survives in the changed code is shown for a person to judge, and only a
# class that kills a clearly smaller share of its mutations than its baseline
# stops the push. Nobody is asked to reach 100%.
module MutationBaseline
  PATH = '.mutant-baseline.yml'
  HOSTED = '# hosted'
  # How many percentage points a class may fall below its baseline before a
  # push is stopped.
  SLACK = 2.0
  Score = Struct.new(:subject, :mutations, :killed, :alive, :problem, keyword_init: true)

  # Runs mutant on each class in turn, yielding each score and mutant's
  # report as they come.
  def self.measure(subjects)
    subjects.map do |subject|
      report, = Open3.capture2e('bundle', 'exec', 'mutant', 'run', "#{subject}*")
      read(subject, report).tap { |score| yield score, report if block_given? }
    end
  end

  # A class's score from what mutant printed. The last report counts: mutant
  # prints progress in the same words before it.
  def self.read(subject, report)
    numbers = %w[Results Kills Alive].map { |label| report.scan(/^#{label}:\s+(\d+)/).last&.first&.to_i }
    return Score.new(subject: subject, problem: report.lines.map(&:strip).reject(&:empty?).first || 'no report') if numbers.any?(&:nil?)

    Score.new(subject: subject, mutations: numbers[0], killed: numbers[1], alive: numbers[2])
  end

  # The baseline file. A hosted class's line ends in the mark the public
  # export drops lines by.
  def self.render(scores, on:, hosted:)
    lines = scores.map { |score|
      "  #{score.subject}: #{line(score)}#{" #{HOSTED}" if hosted.include?(score.subject)}"
    }
    <<~BASELINE
      # Mutation testing, class by class. Written by "rake mutant_baseline"
      # (scripts/mutation.sh runs it in the test stack). A floor, not a target:
      # "rake mutant_changed" stops a push only when a changed class kills a
      # share of its mutations more than #{SLACK.to_i} points below its share here. To
      # accept a new number for a class, measure it again:
      # scripts/mutation.sh AssignPerson
      measured_on: '#{on.iso8601}'
      classes:
      #{lines.join("\n")}
    BASELINE
  end

  # The subjects mutant lists: what "mutant environment subject list" prints
  # after its count line.
  def self.changed_subjects(listing)
    listing.lines.map(&:strip).drop_while { |line| !line.start_with?('Subjects in environment:') }.drop(1).reject(&:empty?)
  end

  # The measured classes that own any of the subjects listed.
  def self.changed_classes(listing, classes)
    subjects = changed_subjects(listing)
    classes.select { |name| subjects.any? { |subject| subject.match?(/\A#{Regexp.escape(name)}(\.|#|::)/) } }
  end

  # What survived in the given subjects: [subject, the first change mutant
  # shows, how many more survived]. Mutant prints one per subject and counts
  # the rest.
  def self.survivors(report, subjects)
    report.scan(%r{^evil:(.+?):/[^\n]*\n-{5,}\n(.*?)\n-{5,}$(?:\n\((\d+) more alive)?}m).filter_map do |subject, change, more|
      next unless subjects.include?(subject)

      [subject, change.lines.reject { |line| line.start_with?('@@') }.join.chomp, more.to_i]
    end
  end

  # The classes that now kill a smaller share of their mutations than the
  # baseline file has for them, by more than the slack. The share is what is
  # held, so a class may grow. A class the baseline does not know, one with
  # no mutations, or one that could not be run, is let be.
  def self.worse(scores, baseline)
    known = YAML.safe_load(baseline).fetch('classes')
    scores.filter_map do |score|
      was = share(known.dig(score.subject, 'killed'), known.dig(score.subject, 'mutations'))
      now = share(score.killed, score.mutations)
      { subject: score.subject, was: was, now: now } if was && now && now < was - SLACK
    end
  end

  # The percentage of mutations killed, to one decimal place.
  def self.share(killed, mutations)
    (killed * 100.0 / mutations).round(1) if killed && mutations.to_i.positive?
  end

  # The baseline file with these classes measured again and the rest as they were.
  def self.merge(baseline, scores, on:, hosted:)
    kept = YAML.safe_load(baseline).fetch('classes').map { |subject, numbers|
      Score.new(subject: subject, mutations: numbers['mutations'], killed: numbers['killed'], alive: numbers['alive'],
        problem: numbers['problem'])
    }
    fresh = scores.to_h { |score| [score.subject, score] }
    merged = kept.map { |score| fresh.delete(score.subject) || score } + fresh.values
    render(merged, on: on, hosted: hosted)
  end

  def self.total(scores)
    measured = scores.reject(&:problem)
    { mutations: measured.sum(&:mutations), killed: measured.sum(&:killed), alive: measured.sum(&:alive) }
  end

  def self.line(score)
    return "{ problem: #{score.problem.inspect} }" if score.problem

    "{ mutations: #{score.mutations}, killed: #{score.killed}, alive: #{score.alive} }"
  end
  private_class_method :line, :share
end
