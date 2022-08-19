# frozen_string_literal: true

require 'sidekiq/api'

RSpec.describe Sidekiq::Queue do

  let(:worker) { Sidekiq::Queue::Worker }
  let(:queue) { described_class.new(worker.sidekiq_options['queue']) }
  let(:job_count) { 10 }
  let(:max) { job_count }

  before do
    Sidekiq::WebCustom.reset!
    Sidekiq::WebCustom.configure # inject the classes
    class Sidekiq::Queue::Worker
      include Sidekiq::Worker
      sidekiq_options queue: :test_queue
      def perform(*)
        Kernel.puts "received test message"
      end
    end
    queue.clear
    job_count.times { worker.perform_async }
  end
  after { Sidekiq::WebCustom.reset! }

  describe '#drain' do
    subject { queue.drain(max: max) }

    it 'calls custom processor' do
      expect(Sidekiq::WebCustom::Processor).to receive(:execute).with(max: max, queue: queue)

      subject
    end

    it 'calls worker logger' do
      expect(Kernel).to receive(:puts).with('received test message').exactly(max)

      subject
    end

    it { expect { subject }.to change { queue.size }.by(max * -1) }
    it { expect(subject).to eq(max) }

    context 'when queue size is less than max' do
      let(:max) { job_count * 2 }
      let(:job_count) { 2 }

      it 'calls custom processor' do
        expect(Sidekiq::WebCustom::Processor).to receive(:execute).with(max: job_count, queue: queue)

        subject
      end

      it 'calls worker logger' do
        expect(Kernel).to receive(:puts).with('received test message').exactly(job_count)

        subject
      end

      it { expect { subject }.to change { queue.size }.by(job_count * -1) }
      it { expect(subject).to eq(job_count) }
    end
  end
end
