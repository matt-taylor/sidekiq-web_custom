# frozen_string_literal: true

require 'sidekiq/api'

RSpec.describe Sidekiq::Job do

  let(:worker) { Sidekiq::Job::Worker }
  let(:queue) { Sidekiq::Queue.new(worker.sidekiq_options['queue']) }
  let(:job) { queue.first }
  let(:job_count) { 1 }

  before do
    Sidekiq::WebCustom.reset!
    Sidekiq::WebCustom.configure # inject the classes
    class Sidekiq::Job::Worker
      include Sidekiq::Worker
      sidekiq_options queue: :test_queue
      def perform(*)
        Sidekiq.logger.info "received test message"
      end
    end
    queue.clear
    allow(Sidekiq).to receive(:logger).and_return(Logger.new('/dev/null'))
    allow(Sidekiq.logger).to receive(:info)
    job_count.times { worker.perform_async }
  end
  after { Sidekiq::WebCustom.reset! }

  describe '#execute' do
    subject { job.execute }

    it 'worker performs' do
      expect_any_instance_of(worker).to receive(:perform).and_call_original

      subject
    end

    it 'calls custom processor' do
      expect(Sidekiq::WebCustom::Processor).to receive(:execute_job).with(job: job)

      subject
    end

    it 'calls worker logger' do
      expect(Sidekiq.logger).to receive(:info).with('received test message')

      subject
    end

    it { expect { subject }.to change { queue.size }.by(-1) }
  end
end
