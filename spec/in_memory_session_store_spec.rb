RSpec.describe Foobara::McpConnector::InMemorySessionStore do
  let(:store) { described_class.new(ttl:, clock:) }
  let(:ttl) { 10 }
  let(:now) { [100.0] }
  let(:clock) { -> { now.first } }
  let(:session) { Foobara::McpConnector::Session.new({ clientInfo: { name: "x" } }) }

  def advance(seconds)
    now[0] += seconds
  end

  describe "#create" do
    it "returns a unique id" do
      id = store.create(session)
      other_id = store.create(Foobara::McpConnector::Session.new({}))

      expect(id).to be_a(String)
      expect(id).to_not eq(other_id)
    end

    it "prunes expired sessions" do
      store.create(session)
      advance(11)
      store.create(Foobara::McpConnector::Session.new({}))

      expect(store.size).to eq(1)
    end
  end

  describe "#find" do
    it "returns the session" do
      id = store.create(session)

      expect(store.find(id)).to be(session)
    end

    it "returns nil for an unknown id" do
      expect(store.find("nope")).to be_nil
    end

    it "expires sessions after ttl seconds without activity" do
      id = store.create(session)
      advance(11)

      expect(store.find(id)).to be_nil
      expect(store.size).to eq(0)
    end

    it "extends the session's life on each access" do
      id = store.create(session)
      advance(8)
      store.find(id)
      advance(8)

      expect(store.find(id)).to be(session)
    end
  end

  describe "#delete" do
    it "removes the session and reports whether it existed" do
      id = store.create(session)

      expect(store.delete(id)).to be(true)
      expect(store.find(id)).to be_nil
      expect(store.delete(id)).to be(false)
    end
  end

  context "with default options" do
    let(:store) { described_class.new }

    it "uses a one hour ttl and a monotonic clock" do
      expect(store.ttl).to eq(3600)
      expect(store.clock.call).to be_a(Float)
    end
  end
end
