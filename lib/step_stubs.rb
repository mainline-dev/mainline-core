# frozen_string_literal: true

require_relative 'feature_file'

# Pending step definitions for a story's scenarios, in the language a team
# tests in: one per distinct step, matching the feature file's text exactly.
# Nothing passes until a person or an agent makes it pass.
module StepStubs
  LANGUAGES = {
    'kotlin'     => 'Kotlin',
    'java'       => 'Java',
    'ruby'       => 'Ruby',
    'typescript' => 'TypeScript',
    'pytest-bdd' => 'Python (pytest-bdd)',
    'behave'     => 'Python (behave)'
  }.freeze

  # Cucumber matches a step whatever its keyword, so the same text under Given
  # and Then is one step there; pytest-bdd and behave keep them apart.
  KEYWORD_BLIND = %w[kotlin java ruby typescript].freeze

  Step = Struct.new(:keyword, :text, :name)

  def self.for(story, language)
    steps = steps(story)
    steps = steps.uniq(&:text) if KEYWORD_BLIND.include?(language)
    send(:"#{language.tr('-', '_')}_stubs", story, named(steps, language))
  end

  def self.file_name(story, language)
    words = words(story.title)
    case language
    when 'kotlin' then "#{class_name(story)}.kt"
    when 'java' then "#{class_name(story)}.java"
    when 'ruby', 'behave' then "#{words.join('_')}_steps.#{language == 'ruby' ? 'rb' : 'py'}"
    when 'typescript' then "#{words.join('-')}.steps.ts"
    when 'pytest-bdd' then "test_#{words.join('_')}.py"
    end
  end

  def self.steps(story)
    Scenario.where(story_id: story.id).order(:position).all.flat_map { |scenario|
      { 'Given' => scenario.given_text, 'When' => scenario.when_text, 'Then' => scenario.then_text }
        .map { |keyword, text| Step.new(keyword, FeatureFile.one_line(text)) }
    }.uniq
  end

  # Gives each step the name of its method or function, numbering any that
  # would otherwise repeat (steps that differ only in punctuation, or have no
  # Latin letters at all).
  def self.named(steps, language)
    seen = Hash.new(0)
    steps.map do |step|
      name = %w[kotlin java].include?(language) ? method_name(step) : function_name(step)
      count = seen[name] += 1
      Step.new(step.keyword, step.text, count == 1 ? name : "#{name}#{count}")
    end
  end

  def self.header(story, comment)
    "#{comment} Step stubs for \"#{FeatureFile.one_line(story.title)}\". Every step is pending until a person or an agent makes it pass.\n"
  end

  def self.words(text)
    text.downcase.scan(/[a-z0-9]+/).then { |found| found.empty? ? ['story'] : found }
  end

  def self.class_name(story)
    name = "#{words(story.title).map(&:capitalize).join}Steps"
    name.match?(/\A\d/) ? "Story#{name}" : name
  end

  def self.method_name(step)
    step.keyword.downcase + words(step.text).map(&:capitalize).join
  end

  def self.function_name(step)
    ([step.keyword.downcase] + words(step.text)).join('_')
  end

  # Cucumber expressions read (, { and / as syntax, so plain text escapes them.
  def self.expression(text)
    text.gsub(%r{[\\(\{/]}) { |char| "\\#{char}" }
  end

  def self.double_quoted(text, dollar: false)
    quoted = text.gsub('\\') { '\\\\' }.gsub('"', '\\"')
    dollar ? quoted.gsub('$', '\\$') : quoted
  end

  def self.single_quoted(text)
    "'#{text.gsub('\\') { '\\\\' }.gsub("'") { "\\'" }}'"
  end

  def self.kotlin_stubs(story, steps)
    methods = steps.map { |step|
      <<~KOTLIN.gsub(/^/, '    ')
        @#{step.keyword}("#{double_quoted(expression(step.text), dollar: true)}")
        fun #{step.name}() {
            throw PendingException()
        }
      KOTLIN
    }
    header(story, '//') +
      "import io.cucumber.java.PendingException\nimport io.cucumber.java.en.Given\n" \
      "import io.cucumber.java.en.Then\nimport io.cucumber.java.en.When\n\n" \
      "class #{class_name(story)} {\n#{methods.join("\n")}}\n"
  end

  def self.java_stubs(story, steps)
    methods = steps.map { |step|
      <<~JAVA.gsub(/^/, '    ')
        @#{step.keyword}("#{double_quoted(expression(step.text))}")
        public void #{step.name}() {
            throw new PendingException();
        }
      JAVA
    }
    header(story, '//') +
      "import io.cucumber.java.PendingException;\nimport io.cucumber.java.en.Given;\n" \
      "import io.cucumber.java.en.Then;\nimport io.cucumber.java.en.When;\n\n" \
      "public class #{class_name(story)} {\n#{methods.join("\n")}}\n"
  end

  def self.ruby_stubs(story, steps)
    blocks = steps.map { |step| "#{step.keyword}(#{single_quoted(expression(step.text))}) do\n  pending\nend\n" }
    "#{header(story, '#')}\n#{blocks.join("\n")}"
  end

  def self.typescript_stubs(story, steps)
    blocks = steps.map { |step|
      "#{step.keyword}(#{single_quoted(expression(step.text))}, function () {\n  return 'pending';\n});\n"
    }
    "#{header(story, '//')}import { Given, Then, When } from '@cucumber/cucumber';\n\n#{blocks.join("\n")}"
  end

  def self.pytest_bdd_stubs(story, steps)
    functions = steps.map { |step|
      "@#{step.keyword.downcase}(#{single_quoted(step.text)})\ndef #{step.name}():\n    raise NotImplementedError\n"
    }
    "#{header(story, '#')}from pytest_bdd import given, scenarios, then, when\n\n" \
      "scenarios(#{single_quoted(FeatureFile.file_name(story))})\n\n\n#{functions.join("\n\n")}"
  end

  def self.behave_stubs(story, steps)
    functions = steps.map { |step|
      pattern = step.text.gsub('{', '{{').gsub('}', '}}')
      <<~PYTHON
        @#{step.keyword.downcase}(#{single_quoted(pattern)})
        def step_impl(context):
            raise NotImplementedError(#{single_quoted("STEP: #{step.keyword} #{step.text}")})
      PYTHON
    }
    "#{header(story, '#')}from behave import given, then, when\n\n\n#{functions.join("\n\n")}"
  end

  private_class_method :steps, :named, :header, :words, :class_name, :method_name, :function_name, :expression,
    :double_quoted, :single_quoted, :kotlin_stubs, :java_stubs, :ruby_stubs, :typescript_stubs,
    :pytest_bdd_stubs, :behave_stubs
end
