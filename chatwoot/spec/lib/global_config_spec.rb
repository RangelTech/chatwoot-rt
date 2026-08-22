require 'rails_helper'

describe GlobalConfig do
  subject(:trigger) { described_class }

  describe 'execute' do
    context 'when called with default options' do
      before do
        described_class.clear_cache
      end

      it 'hit DB for the first call' do
        expect(InstallationConfig).to receive(:find_by)
        described_class.get('test')
      end

      it 'get from cache for subsequent calls' do
        # this loads from DB
        described_class.get('test')

        # subsequent calls should not hit DB
        expect(InstallationConfig).not_to receive(:find_by)
        described_class.get('test')
      end

      it 'clears cache and fetch from DB next time, when clear_cache is called' do
        # this loads from DB and is cached
        described_class.get('test')

        # clears the cache
        described_class.clear_cache

        # should be loaded from DB
        expect(InstallationConfig).to receive(:find_by).with({ name: 'test' }).and_return(nil)
        described_class.get('test')
      end

      it 'reads several cached settings in one Redis round trip' do
        redis = instance_double(Redis)
        cache_keys = %w[ONE TWO].map { |key| "V1:GLOBAL_CONFIG:#{key}" }
        values = ['{"value":"one"}', '{"value":"two"}']

        allow($alfred).to receive(:with).and_yield(redis)
        expect(redis).to receive(:mget).with(*cache_keys).and_return(values)
        expect(InstallationConfig).not_to receive(:find_by)

        expect(described_class.get('ONE', 'TWO')).to include('ONE' => 'one', 'TWO' => 'two')
      end
    end
  end
end
