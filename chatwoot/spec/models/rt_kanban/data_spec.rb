require 'rails_helper'

RSpec.describe 'RtKanban data (K1)' do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  def conversation_for(acc = account, box = inbox)
    create(:conversation, account: acc, inbox: box)
  end

  it 'creates one board per account with the four default stages and a single initial stage' do
    board = RtKanban::EnsureBoard.call(account)
    expect(RtKanban::EnsureBoard.call(account).id).to eq(board.id)
    expect(board.stages.pluck(:name)).to eq(['Novo', 'Em atendimento', 'Aguardando cliente', 'Concluído'])
    expect(board.stages.where(initial: true).count).to eq(1)
    expect(board.enabled).to be false
  end

  it 'creates exactly one card per conversation (idempotent) in the initial stage, in order, with an event' do
    first = conversation_for
    second = conversation_for
    c1 = RtKanban::EnsureCard.call(first)
    expect(RtKanban::EnsureCard.call(first).id).to eq(c1.id)
    c2 = RtKanban::EnsureCard.call(second)
    expect(c2.position).to be > c1.position
    expect(c1.stage).to eq(c1.board.initial_stage)
    expect(RtKanban::Event.where(action: 'created').count).to eq(2)
    expect(RtKanban::Card.where(conversation_id: first.id).count).to eq(1)
  end

  it 'gives two conversations of the same contact two cards' do
    contact = create(:contact, account: account)
    ci = create(:contact_inbox, contact: contact, inbox: inbox)
    a = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: ci)
    b = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: ci)
    expect([RtKanban::EnsureCard.call(a).id, RtKanban::EnsureCard.call(b).id].uniq.size).to eq(2)
  end

  it 'backfills missing cards without duplicating on a second run and reconciles to zero' do
    3.times { conversation_for }
    RtKanban::BackfillJob.perform_now(account.id)
    RtKanban::BackfillJob.perform_now(account.id)
    expect(RtKanban::Reconcile.call(account)).to eq(conversations: 3, cards: 3, missing: 0, duplicate: 0, cross_account: 0)
  end

  it 'keeps accounts isolated' do
    other = create(:account)
    RtKanban::EnsureCard.call(conversation_for)
    RtKanban::EnsureCard.call(conversation_for(other, create(:inbox, account: other)))
    expect(RtKanban::Reconcile.call(account)[:cards]).to eq(1)
    expect(RtKanban::Reconcile.call(other)[:cards]).to eq(1)
    expect(RtKanban::Board.where(account_id: [account.id, other.id]).count).to eq(2)
  end

  it 'rejects a card whose conversation belongs to another account' do
    board = RtKanban::EnsureBoard.call(account)
    other = create(:account)
    foreign = create(:conversation, account: other, inbox: create(:inbox, account: other))
    card = RtKanban::Card.new(account_id: account.id, board_id: board.id, stage_id: board.initial_stage.id,
                              conversation_id: foreign.id, position: 1024)
    expect(card).not_to be_valid
  end

  it 'records a structural event and removes the card when the conversation is destroyed' do
    conversation = conversation_for
    card = RtKanban::EnsureCard.call(conversation)
    conversation.destroy!
    expect(RtKanban::Card.where(id: card.id)).to be_empty
    event = RtKanban::Event.find_by(action: 'deleted')
    expect(event.conversation_id_snapshot).to eq(conversation.id)
    expect(event.card_id_snapshot).to eq(card.id)
  end

  it 'makes events immutable' do
    RtKanban::EnsureCard.call(conversation_for)
    event = RtKanban::Event.first
    expect { event.update!(action: 'moved') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { event.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'only auto-creates cards for new conversations once the board is enabled' do
    RtKanban::EnsureBoard.call(account)
    conversation = conversation_for
    RtKanban::ConversationListener.instance.conversation_created(
      Events::Base.new('conversation.created', Time.zone.now, conversation: conversation)
    )
    expect(RtKanban::Card.where(conversation_id: conversation.id)).to be_empty
    RtKanban::Board.find_by(account_id: account.id).update!(enabled: true)
    RtKanban::ConversationListener.instance.conversation_created(
      Events::Base.new('conversation.created', Time.zone.now, conversation: conversation)
    )
    expect(RtKanban::Card.where(conversation_id: conversation.id).count).to eq(1)
  end
end
