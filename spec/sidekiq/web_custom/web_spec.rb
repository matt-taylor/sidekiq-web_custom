require 'sidekiq/web'
require 'sidekiq/util'
require 'rack/test'

RSpec.describe Sidekiq::Web do
  include Rack::Test::Methods

  let(:app) { described_class}
  let(:worker) { Sidekiq::Web::Worker }
  let(:queue) { Sidekiq::Queue.new(worker.sidekiq_options['queue']) }
  let(:job_count) { 10 }
  let(:max) { job_count }

  before do
    # We are not testing this here -- it requires a full application setup
    allow_any_instance_of(Sidekiq::Web::CsrfProtection).to receive(:session).and_return({})
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
    job_count.times { worker.perform_async }
    app.set(:session_secret, "foo")
  end

  describe 'queues' do
    subject { get '/queues' }

    it 'returns 200' do
      subject
      expect(last_response.status).to eq 200
    end
  end
end
