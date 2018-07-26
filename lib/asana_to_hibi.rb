require 'asana'
require 'hibi'
require 'raven'

SECONDS_IN_A_DAY = 24 * 60 * 60

module AsanaToHibi
  class Client
    def initialize(opts = {})
      @hibi = opts.fetch :hibi
      @asana = opts.fetch :asana
      @asana_user = Asana::User.me(@asana)
    end

    def sync
      span :sync do
        my_tasks = get_my_tasks

        sync_tasks_to_hibi(my_tasks)

        active_synced_tasks = get_active_synced_tasks

        update_existing_hibi_tasks(active_synced_tasks, my_tasks)
      end
    rescue => e
      Raven.capture_exception e
    end

    private
    def span(name)
      Honeycomb.span(service_name: SERVICE_NAME, name: name) { yield }
    end

    def get_my_tasks
      span :get_my_tasks do
        puts "Getting tasks for #{@asana_user.name}"

        yesterday = Time.now - SECONDS_IN_A_DAY

        Asana::Task.find_all(@asana, assignee: :me, workspace: ASANA_WORKSPACE_ID,
                             completed_since: asana_time(yesterday),
                             options: {
                               fields: %w(
                                 name
                                 id
                                 completed
                                 assignee
                                 assignee_status
                                 memberships.project.id
                                 memberships.section.id
                                 memberships.section.name
                                 due_on
                               )
                             }
                            )
          .reject do |task|
            if ASANA_MAIN_PROJECT_ID.nil?
              if task.completed
                false
              elsif task.assignee_status != 'today' && task.assignee_status != 'upcoming'
                puts "Ignoring task #{task.id} (#{task.name}) because scheduled for '#{task.assignee_status}'"
                true
              else
                false
              end
            elsif membership = task.memberships.detect {|ship| ship['project']['id'] == ASANA_MAIN_PROJECT_ID }
              section = membership['section']
              if !ASANA_MAIN_PROJECT_SECTION_ID
                false
              elsif section && ASANA_MAIN_PROJECT_SECTION_ID == section['id']
                false
              else
                puts "Ignoring task #{task.id} (#{task.name}) because not in main section"
                true
              end
            else
              puts "Ignoring task #{task.id} (#{task.name}) because not in main project"
              true
            end
          end
          .tap do |tasks|
          puts "Got #{tasks.size} tasks from Asana: #{tasks.map(&:name).join(', ')}"
        end
      end
    end

    def get_active_synced_tasks
      span :get_active_synced_tasks do
        hibi_asana_tasks = @hibi.my_ext_tasks('asana')

        hibi_asana_tasks.select(&:ext_active?).tap do |active|
          puts "Got #{hibi_asana_tasks.size} tasks from Hibi, #{active.size} active: #{active.map(&:ext_id).join(', ')}"
        end
      end
    end

    def sync_tasks_to_hibi(tasks)
      span :sync_tasks_to_hibi do
        errors = []
        tasks.each do |task|
          begin
            @hibi.create_or_update_task(asana_task_to_hibi_task(task))
          rescue => e
            puts "Failed to update task #{task.id} (#{task.name}) to Hibi!\n#{e}"
            Raven.capture_exception e
            errors << e
          end
        end
        puts "Synced #{tasks.size - errors.size} of my tasks to Hibi, #{errors.size} errors."
      end
    end

    def update_existing_hibi_tasks(tasks, already_synced_tasks)
      span :update_existing_hibi_tasks do
        yet_unsynced_ids = tasks.map(&:ext_id) - already_synced_tasks.map(&:id)
        puts "#{yet_unsynced_ids.size} need syncing: #{yet_unsynced_ids.join(', ')}"

        errors = []
        yet_unsynced_ids.each do |id|
          begin
            task = Asana::Task.find_by_id(@asana, id)
            @hibi.create_or_update_task(asana_task_to_hibi_task(task))
          rescue => e
            puts "Failed to sync task #{id} (#{task.name if task}) to Hibi!\n#{e}"
            Raven.capture_exception e
            errors << e
          end
        end
        puts "Synced #{yet_unsynced_ids.size} tasks from Asana, #{errors.size} errors."
      end
    end

    def asana_task_to_hibi_task(task)
      assignee = task.assignee
      assignee_desc = if assignee.nil?
                        'not assigned'
                      elsif assignee['id'] == @asana_user.id
                        nil
                      else
                        assignee['name']
                      end
      status = if task.completed
        'done'
      elsif task.due_on
        "due #{task.due_on}"
      elsif task.assignee_status == 'today'
        'today'
      else
        nil
      end
      Hibi::Task.new(
        ext_id: task.id.to_s,
        title: task.name,
        schedule: 'Once',
        ext_source: 'asana',
        ext_url: asana_task_url(task),
        ext_status: status,
        ext_assignee: assignee_desc,
      )
    end

    def asana_time(time)
      time.strftime('%Y-%m-%dT%H:%M:%S%z')
    end

    def asana_task_url(task)
      "https://app.asana.com/0/#{ASANA_WORKSPACE_ID}/#{task.id}"
    end
  end
end
