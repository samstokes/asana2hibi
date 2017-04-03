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
      my_tasks = get_my_tasks

      sync_tasks_to_hibi(my_tasks)

      active_synced_tasks = get_active_synced_tasks

      update_existing_hibi_tasks(active_synced_tasks, my_tasks)
    rescue => e
      Raven.capture_exception e
    end

    private
    def get_my_tasks
      puts "Getting tasks for #{@asana_user.name}"

      yesterday = Time.now - SECONDS_IN_A_DAY

      Asana::Task.find_all(@asana, assignee: :me, workspace: ASANA_WORKSPACE_ID,
                           completed_since: asana_time(yesterday),
                           options: {fields: %w(name id completed assignee)}
                          ).tap do |tasks|
        puts "Got #{tasks.size} tasks from Asana: #{tasks.map(&:name).join(', ')}"
      end
    end

    def get_active_synced_tasks
      hibi_asana_tasks = @hibi.my_ext_tasks('asana')

      hibi_asana_tasks.select(&:ext_active?).tap do |active|
        puts "Got #{hibi_asana_tasks.size} tasks from Hibi, #{active.size} active: #{active.map(&:ext_id).join(', ')}"
      end
    end

    def sync_tasks_to_hibi(tasks)
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

    def update_existing_hibi_tasks(tasks, already_synced_tasks)
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

    def asana_task_to_hibi_task(task)
      assignee = task.assignee
      assignee_desc = if assignee.nil?
                        'not assigned'
                      elsif assignee['id'] == @asana_user.id
                        nil
                      else
                        assignee['name']
                      end
      status = task.completed ? 'done' : nil
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
