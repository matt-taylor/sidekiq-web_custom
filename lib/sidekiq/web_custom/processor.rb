require 'sidekiq/processor'

module Sidekiq
  module WebCustom
    class Processor < ::Sidekiq::Processor

      def self.execute(max:, queue:, options: Sidekiq.default_configuration.default_capsule)
        __processor__(queue: queue, options: options).__execute(max: max)
      end

      def self.execute_job(job:, options: Sidekiq.default_configuration.default_capsule)
        __processor__(queue: job.queue, options: options).__execute_job(job: job)
      rescue StandardError => _
        false # error gets loggged downstream
      end

      def self.__processor__(queue:, options: Sidekiq.default_configuration.default_capsule)
        options_temp = options.dup
        queue = queue.is_a?(String) ? Sidekiq::Queue.new(queue) : queue

        options_temp.queues = [queue.name]

        new(options: options_temp, queue: queue)
      end

      def initialize(options:, queue:)
        @__queue = queue
        @__basic_fetch = options.fetcher.class == BasicFetch

        super(options)
      end

      def __execute_job(job:)
        queue_name = "queue:#{job.queue}"
        work_unit = Sidekiq::BasicFetch::UnitOfWork.new(queue_name, job.item.to_json)
        begin
          logger.info "Manually processing individual work unit for #{work_unit.queue_name}"
          process(work_unit)
        rescue StandardError => e
          logger.error "Manually processed work unit failed with #{e.message}. Work unit will not be dequeued"
          raise e
        end

        begin
          job.delete
          logger.info { "Manually processed work unit sucessfully dequeued." }
        rescue StandardError => e
          logger.fatal "Manually processed work unit failed to be dequeued. #{e.message}."
          raise e
        end

        true
      end

      def __execute(max:)
        count = 0
        max.times do
          break if @__queue.size <= 0

          if Thread.current[Sidekiq::WebCustom::BREAK_BIT]
            logger.warn "Yikes -- Break bit has been set. Attempting to return in time. Completed #{count} of attempted #{max}"
            break
          end

          logger.info { "Manually processing next item in queue:[#{@__queue.name}]" }
          process_one
          count += 1
        end

        count
      rescue Exception => ex
        if @job && @__basic_fetch
          logger.fatal "Processor Execution interrupted. Lost Job #{@job.job}"
        end
        logger.warn "Manual execution has terminated. Received error [#{ex.message}]"
        return count
      end
    end
  end
end

