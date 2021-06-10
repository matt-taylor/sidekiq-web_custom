require 'sidekiq/api'
require 'sidekiq/web'
require 'sidekiq/util'
require 'rack/test'

RSpec.describe Sidekiq::Web do
  include Rack::Test::Methods

  let(:app) { described_class}
  let(:worker) { Sidekiq::Web::Worker }
  let(:queue) { Sidekiq::Queue.new(worker.sidekiq_options['queue']) }
  let(:job_count) { 5 }
  let(:max) { job_count }

  before do
    # We are not testing this here -- it requires a full application setup
    allow_any_instance_of(Sidekiq::Web::CsrfProtection).to receive(:session).and_return({})
    allow_any_instance_of(Sidekiq::Web::CsrfProtection).to receive(:accept?).and_return(true)
    Sidekiq::WebCustom.reset!
    Sidekiq::WebCustom.configure # inject the classes
    class Sidekiq::Web::Worker
      include Sidekiq::Worker
      sidekiq_options queue: :test_queue
      def perform(*)
        Sidekiq.logger.info "received test message"
      end
    end
    queue.clear
    allow(Sidekiq).to receive(:logger).and_return(Logger.new('/dev/null'))
    allow(Sidekiq.logger).to receive(:info)
    allow(Sidekiq.logger).to receive(:warn)
    job_count.times { worker.perform_async }
  end
  after { queue.clear; Sidekiq::WebCustom.reset! }

  describe 'queues/drain/:name' do
    subject { post "/queues/drain/#{queue.name}" }

    let(:timeout_params) do
      {
        warn: Sidekiq::WebCustom.config.warn_execution_time,
        timeout: Sidekiq::WebCustom.config.max_execution_time,
        proc: be_a(Proc)
      }
    end
    it { expect { subject }.to change { queue.size }.by(-max) }

    it 'returns 302' do
      subject

      expect(last_response.status).to eq 302
    end

    it 'timeout correctly called' do
      expect(Sidekiq::WebCustom::Timeout).to receive(:timeout).with(timeout_params).and_call_original

      subject
    end

    it 'queue correctly called' do
      expect(Sidekiq::Queue).to receive(:new).with(queue.name).and_call_original

      subject
    end

    it 'drain correctly called' do
      allow(Sidekiq::Queue).to receive(:new).with(queue.name).and_return(queue)
      expect(queue).to receive(:drain).with(max: Sidekiq::WebCustom.config.drain_rate).and_call_original

      subject
    end

    context 'when job fails' do
      let(:worker2) { BlahBlahWorker }
      let(:queue2) { Sidekiq::Queue.new(worker2.sidekiq_options['queue']) }
      before do
        class BlahBlahWorker
          include Sidekiq::Worker
          sidekiq_options queue: :test_queue
          def perform(*)
            raise StandardError, 'Yikes -- I failed'
          end
        end
        queue2.clear
        job_count.times { worker2.perform_async }
      end
      after { queue2.clear }

      it { expect { subject }.to change { queue2.size }.by(-1) }

      it 'returns 302' do
        subject

        expect(last_response.status).to eq 302
      end
    end

    context 'when job takes too long' do
      let(:worker2) { RaiseMyWorker }
      let(:queue2) { Sidekiq::Queue.new(worker2.sidekiq_options['queue']) }
      let(:job_count) { 10 }
      before do
        Sidekiq::WebCustom.reset!
        Sidekiq::WebCustom.configure do |config|
          config.max_execution_time = 1.0
          config.warn_execution_time = 0.75
        end
        class RaiseMyWorker
          include Sidekiq::Worker
          sidekiq_options queue: :test_queue
          def perform(*)
            sleep(0.1)
          end
        end
        queue2.clear
        job_count.times { worker2.perform_async }
        Thread.current[Sidekiq::WebCustom::BREAK_BIT] = nil
      end
      after do
        queue2.clear
        Thread.current[Sidekiq::WebCustom::BREAK_BIT] = nil
        Sidekiq::WebCustom.reset!
      end

      it 'logger message gets hit' do
        expect(Sidekiq.logger).to receive(:warn).with(/Yikes -- Break bit has been set/)

        subject
      end

      it 'returns 302' do
        subject

        expect(last_response.status).to eq 302
      end
    end

    context 'when job reallly takes too long' do
      before do
        Sidekiq::WebCustom.reset!
        Sidekiq::WebCustom.configure do |config|
          config.max_execution_time = 0.1
          config.warn_execution_time = 0.05
        end
         Thread.current[Sidekiq::WebCustom::BREAK_BIT] = nil
      end

      after {  Thread.current[Sidekiq::WebCustom::BREAK_BIT] = nil }

      it 'returns 302' do
        subject

        expect(last_response.status).to eq 302
      end
    end
  end

  describe 'job/delete' do
    subject { post '/job/delete', data }

    before { job_count.times { worker.perform_in(1000) } }
    after { Sidekiq::ScheduledSet.new.clear; Sidekiq::RetrySet.new.clear; }

    let(:sorted_klass) { Sidekiq::ScheduledSet }
    let(:job) { sorted_klass.new.first }
    let(:params) { "#{job.score}-#{job['jid']}" }
    let(:data) { { 'entry.score' => params, 'entry.type' => "scheduled"} }
    let(:jobset) { sorted_klass.new.find_job(job.jid) }
    it 'returns 302' do
      subject

      expect(last_response.status).to eq 302
    end

    it 'removes from scheduled set' do
      expect { subject }.to change { Sidekiq::ScheduledSet.new.size }.by(-1)
    end

    it 'deletes job' do
      subject

      expect(jobset).to be_nil
    end

    context 'when job does not exist' do
      let(:params) { "#{job.score}-#{job['jid']}#{(rand*1000).to_i}" }

      it { expect { subject }.to_not change { Sidekiq::ScheduledSet.new.size } }
    end
  end

  describe 'job/execute' do
    subject { post '/job/execute', data }

    before { job_count.times { worker.perform_in(1000) } }
    after { Sidekiq::ScheduledSet.new.clear; Sidekiq::RetrySet.new.clear; }
    let(:sorted_klass) { Sidekiq::ScheduledSet }
    let(:job) { sorted_klass.new.first }
    let(:params) { "#{job.score}-#{job['jid']}" }
    let(:data) { { 'entry.score' => params, 'entry.type' => "scheduled"} }
    let(:jobset) { sorted_klass.new.find_job(job.jid) }
    it 'returns 302' do
      subject

      expect(last_response.status).to eq 302
    end

    it 'removes from scheduled set after execution' do
      expect { subject }.to change { Sidekiq::ScheduledSet.new.size }.by(-1)
    end

    it 'executes job' do
      expect(Sidekiq.logger).to receive(:info).with(/received test message/)

      subject
    end

    it 'deletes job after execution' do
      subject

      expect(jobset).to be_nil
    end

    context 'when job does not exist' do
      let(:params) { "#{job.score}-#{job['jid']}#{(rand*1000).to_i}" }

      it { expect { subject }.to_not change { Sidekiq::ScheduledSet.new.size } }
    end
  end
end
