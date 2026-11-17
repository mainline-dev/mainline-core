# frozen_string_literal: true

class Mainline
  # Splitting a story: the form, and the new story made from the scenarios
  # moved out of it. routes/maps/stories.rb loads the story.
  hash_branch('maps/stories', 'split') do |r|
    r.get do
      next r.redirect("/maps/#{@map.id}") if @story.status == 'released' || @story.archived_at

      @split_scenarios = Scenario.where(story_id: @story.id, done_at: nil).order(:position).all
      @split_errors = []
      @form = {}
      view 'maps/stories/split'
    end

    r.post do
      scenario_ids = Array(r.params['scenario_ids']).grep(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
      edits = scenario_ids.to_h { |sid|
        [sid, { given: typecast_params.str("scenario_#{sid}_given"),
                when:  typecast_params.str("scenario_#{sid}_when"),
                then:  typecast_params.str("scenario_#{sid}_then") }]
      }
      template, title = template_title
      story_count = Story.where(map_id: @map.id).count
      result = if ResourceCap.stories_per_map(story_count) == :blocked
                 :map_capped
               else
                 SplitStory.call(
                   story: @story, actor: @current_actor, person: @current_person,
                   title: title, scenario_ids: scenario_ids, scenario_edits: edits
                 )
               end
      if result.is_a?(Symbol)
        @split_errors = [split_error_message(result, template)]
        @split_scenarios = Scenario.where(story_id: @story.id, done_at: nil).order(:position).all
        @form = r.params
        next view('maps/stories/split')
      end

      flash['notice'] = "Story '#{result.title}' split out from '#{@story.title}'"
      r.redirect "/maps/#{@map.id}"
    end
  end

  private

  def split_error_message(result, template = nil)
    return 'Fill in all template fields' if result == :title_required && template

    {
      released:           'Released stories cannot be split',
      archived:           'Archived stories cannot be split',
      map_capped:         'This map has reached its story limit',
      title_required:     'Name the new story before saving',
      title_too_long:     'Title must be 200 characters or fewer',
      scenario_invalid:   'Scenario fields must be 1-100 characters',
      scenarios_required: 'Select at least one scenario to split out'
    }.fetch(result)
  end
end
