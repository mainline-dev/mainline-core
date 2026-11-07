# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Story drag (browser)' do
  include MainlineDSL

  before do
    setup_team
    add_person(name: 'Alice')
    create_map
    persona  = create_persona('Customer')
    activity = create_activity('Browse', for_personas: [persona])
    @task    = create_task('Search', under_activity: activity)
    @story_a = create_story('Story A', under_task: @task)
    @story_b = create_story('Story B', under_task: @task)
    @story_c = create_story('Story C', under_task: @task)
  end

  # The page sends reorders one after another; reloading it to check would
  # abandon any still queued, so this waits on the saved order and then loads
  # the map once.
  def wait_for_order(*stories, timeout: 5)
    expected = stories.map(&:id)
    deadline = Time.now + timeout
    loop do
      break if Story.where(id: expected).order(:position).select_map(:id) == expected
      raise 'Reorder not saved in the dragged order' if Time.now > deadline

      sleep 0.2
    end
    driver.visit_map(@map)
  end

  it 'rapid back-to-back drags apply in order' do
    use_browser!
    driver.visit_map(@map)

    assert_selector '.task-stories[data-task-id] .story-card', minimum: 3

    page.execute_script(<<~JS)
      var container = document.querySelector('.task-stories[data-task-id]');
      var sortable = Sortable.get(container);

      var cards1 = container.querySelectorAll('.story-card');
      container.insertBefore(cards1[1], cards1[0]);
      sortable.option('onEnd')({to: container, from: container, item: cards1[1], oldIndex: 1, newIndex: 0});

      var cards2 = container.querySelectorAll('.story-card');
      container.insertBefore(cards2[2], cards2[0]);
      sortable.option('onEnd')({to: container, from: container, item: cards2[2], oldIndex: 2, newIndex: 0});
    JS

    wait_for_order(@story_c, @story_b, @story_a)

    selector = '.task-stories[data-task-id] .story-card [data-test-id^="story-title-"]'
    titles = all(selector).map(&:text)

    assert_equal 'Story C', titles[0]
    assert_equal 'Story B', titles[1]
    assert_equal 'Story A', titles[2]
  end

  it 'drags a story from one slice to another' do
    slice_a = create_release_slice('MVP')
    slice_b = create_release_slice('Beta')
    move_story_to_slice(@story_a, release_slice_id: slice_a.id)
    move_story_to_slice(@story_b, release_slice_id: slice_b.id)

    use_browser!

    driver.visit_map_slices(@map)

    assert_selector ".task-stories[data-slice-id='#{slice_a.id}'] .story-card"
    assert_selector ".task-stories[data-slice-id='#{slice_b.id}']"

    # A move across slices saves, then the page reloads the grid from the
    # server. The test waits for that reload: a reload still in flight when the
    # test ends would reach the server after its data is rolled back.
    page.execute_script(<<~JS)
      document.body.addEventListener('htmx:afterSettle', function() {
        document.body.dataset.gridRefreshed = 'true';
      }, {once: true});
      var sourceContainer = document.querySelector('.task-stories[data-slice-id="#{slice_a.id}"]');
      var targetContainer = document.querySelector('.task-stories[data-slice-id="#{slice_b.id}"]');
      var card = sourceContainer.querySelector('.story-card');
      sourceContainer.removeChild(card);
      targetContainer.appendChild(card);
      var sortable = Sortable.get(sourceContainer);
      sortable.option('onEnd')({
        to: targetContainer, from: sourceContainer, item: card,
        oldIndex: 0, newIndex: targetContainer.querySelectorAll('.story-card').length - 1
      });
    JS

    assert_selector 'body[data-grid-refreshed]'
    assert_selector ".task-stories[data-slice-id='#{slice_b.id}'] [data-test-id='story-title-story-a']"
    assert_equal slice_b.id, @story_a.refresh.release_slice_id
  end

  it 'programmatic reorder persists after page reload' do
    use_browser!
    driver.visit_map(@map)

    assert_selector '.task-stories[data-task-id] .story-card', minimum: 2

    page.execute_script(<<~JS)
      var container = document.querySelector('.task-stories[data-task-id]');
      var cards = container.querySelectorAll('.story-card');
      container.insertBefore(cards[1], cards[0]);
      var sortable = Sortable.get(container);
      sortable.option('onEnd')({to: container, from: container, item: cards[1], oldIndex: 1, newIndex: 0});
    JS

    wait_for_order(@story_b, @story_a, @story_c)

    selector = '.task-stories[data-task-id] .story-card [data-test-id^="story-title-"]'
    titles = all(selector).map(&:text)

    assert_equal 'Story B', titles[0]
    assert_equal 'Story A', titles[1]
  end
end
