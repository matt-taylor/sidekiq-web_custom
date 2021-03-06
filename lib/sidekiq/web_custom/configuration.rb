module Sidekiq
  module WebCustom
    class Configuration

      ALLOWED_BASED = [ACTIONS = :actions, LOCAL_ERBS = :local_erbs]
      INTEGERS = [:drain_rate, :max_execution_time, :warn_execution_time]

      DEFAULT_DRAIN_RATE = 10
      DEFAULT_EXEC_TIME = 6
      DEFAULT_WARN_TIME = 5

      attr_reader *ALLOWED_BASED
      attr_reader *INTEGERS

      def initialize
        ALLOWED_BASED.each do |var|
          instance_variable_set(:"@#{var}", {})
        end

        @drain_rate = DEFAULT_DRAIN_RATE
        @max_execution_time = DEFAULT_EXEC_TIME
        @warn_execution_time = DEFAULT_WARN_TIME
      end

      INTEGERS.each do |int|
         self.define_method("#{int}=") do |val|
          unless _allow_write_block?
            raise Sidekiq::WebCustom::ConfigurationEstablished, "Unable to assign [#{int}]. Assignment must happen on boot"
          end

          unless [Integer, Float].include?(val.class)
            raise Sidekiq::WebCustom::ArgumentError, "Expected #{int} to be an integer or float"
          end

          instance_variable_set(:"@#{int}", val)
        end
      end

      def merge(base:, params:, action_type: nil)
        unless _allow_write_block?
          raise Sidekiq::WebCustom::ConfigurationEstablished, "Unable to assign base [#{base}]. Assignment must happen on boot"
        end
        raise Sidekiq::WebCustom::ArgumentError, "Unexpected base: #{base}" unless ALLOWED_BASED.include?(base)
        raise Sidekiq::WebCustom::ArgumentError, "Expected object for #{base} to be a Hash" unless params.is_a?(Hash)

        value = instance_variable_get(:"@#{base}")
        value =
          if action_type && base == ACTIONS
            value[action_type.to_sym] ||= {}
            value[action_type.to_sym].merge!(params)
            value
          else
            value.merge(params)
          end
        instance_variable_set(:"@#{base}", value)
      end

      def validate!
        ALLOWED_BASED.each do |key|
          value = instance_variable_get(:"@#{key}")

          _validate!(value, key)
        end

        unless @warn_execution_time <= @max_execution_time
          raise Sidekiq::WebCustom::ArgumentError, "Expected warn_execution_time to be less than max_execution_time"
        end

        unless actions.keys.all? { |k| local_erbs.keys.include?(k) }
          raise Sidekiq::WebCustom::ArgumentError, "Unexpected actions keys#{actions.keys} -- Expected to be part of #{local_erbs.keys}"
        end

        define_convenienve_methods!
        _unset_allow_write!
      end

      private

      def _allow_write_block?
        true
      end

      def _unset_allow_write!
        define_singleton_method('_allow_write_block?') do
          false
        end
      end

      def define_convenienve_methods!
        actions.keys.each do |key|
          define_singleton_method("actions_for_#{key.to_s}") do
            actions[key]
          end
        end
      end

      def _validate!(params, key, add: [])
        params.each do |k, file|
          return _validate!(file, k, add: add << key) if file.is_a? Hash
          passed = [add, k].flatten.compact.join(':')


          next if File.exist?(file)

          raise Sidekiq::WebCustom::FileNotFound,
             "#{key}.merge passed #{passed}: #{file}.\n" \
            "The absolute file path does not exist."
        end
      end
    end
  end
end
