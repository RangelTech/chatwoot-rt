require 'rails_helper'

describe GlobalConfigService do
  subject(:trigger) { described_class }

  describe 'execute' do
    context 'when called with default options' do
      before do
        # to clear redis cache
        GlobalConfig.clear_cache
      end

      # it 'set default value if not found on db nor env var' do
      #   value = GlobalConfig.get('ENABLE_ACCOUNT_SIGNUP')
      #   expect(value['ENABLE_ACCOUNT_SIGNUP']).to eq nil

      #   described_class.load('ENABLE_ACCOUNT_SIGNUP', 'true')

      #   value = GlobalConfig.get('ENABLE_ACCOUNT_SIGNUP')
      #   expect(value['ENABLE_ACCOUNT_SIGNUP']).to eq 'true'
      #   expect(InstallationConfig.find_by(name: 'ENABLE_ACCOUNT_SIGNUP')&.value).to eq 'true'
      # end

      it 'get value from env variable even if present on DB' do
        with_modified_env ENABLE_ACCOUNT_SIGNUP: 'false' do
          expect(InstallationConfig.find_by(name: 'ENABLE_ACCOUNT_SIGNUP')&.value).to be_nil
          value = described_class.load('ENABLE_ACCOUNT_SIGNUP', 'true')
          expect(value).to eq 'false'
        end
      end

      it 'hydrates an existing blank setting from the runtime environment' do
        config = create(:installation_config, name: 'FB_APP_ID', value: nil, locked: false)

        with_modified_env FB_APP_ID: 'runtime-app-id' do
          expect(described_class.load('FB_APP_ID', '')).to eq 'runtime-app-id'
        end

        expect(config.reload.value).to eq 'runtime-app-id'
      end

      it 'keeps a cached false boolean without clearing all global config keys' do
        create(:installation_config, name: 'ENABLE_ACCOUNT_SIGNUP', value: 'false', locked: false)
        GlobalConfig.clear_cache
        expect(GlobalConfig.get('ENABLE_ACCOUNT_SIGNUP')['ENABLE_ACCOUNT_SIGNUP']).to be(false)

        expect(GlobalConfig).not_to receive(:clear_cache)
        expect(described_class.load('ENABLE_ACCOUNT_SIGNUP', 'true')).to be(false)
      end

      # it 'get value from DB if found' do
      #   # Set a value in db first and make sure this value
      #   # is not respected even when load() method is called with
      #   # another value.
      #   InstallationConfig.where(name: 'ENABLE_ACCOUNT_SIGNUP').first_or_create(value: 'true')
      #   described_class.load('ENABLE_ACCOUNT_SIGNUP', 'false')
      #   value = GlobalConfig.get('ENABLE_ACCOUNT_SIGNUP')
      #   expect(value['ENABLE_ACCOUNT_SIGNUP']).to eq 'true'
      # end
    end
  end
end
