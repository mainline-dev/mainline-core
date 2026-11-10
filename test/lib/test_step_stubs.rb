# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/add_scenario'
require_relative '../../lib/step_stubs'

describe StepStubs do
  cover 'StepStubs*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    map = Map.create(team_id: @team.id, name: 'Shop', position: 1000)
    activity = Activity.create(map_id: map.id, team_id: @team.id, name: 'Checkout', position: 1000)
    task = Task.create(activity_id: activity.id, map_id: map.id, team_id: @team.id, name: 'Pay', position: 1000)
    @story = Story.create(task_id: task.id, map_id: map.id, team_id: @team.id, title: 'Guests can check out',
      position: 1000, created_by_id: @person.id)
    add('Guest pays by email', 'a basket and no account', 'I continue as a guest', 'I can pay with my email')
    add('Discount code', 'a basket and no account', 'I enter {SAVE10} (once)', "it's 10% off/now")
  end

  def add(name, given, whn, thn)
    AddScenario.call(story: @story, actor: @person.actor, name: name, given_text: given, when_text: whn, then_text: thn)
  end

  it 'offers the six languages' do
    assert_equal %w[kotlin java ruby typescript pytest-bdd behave], StepStubs::LANGUAGES.keys
  end

  it 'names each file the way its language expects' do
    names = StepStubs::LANGUAGES.keys.map { |language| StepStubs.file_name(@story, language) }

    assert_equal %w[GuestsCanCheckOutSteps.kt GuestsCanCheckOutSteps.java guests_can_check_out_steps.rb
                    guests-can-check-out.steps.ts test_guests_can_check_out.py guests_can_check_out_steps.py], names
  end

  it 'writes Kotlin stubs for Cucumber-JVM, one per distinct step, all pending' do
    assert_equal <<~'KOTLIN', StepStubs.for(@story, 'kotlin')
      // Step stubs for "Guests can check out". Every step is pending until a person or an agent makes it pass.
      import io.cucumber.java.PendingException
      import io.cucumber.java.en.Given
      import io.cucumber.java.en.Then
      import io.cucumber.java.en.When

      class GuestsCanCheckOutSteps {
          @Given("a basket and no account")
          fun givenABasketAndNoAccount() {
              throw PendingException()
          }

          @When("I continue as a guest")
          fun whenIContinueAsAGuest() {
              throw PendingException()
          }

          @Then("I can pay with my email")
          fun thenICanPayWithMyEmail() {
              throw PendingException()
          }

          @When("I enter \\{SAVE10} \\(once)")
          fun whenIEnterSave10Once() {
              throw PendingException()
          }

          @Then("it's 10% off\\/now")
          fun thenItS10OffNow() {
              throw PendingException()
          }
      }
    KOTLIN
  end

  it 'writes Java stubs for Cucumber-JVM' do
    assert_equal <<~'JAVA', StepStubs.for(@story, 'java')
      // Step stubs for "Guests can check out". Every step is pending until a person or an agent makes it pass.
      import io.cucumber.java.PendingException;
      import io.cucumber.java.en.Given;
      import io.cucumber.java.en.Then;
      import io.cucumber.java.en.When;

      public class GuestsCanCheckOutSteps {
          @Given("a basket and no account")
          public void givenABasketAndNoAccount() {
              throw new PendingException();
          }

          @When("I continue as a guest")
          public void whenIContinueAsAGuest() {
              throw new PendingException();
          }

          @Then("I can pay with my email")
          public void thenICanPayWithMyEmail() {
              throw new PendingException();
          }

          @When("I enter \\{SAVE10} \\(once)")
          public void whenIEnterSave10Once() {
              throw new PendingException();
          }

          @Then("it's 10% off\\/now")
          public void thenItS10OffNow() {
              throw new PendingException();
          }
      }
    JAVA
  end

  it 'writes Ruby stubs for cucumber-ruby' do
    assert_equal <<~'RUBY', StepStubs.for(@story, 'ruby')
      # Step stubs for "Guests can check out". Every step is pending until a person or an agent makes it pass.

      Given('a basket and no account') do
        pending
      end

      When('I continue as a guest') do
        pending
      end

      Then('I can pay with my email') do
        pending
      end

      When('I enter \\{SAVE10} \\(once)') do
        pending
      end

      Then('it\'s 10% off\\/now') do
        pending
      end
    RUBY
  end

  it 'writes TypeScript stubs for cucumber-js' do
    assert_equal <<~'TYPESCRIPT', StepStubs.for(@story, 'typescript')
      // Step stubs for "Guests can check out". Every step is pending until a person or an agent makes it pass.
      import { Given, Then, When } from '@cucumber/cucumber';

      Given('a basket and no account', function () {
        return 'pending';
      });

      When('I continue as a guest', function () {
        return 'pending';
      });

      Then('I can pay with my email', function () {
        return 'pending';
      });

      When('I enter \\{SAVE10} \\(once)', function () {
        return 'pending';
      });

      Then('it\'s 10% off\\/now', function () {
        return 'pending';
      });
    TYPESCRIPT
  end

  it 'writes pytest-bdd stubs, bound to the feature file, matching the steps exactly' do
    assert_equal <<~'PYTHON', StepStubs.for(@story, 'pytest-bdd')
      # Step stubs for "Guests can check out". Every step is pending until a person or an agent makes it pass.
      from pytest_bdd import given, scenarios, then, when

      scenarios('guests-can-check-out.feature')


      @given('a basket and no account')
      def given_a_basket_and_no_account():
          raise NotImplementedError


      @when('I continue as a guest')
      def when_i_continue_as_a_guest():
          raise NotImplementedError


      @then('I can pay with my email')
      def then_i_can_pay_with_my_email():
          raise NotImplementedError


      @when('I enter {SAVE10} (once)')
      def when_i_enter_save10_once():
          raise NotImplementedError


      @then('it\'s 10% off/now')
      def then_it_s_10_off_now():
          raise NotImplementedError
    PYTHON
  end

  it "writes behave stubs, with braces doubled for behave's matcher" do
    assert_equal <<~'PYTHON', StepStubs.for(@story, 'behave')
      # Step stubs for "Guests can check out". Every step is pending until a person or an agent makes it pass.
      from behave import given, then, when


      @given('a basket and no account')
      def step_impl(context):
          raise NotImplementedError('STEP: Given a basket and no account')


      @when('I continue as a guest')
      def step_impl(context):
          raise NotImplementedError('STEP: When I continue as a guest')


      @then('I can pay with my email')
      def step_impl(context):
          raise NotImplementedError('STEP: Then I can pay with my email')


      @when('I enter {{SAVE10}} (once)')
      def step_impl(context):
          raise NotImplementedError('STEP: When I enter {SAVE10} (once)')


      @then('it\'s 10% off/now')
      def step_impl(context):
          raise NotImplementedError('STEP: Then it\'s 10% off/now')
    PYTHON
  end
end
