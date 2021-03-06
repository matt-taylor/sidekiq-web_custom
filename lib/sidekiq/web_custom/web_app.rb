# frozen_string_literal: true

require 'timeoutable'

module Sidekiq
  module WebCustom
    class WebApp
      MAPPED_TYPE = {
        retries: RetrySet,
        scheduled: ScheduledSet,
      }
      def self.registered(app)
        app.post '/queues/drain/:name' do
          timeout_params = {
            warn: Sidekiq::WebCustom.config.warn_execution_time,
            timeout: Sidekiq::WebCustom.config.max_execution_time,
            proc: ->(thread, seconds) { thread[Sidekiq::WebCustom::BREAK_BIT] = 1; Sidekiq.logger.warn "set bit #{thread[Sidekiq::WebCustom::BREAK_BIT]}" }
          }
          Thread.current[Sidekiq::WebCustom::BREAK_BIT] = nil
          ::Timeoutable.timeout(**timeout_params) do
            Sidekiq::Queue.new(params[:name]).drain(max: Sidekiq::WebCustom.config.drain_rate)
          end
          redirect_with_query("#{root_path}queues")
        end

        app.post '/job/delete' do
          parsed = parse_params(params['entry.score'])

          klass = MAPPED_TYPE[params['entry.type'].to_sym]
          job = klass.new.fetch(*parsed)&.first

          job&.delete
          redirect_with_query("#{root_path}scheduled")
        end

        app.post '/job/execute' do
          parsed = parse_params(params['entry.score'])

          klass = MAPPED_TYPE[params['entry.type'].to_sym]
          job = klass.new.fetch(*parsed)&.first

          status = job&.execute
          redirect_with_query("#{root_path}#{params['entry.type']}")
        end
      end
    end
  end
end
