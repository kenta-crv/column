namespace :sidekiq do
  desc "Remove stale jobs whose constants are not defined in this app (e.g. DealFollowUp)"
  task purge_orphans: :environment do
    require "sidekiq/api"

    deleted = 0

  purge = lambda do |collection, label|
    collection.each do |job|
      item = job.respond_to?(:item) ? job.item : job
      klass = item["class"].to_s
      constant_name = if klass.include?("JobWrapper")
                        item.dig("args", 0, "job_class")
                      else
                        klass
                      end
      next if constant_name.blank?

      begin
        constant_name.constantize
      rescue NameError
        job.delete
        deleted += 1
        puts "deleted: #{constant_name} (#{label})"
      end
    end
  end

    Sidekiq::Queue.all.each { |queue| purge.call(queue, queue.name) }
    purge.call(Sidekiq::RetrySet.new, "retry")
    purge.call(Sidekiq::ScheduledSet.new, "scheduled")
    purge.call(Sidekiq::DeadSet.new, "dead")

    puts "done. deleted #{deleted} orphan job(s)."
  end
end
