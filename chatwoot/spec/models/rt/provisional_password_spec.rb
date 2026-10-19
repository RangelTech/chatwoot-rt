require 'rails_helper'

RSpec.describe Rt::ProvisionalPassword do
  let(:user) { create(:user) }

  it 'issues a password that works and flags the user until it is changed' do
    password = described_class.issue!(user)
    user.reload
    expect(user.valid_password?(password)).to be true
    expect(user.must_change_password?).to be true
    user.update!(password: 'Nova#Senha123', password_confirmation: 'Nova#Senha123')
    expect(user.reload.must_change_password?).to be false
  end

  it 'reissuing keeps the flag on' do
    described_class.issue!(user)
    described_class.issue!(user)
    expect(user.reload.must_change_password?).to be true
  end
end
