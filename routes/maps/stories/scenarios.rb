# frozen_string_literal: true

class Mainline
  # A story's acceptance scenarios: adding one, and editing, marking done or
  # not done, and removing each. routes/maps/stories.rb loads the story.
  hash_branch('maps/stories', 'scenarios') do |r|
    r.is do
      r.get do
        @scenarios = @story.scenarios
        @scenario_errors = []
        render('maps/stories/_scenarios')
      end

      r.post do
        next render('maps/stories/_scenarios') if @story.status == 'released'

        name  = typecast_params.str('name').to_s.strip
        given = typecast_params.str('given').to_s.strip
        whn   = typecast_params.str('when').to_s.strip
        thn   = typecast_params.str('then').to_s.strip

        @scenario_errors = AddScenario.call(story: @story, actor: @current_actor, name: name, given_text: given,
          when_text: whn, then_text: thn).errors

        @scenarios = Scenario.where(story_id: @story.id).order(:position).all
        with_preview(render('maps/stories/_scenarios'))
      end
    end

    r.on String do |scenario_id|
      next unless scenario_id.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)

      scenario = Scenario[scenario_id]
      next unless scenario && scenario.story_id == @story.id

      r.post 'delete' do
        RemoveScenario.call(story: @story, scenario: scenario, actor: @current_actor)
        @scenarios = Scenario.where(story_id: @story.id).order(:position).all
        @scenario_errors = []
        with_preview(render('maps/stories/_scenarios'))
      end

      r.post 'done' do
        MarkScenario.done(story: @story, scenario: scenario, actor: @current_actor, now: Time.now)
        @scenarios = Scenario.where(story_id: @story.id).order(:position).all
        @scenario_errors = []
        with_preview(render('maps/stories/_scenarios'))
      end

      r.post 'undone' do
        MarkScenario.undone(story: @story, scenario: scenario, actor: @current_actor)
        @scenarios = Scenario.where(story_id: @story.id).order(:position).all
        @scenario_errors = []
        with_preview(render('maps/stories/_scenarios'))
      end

      r.is do
        r.post do
          next render('maps/stories/_scenarios') if @story.status == 'released'

          @scenario_errors = EditScenario.call(
            story: @story, scenario: scenario, actor: @current_actor,
            name: typecast_params.str('name').to_s.strip, given_text: typecast_params.str('given').to_s.strip,
            when_text: typecast_params.str('when').to_s.strip, then_text: typecast_params.str('then').to_s.strip
          ).errors

          @scenarios = Scenario.where(story_id: @story.id).order(:position).all
          with_preview(render('maps/stories/_scenarios'))
        end
      end
    end
  end
end
