# frozen_string_literal: true

class Mainline
  hash_branch('teams', 'museum') do |r|
    @museum_path = "/teams/#{@team.id}/museum"

    r.get true do
      @filters = %w[search type label epic age status why source].to_h { |name| [name.to_sym, typecast_params.nonempty_str(name)] }.compact
      stale_why = @filters.delete(:why) unless @filters[:status] == 'in-storage'
      @museum = MuseumList.call(team_id: @team.id, **@filters, page: typecast_params.pos_int('page', 1))
      @open_key = typecast_params.nonempty_str('open')
      page_path = ->(page) { "#{@museum_path}?#{URI.encode_www_form(@filters.merge(page: page))}" }
      @previous_path = page_path.call(@museum.page - 1) if @museum.page > 1
      @next_path = page_path.call(@museum.page + 1) if @museum.page < @museum.pages
      response['HX-Push-Url'] = museum_filter_path({}) if stale_why
      next render('teams/museum/_results', locals: { in_place: true }) if request.env['HTTP_HX_REQUEST']

      @empty = MuseumItem.where(team_id: @team.id).empty?
      @no_tasks = !@empty && promotable_tasks.empty?
      @let_go_prompt = LetGoPrompt.call(team: @team)
      @let_go_tries = 1 if flash['let_go_watch']
      @waiting = MuseumImport.where(team_id: @team.id, status: 'staged').reverse(:created_at).first
      @page_title = 'Ticket Museum - Mainline'
      view 'museum'
    end

    r.is 'import' do
      r.get do
        @source = museum_source(typecast_params.nonempty_str('source'))
        museum_upload_page
      end

      r.post do
        unless MUSEUM_UPLOAD_RATE_LIMITER.allow?(@team.id)
          flash['error'] = 'Too many uploads. Try again later.'
          r.redirect "/teams/#{@team.id}/museum/import"
        end

        upload = r.params['csv']
        unless upload.is_a?(Hash) && upload[:tempfile]
          flash['error'] = 'Choose a file to acquire'
          r.redirect "/teams/#{@team.id}/museum/import"
        end

        @source = museum_source(typecast_params.nonempty_str('source'), file_name: upload[:filename])
        staged = ImportToMuseum.stage(team: @team, actor: @current_actor, file_name: upload[:filename],
          csv: upload[:tempfile].read(JiraCsv::MAX_BYTES + 1).to_s, source: @source)
        r.redirect "/teams/#{@team.id}/museum/imports/#{staged.import.id}" if staged.success?

        if staged.problems.empty?
          flash['error'] = staged.errors.first
          r.redirect "/teams/#{@team.id}/museum/import"
        end

        # A file refused for what is in it: every problem goes on the page, to
        # correct in one go.
        @refused = { file_name: upload[:filename].to_s, problems: staged.problems, sentences: staged.errors }
        response.status = 422
        museum_upload_page
      end
    end

    r.on 'imports', String do |import_id|
      next unless import_id.match?(MUSEUM_ID)

      @import = MuseumImport.where(team_id: @team.id, id: import_id).first
      next unless @import

      r.get true do
        @preview = ImportToMuseum.preview(@import) if @import.status == 'staged'
        @plan = LayOutMap.plan(team: @team, import: @import) if @preview && @import.backbone
        @hours_left = museum_hours_left(@import)
        @page_title = "Acquisition #{@import.file_name} - Mainline"
        view 'import'
      end

      r.get 'problems.csv' do
        response['Content-Type'] = 'text/csv; charset=utf-8'
        safe_name = File.basename(@import.file_name, '.*').gsub(/[^\w -]/, '')
        response['Content-Disposition'] = %(attachment; filename="#{safe_name}-problems.csv")
        JiraCsv.problems_csv(header: @import.header.to_a, problems: @import.problems.to_a)
      end

      r.post 'apply' do
        layout = if @import.backbone
                   { map: typecast_params.nonempty_str('map'), activities: Array(r.params['activities']).grep(/\A\d+\z/).map(&:to_i),
                     steps: Array(r.params['steps']).grep(/\A\d+:\d+\z/) }
                 end
        result = ImportToMuseum.apply(import: @import, actor: @current_actor, layout: layout)
        if result.success?
          flash['notice'] = import_notice(result)
          # Once the exhibits are committed, or the curator looks at a museum without them.
          DB.after_commit(savepoint: true) { LetGoJob.perform_async(@team.id) }
          flash['let_go_watch'] = true
        else
          flash['error'] = result.errors.first
        end
        r.redirect "/teams/#{@team.id}/museum"
      end

      r.post 'undo' do
        result = ImportToMuseum.undo(import: @import, actor: @current_actor)
        if result.success?
          flash['notice'] = "#{@import.file_name} returned: #{result.removed} exhibits removed, #{result.restored} put back as they were" \
                            "#{", #{result.kept} promoted or discarded since, kept" if result.kept.positive?}"
        else
          flash['error'] = result.errors.first
        end
        r.redirect "/teams/#{@team.id}/museum"
      end

      r.post 'cancel' do
        result = ImportToMuseum.cancel(import: @import)
        if result.success?
          flash['notice'] = "#{@import.file_name} turned down; the museum is as it was"
        else
          flash['error'] = result.errors.first
        end
        r.redirect "/teams/#{@team.id}/museum"
      end
    end

    r.get 'stories' do
      items = MuseumItem.where(team_id: @team.id, id: typecast_params.str('for').to_s.split(',').grep(MUSEUM_ID)).all
      suggestion = StoryPicker.suggestion(items: items)
      chosen = typecast_params.nonempty_str('story_id') || suggestion&.story_id
      query = typecast_params.str('q')
      groups = StoryPicker.call(team_id: @team.id, query: query, suggested: chosen)
      render('teams/museum/_story_hits', locals: { groups: groups, suggestion: suggestion, chosen: chosen, query: query })
    end

    r.post 'add-to-story' do
      return_to = museum_return_path(r.params['return_to'])
      items = MuseumItem.where(team_id: @team.id, id: museum_strs('ids').grep(MUSEUM_ID)).order(:source_key).all
      story_id = typecast_params.nonempty_str('story_id')
      result = AddToStory.call(items: items, story_id: (story_id if story_id&.match?(MUSEUM_ID)), team: @team, actor: @current_actor)
      if result.success?
        museum_added_toast(items, result)
        r.redirect return_to
      end

      next museum_refusal(result.errors.first) if r.env['HTTP_HX_REQUEST']

      flash['error'] = result.errors.first
      r.redirect return_to
    end

    r.post 'added', String, 'undo' do |batch|
      next unless batch.match?(MUSEUM_ID)

      back = AddToStory.undo(team_id: @team.id, actor: @current_actor, batch: batch)
      back.zero? ? flash['error'] = 'Nothing to send back' : museum_count_toast(back, 'back in their cases')
      r.redirect museum_return_path(r.params['return_to'])
    end

    r.on 'together' do
      @return_to = museum_return_path(r.params['return_to'])

      r.post String, 'undo' do |batch|
        next unless batch.match?(MUSEUM_ID)

        undone = PromoteMuseumItem.undo(team_id: @team.id, actor: @current_actor, batch: batch)
        if undone.back.zero?
          flash['error'] = 'Nothing to send back'
        else
          museum_count_toast(undone.back, "back in their cases; #{museum_story_fate(undone.story_archived)}",
            story_state: undone.story_archived ? 'archived' : 'kept')
        end
        r.redirect @return_to
      end

      museum_together(museum_strs('ids').grep(MUSEUM_ID))
      if @items.empty?
        flash['error'] = 'Nothing there can be promoted'
        r.redirect @return_to
      end

      r.post 'promote' do
        @title = museum_posted_title
        @selected_task_id = typecast_params.nonempty_str('task_id')
        @scenarios = museum_scenarios(r.params['scenarios'])
        task_id = @selected_task_id if @selected_task_id&.match?(MUSEUM_ID)
        result = PromoteMuseumItem.together(items: @items, team: @team, actor: @current_actor, person: @current_person,
          title: @title, task_id: task_id, scenarios: @scenarios)
        if result.success?
          session["museum_task:#{@team.id}"] = result.story.task_id
          museum_count_toast(@items.size, 'promoted together as', story: result.story,
            undo: "#{@museum_path}/together/#{result.batch}/undo")
          r.redirect @return_to
        end

        @errors = result.errors
        view 'together'
      end

      r.post true do
        @mode = r.params['mode'] == 'add' ? 'add' : 'new'
        @selected_task_id = remembered_museum_task
        @remembered_task = !@selected_task_id.nil?
        view 'together'
      end
    end

    r.on 'let-go' do
      r.get 'prompt' do
        tries = typecast_params.pos_int('tries', 1)
        render('teams/museum/_let_go_prompt', locals: {
          prompt: LetGoPrompt.call(team: @team), tries: (tries + 1 if tries < LetGoPrompt::WATCH_TRIES), back: @museum_path
        })
      end

      r.post 'snooze' do
        LetGoPrompt.snooze(team: @team, actor: @current_actor)
        r.redirect museum_return_path(r.params['return_to'])
      end

      r.get 'done' do
        @gone = flash['let_go_done']
        r.redirect @museum_path unless @gone

        @left = MuseumList.on_display(@team.id).count
        museum_count_toast(@gone, 'let go to storage', dot: 'stored', undo: "#{@museum_path}/let-go/undo")
        @page_title = 'Let go - Mainline'
        view 'let_go_done'
      end

      r.post 'undo' do
        back = LetGoReview.undo(team_id: @team.id, actor: @current_actor, batch: session.delete("let_go_batch:#{@team.id}"))
        back.zero? ? flash['error'] = 'Nothing to undo' : museum_count_toast(back, 'brought out of storage')
        r.redirect museum_return_path(r.params['return_to'])
      end

      r.get 'more' do
        group = LetGoReview.groups(team_id: @team.id).find { |one| one.id == typecast_params.nonempty_str('group') }
        next unless group

        render('teams/museum/_let_go_page', locals: {
          group: group, offset: typecast_params.pos_int('offset', group.limit), size: LetGoReview::PAGE,
          ticked: museum_strs('rest').include?(group.id)
        })
      end

      r.is do
        r.get do
          @groups = LetGoReview.groups(team_id: @team.id)
          @on_display = MuseumList.on_display(@team.id).count
          @page_title = 'Let go - Mainline'
          view 'let_go'
        end

        r.post do
          pairs = r.params['pairs'].is_a?(Hash) ? r.params['pairs'] : {}
          outcome = LetGoReview.let_go(team_id: @team.id, actor: @current_actor, ids: (museum_strs('ids') + pairs.values).grep(MUSEUM_ID),
            seen: museum_strs('seen').grep(MUSEUM_ID), rest: museum_strs('rest'),
            keep: pairs.select { |_name, value| value == 'both' }.keys)
          if outcome.gone.zero?
            flash['notice'] = 'Nothing let go'
            r.redirect @museum_path
          end

          session["let_go_batch:#{@team.id}"] = outcome.batch
          flash['let_go_done'] = outcome.gone
          r.redirect "#{@museum_path}/let-go/done"
        end
      end
    end

    r.post 'discard' do
      ids = (typecast_params.array(:str, 'ids') || []).grep(MUSEUM_ID).uniq
      sent = DiscardMuseumItem.many(items: MuseumItem.where(team_id: @team.id, id: ids).all, actor: @current_actor)
      museum_count_toast(sent.stored, 'sent to storage', dot: 'stored', undo: "#{@museum_path}/stored/#{sent.batch}/undo")
      r.redirect museum_return_path(r.params['return_to'])
    end

    r.post 'stored', String, 'undo' do |batch|
      next unless batch.match?(MUSEUM_ID)

      back = DiscardMuseumItem.restore_batch(team_id: @team.id, actor: @current_actor, batch: batch)
      back.zero? ? flash['error'] = 'Nothing to bring back' : museum_count_toast(back, 'brought out of storage')
      r.redirect museum_return_path(r.params['return_to'])
    end

    r.on String do |item_id|
      next unless item_id.match?(MUSEUM_ID)

      @item = MuseumItem.where(team_id: @team.id, id: item_id).first
      next unless @item

      r.get 'case' do
        sub_tasks = MuseumItem.where(team_id: @team.id, parent_key: @item.source_key).order(:source_key).all
        museum_case(@item, sub_tasks, museum_return_path(r.params['return_to']))
      end

      r.is 'promote' do
        @tasks_by_map = promotable_tasks
        @page_title = "Promote #{@item.source_key} - Mainline"
        @return_to = museum_return_path(r.params['return_to'])
        @sub_tasks = MuseumItem.where(team_id: @team.id, parent_key: @item.source_key).order(:source_key).all

        r.get do
          suggestion = museum_suggestion(@item)
          @title = suggestion[:title]
          @scenarios = suggestion[:scenarios]
          @selected_task_id = suggestion[:task_id] || remembered_museum_task
          @remembered_task = suggestion[:task_id].nil? && !@selected_task_id.nil?
          view 'promote'
        end

        r.post do
          @title = museum_posted_title
          @selected_task_id = typecast_params.nonempty_str('task_id')
          @scenarios = museum_scenarios(r.params['scenarios'])
          task_id = @selected_task_id if @selected_task_id&.match?(MUSEUM_ID)
          result = PromoteMuseumItem.call(item: @item, team: @team, actor: @current_actor, person: @current_person,
            title: @title, task_id: task_id, scenarios: @scenarios)
          if result.success?
            session["museum_task:#{@team.id}"] = result.story.task_id
            museum_toast(@item, 'has a second life as', story: result.story, undo: 'unpromote')
            r.redirect @return_to
          end

          next museum_refusal(result.errors.first) if r.env['HTTP_HX_REQUEST']

          @errors = result.errors
          view 'promote'
        end
      end

      r.post 'keep' do
        next unless @item.let_go_group

        LetGoReview.keep(item: @item, actor: @current_actor)
        render('teams/museum/_let_go_row', locals: { suggestion: LetGoReview.suggestion(@item), ticked: false })
      end

      r.post 'unkeep' do
        next unless @item.kept_at

        LetGoReview.unkeep(item: @item, actor: @current_actor)
        if request.env['HTTP_HX_REQUEST']
          next render('teams/museum/_let_go_row', locals: { suggestion: LetGoReview.suggestion(@item), ticked: true })
        end

        museum_toast(@item, 'can be suggested again')
        r.redirect museum_return_path(r.params['return_to'])
      end

      r.post 'unpromote' do
        result = UnpromoteMuseumItem.call(item: @item, actor: @current_actor)
        if result.success?
          museum_toast(@item, "is back in its case; #{museum_story_fate(result.story_archived)}",
            story_state: result.story_archived ? 'archived' : 'kept')
        else
          flash['error'] = result.errors.first
        end
        r.redirect museum_return_path(r.params['return_to'])
      end

      r.post 'discard' do
        result = DiscardMuseumItem.call(item: @item, actor: @current_actor)
        result.success? ? museum_toast(@item, 'sent to storage', dot: 'stored', undo: 'restore') : flash['error'] = result.errors.first
        r.redirect museum_return_path(r.params['return_to'])
      end

      r.post 'restore' do
        result = DiscardMuseumItem.restore(item: @item, actor: @current_actor)
        result.success? ? museum_toast(@item, 'brought out of storage') : flash['error'] = result.errors.first
        r.redirect museum_return_path(r.params['return_to'])
      end
    end
  end
end
