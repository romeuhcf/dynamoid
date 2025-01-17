# frozen_string_literal: true

require 'spec_helper'

describe Dynamoid::Document do
  it 'initializes a new document' do
    address = Address.new

    expect(address.new_record).to be_truthy
    expect(address.attributes).to eq({})
  end

  it 'responds to will_change! methods for all fields' do
    address = Address.new
    expect(address).to respond_to(:id_will_change!)
    expect(address).to respond_to(:options_will_change!)
    expect(address).to respond_to(:created_at_will_change!)
    expect(address).to respond_to(:updated_at_will_change!)
  end

  it 'initializes a new document with attributes' do
    address = Address.new(city: 'Chicago')

    expect(address.new_record).to be_truthy

    expect(address.attributes).to eq(city: 'Chicago')
  end

  it 'initializes a new document with a virtual attribute' do
    address = Address.new(zip_code: '12345')

    expect(address.new_record).to be_truthy

    expect(address.attributes).to eq(city: 'Chicago')
  end

  it 'allows interception of write_attribute on load' do
    klass = new_class do
      field :city

      def city=(value)
        self[:city] = value.downcase
      end
    end
    expect(klass.new(city: 'Chicago').city).to eq 'chicago'
  end

  it 'ignores unknown fields (does not raise error)' do
    klass = new_class do
      field :city
    end

    model = klass.new(unknown_field: 'test', city: 'Chicago')
    expect(model.city).to eql 'Chicago'
  end

  describe '#initialize' do
    describe 'type casting' do
      let(:klass) do
        new_class do
          field :count, :integer
        end
      end

      it 'type casts attributes' do
        obj = klass.new(count: '101')
        expect(obj.attributes[:count]).to eql(101)
      end
    end
  end

  describe '.exist?' do
    it 'checks if there is a document with specified primary key' do
      address = Address.create(city: 'Chicago')

      expect(Address.exists?(address.id)).to be_truthy
      expect(Address.exists?('does-not-exist')).to be_falsey
    end

    it 'supports an array of primary keys' do
      address_1 = Address.create(city: 'Chicago')
      address_2 = Address.create(city: 'New York')
      address_3 = Address.create(city: 'Los Angeles')

      expect(Address.exists?([address_1.id, address_2.id])).to be_truthy
      expect(Address.exists?([address_1.id, 'does-not-exist'])).to be_falsey
    end

    it 'supports hash with conditions' do
      address = Address.create(city: 'Chicago')

      expect(Address.exists?(city: address.city)).to be_truthy
      expect(Address.exists?(city: 'does-not-exist')).to be_falsey
    end

    it 'checks if there any document in table at all if called without argument' do
      Address.create_table(sync: true)
      expect(Address.count).to eq 0

      expect { Address.create }.to change { Address.exists? }.from(false).to(true)
    end
  end

  it 'gets errors courtesy of ActiveModel' do
    address = Address.create(city: 'Chicago')

    expect(address.errors).to be_empty
    expect(address.errors.full_messages).to be_empty
  end

  context '.reload' do
    let(:address) { Address.create }
    let(:message) { Message.create(text: 'Nice, supporting datetime range!', time: Time.now.to_datetime) }
    let(:tweet) { tweet = Tweet.create(tweet_id: 'x', group: 'abc') }

    it 'reflects persisted changes' do
      address.update_attributes(city: 'Chicago')
      expect(address.reload.city).to eq 'Chicago'
    end

    it 'uses a :consistent_read' do
      expect(Tweet).to receive(:find).with(tweet.hash_key, range_key: tweet.range_value, consistent_read: true).and_return(tweet)
      tweet.reload
    end

    it 'works with range key' do
      expect(tweet.reload.group).to eq 'abc'
    end

    it 'uses dumped value of sort key to load document' do
      klass = new_class do
        range :activated_on, :date
        field :name
      end

      obj = klass.create!(activated_on: Date.today, name: 'Old value')
      obj2 = klass.where(id: obj.id, activated_on: obj.activated_on).first
      obj2.update_attributes(name: 'New value')

      expect { obj.reload }.to change {
        obj.name
      }.from('Old value').to('New value')
    end
  end

  it 'has default table options' do
    address = Address.create

    expect(address.id).to_not be_nil
    expect(Address.table_name).to eq 'dynamoid_tests_addresses'
    expect(Address.hash_key).to eq :id
    expect(Address.read_capacity).to eq 100
    expect(Address.write_capacity).to eq 20
    expect(Address.inheritance_field).to eq :type
  end

  it 'follows any table options provided to it' do
    tweet = Tweet.create(group: 12_345)

    expect { tweet.id }.to raise_error(NoMethodError)
    expect(tweet.tweet_id).to_not be_nil
    expect(Tweet.table_name).to eq 'dynamoid_tests_twitters'
    expect(Tweet.hash_key).to eq :tweet_id
    expect(Tweet.read_capacity).to eq 200
    expect(Tweet.write_capacity).to eq 200
  end

  shared_examples 'it has equality testing and hashing' do
    it 'is equal to itself' do
      expect(document).to eq document
    end

    it 'is equal to another document with the same key(s)' do
      expect(document).to eq same
    end

    it 'is not equal to another document with different key(s)' do
      expect(document).to_not eq different
    end

    it 'is not equal to an object that is not a document' do
      expect(document).to_not eq 'test'
    end

    it 'is not equal to nil' do
      expect(document).to_not eq nil
    end

    it 'hashes documents with the keys to the same value' do
      expect(document => 1).to have_key(same)
    end
  end

  context 'without a range key' do
    it_behaves_like 'it has equality testing and hashing' do
      let(:document) { Address.create(id: 123, city: 'Seattle') }
      let(:different) { Address.create(id: 456, city: 'Seattle') }
      let(:same) { Address.new(id: 123, city: 'Boston') }
    end
  end

  context 'with a range key' do
    it_behaves_like 'it has equality testing and hashing' do
      let(:document) { Tweet.create(tweet_id: 'x', group: 'abc', msg: 'foo') }
      let(:different) { Tweet.create(tweet_id: 'y', group: 'abc', msg: 'foo') }
      let(:same) { Tweet.new(tweet_id: 'x', group: 'abc', msg: 'bar') }
    end

    it 'is not equal to another document with the same hash key but a different range value' do
      document = Tweet.create(tweet_id: 'x', group: 'abc')
      different = Tweet.create(tweet_id: 'x', group: 'xyz')

      expect(document).to_not eq different
    end
  end

  context '#count' do
    it 'returns the number of documents in the table' do
      document = Tweet.create(tweet_id: 'x', group: 'abc')
      different = Tweet.create(tweet_id: 'x', group: 'xyz')

      expect(Tweet.count).to eq 2
    end
  end

  describe '.deep_subclasses' do
    it 'returns direct children' do
      expect(Car.deep_subclasses).to eq [Cadillac]
    end

    it 'returns grandchildren too' do
      expect(Vehicle.deep_subclasses).to include(Cadillac)
    end
  end
end
