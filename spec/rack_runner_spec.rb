RSpec.describe Foobara::McpConnector::RackRunner do
  after { Foobara.reset_alls }

  let(:command_connector) { Foobara::McpConnector.new(**connector_options) }
  let(:connector_options) { {} }
  let(:connect_options) { {} }
  let(:command_class) do
    stub_class "ComputeExponent", Foobara::Command do
      inputs do
        base :integer, :required
        exponent :integer, :required
      end

      result :integer

      def execute
        base ** exponent
      end
    end
  end

  let(:tool_call_json) do
    JSON.generate(
      jsonrpc: "2.0", id: 1, method: "tools/call",
      params: { name: "ComputeExponent", arguments: { base: 2, exponent: 3 } }
    )
  end
  let(:initialize_json) do
    JSON.generate(
      jsonrpc: "2.0", id: 1, method: "initialize",
      params: {
        protocolVersion: "2025-03-26",
        clientInfo: { name: "Some Client", version: "1.0.0" },
        capabilities: {}
      }
    )
  end
  let(:notification_json) { JSON.generate(jsonrpc: "2.0", method: "notifications/initialized") }

  before do
    command_connector.connect(command_class, **connect_options)
  end

  def call(method, body: "", headers: {})
    status, response_headers, body_parts = command_connector.call(
      { "REQUEST_METHOD" => method, "rack.input" => StringIO.new(body) }.merge(headers)
    )

    [status, response_headers, body_parts.join]
  end

  def tool_result(body)
    JSON.parse(body)["result"]["content"].first["text"]
  end

  context "without a session store" do
    it "runs a tool call and responds with json" do
      status, headers, body = call("POST", body: tool_call_json)

      expect(status).to eq(200)
      expect(headers["content-type"]).to eq("application/json")
      expect(headers).to_not have_key("mcp-session-id")
      expect(tool_result(body)).to eq("8")
    end

    it "accepts notifications without a body" do
      expect(call("POST", body: notification_json)).to eq([202, {}, ""])
    end

    it "does not hand out a session id on initialize" do
      status, headers, = call("POST", body: initialize_json)

      expect(status).to eq(200)
      expect(headers).to_not have_key("mcp-session-id")
    end

    it "responds to invalid json with a json-rpc error" do
      status, _headers, body = call("POST", body: "{nope")

      expect(status).to eq(200)
      expect(JSON.parse(body)["error"]["code"]).to eq(-32_700)
    end

    it "responds to a request without a body with a json-rpc error" do
      status, _headers, body = command_connector.call({ "REQUEST_METHOD" => "POST" })

      expect(status).to eq(200)
      expect(JSON.parse(body.join)["error"]["code"]).to eq(-32_700)
    end

    it "does not allow DELETE" do
      status, headers, = call("DELETE", headers: { "HTTP_MCP_SESSION_ID" => "abc" })

      expect(status).to eq(405)
      expect(headers["allow"]).to eq("POST")
    end

    it "does not allow GET" do
      status, headers, = call("GET")

      expect(status).to eq(405)
      expect(headers["allow"]).to eq("POST")
    end
  end

  context "with allowed origins" do
    let(:connector_options) { { allowed_origins: ["https://claude.ai"] } }

    it "accepts an allowed origin" do
      expect(call("POST", body: tool_call_json, headers: { "HTTP_ORIGIN" => "https://claude.ai" }).first).to eq(200)
    end

    it "rejects any other origin" do
      status, = call("POST", body: tool_call_json, headers: { "HTTP_ORIGIN" => "https://evil.example" })

      expect(status).to eq(403)
    end

    it "accepts requests without an origin" do
      expect(call("POST", body: tool_call_json).first).to eq(200)
    end
  end

  context "with a session store" do
    let(:session_store) { Foobara::McpConnector::InMemorySessionStore.new }
    let(:connector_options) { { session_store: } }

    def initialize_session
      _status, headers, = call("POST", body: initialize_json)
      headers["mcp-session-id"]
    end

    it "hands out a session id on initialize" do
      session_id = initialize_session

      expect(session_id).to be_a(String)
      expect(session_store.find(session_id)).to be_a(Foobara::McpConnector::Session)
    end

    it "runs requests that carry a known session id" do
      status, headers, body = call(
        "POST", body: tool_call_json, headers: { "HTTP_MCP_SESSION_ID" => initialize_session }
      )

      expect(status).to eq(200)
      expect(headers["mcp-session-id"]).to be_a(String)
      expect(tool_result(body)).to eq("8")
    end

    it "requires a session id for requests other than initialize" do
      expect(call("POST", body: tool_call_json).first(2)).to eq([400, { "content-type" => "text/plain" }])
    end

    it "rejects an unknown session id so the client re-initializes" do
      status, = call("POST", body: tool_call_json, headers: { "HTTP_MCP_SESSION_ID" => "unknown" })

      expect(status).to eq(404)
    end

    it "still reports invalid json as a json-rpc error" do
      status, _headers, body = call("POST", body: "{nope")

      expect(status).to eq(200)
      expect(JSON.parse(body)["error"]["code"]).to eq(-32_700)
    end

    it "ends a session on DELETE" do
      session_id = initialize_session

      expect(call("DELETE", headers: { "HTTP_MCP_SESSION_ID" => session_id }).first).to eq(204)
      expect(call("DELETE", headers: { "HTTP_MCP_SESSION_ID" => session_id }).first).to eq(404)
      expect(call("POST", body: tool_call_json, headers: { "HTTP_MCP_SESSION_ID" => session_id }).first).to eq(404)
    end

    it "requires a session id to DELETE" do
      expect(call("DELETE").first).to eq(400)
    end

    it "does not allow GET" do
      status, headers, = call("GET")

      expect(status).to eq(405)
      expect(headers["allow"]).to eq("POST, DELETE")
    end
  end

  context "with an authenticator that reads the http request" do
    let(:connector_options) do
      { authenticator: -> { "owner" if env["HTTP_AUTHORIZATION"] == "Bearer secret" } }
    end
    let(:connect_options) { { requires_authentication: true } }

    it "runs the command when the request authenticates" do
      _status, _headers, body = call("POST", body: tool_call_json, headers: { "HTTP_AUTHORIZATION" => "Bearer secret" })

      expect(tool_result(body)).to eq("8")
    end

    it "refuses the command otherwise" do
      _status, _headers, body = call("POST", body: tool_call_json)

      expect(JSON.parse(body)["error"]["message"]).to eq("Unauthenticated")
    end

    it "authenticates each request in a batch" do
      batch_json = "[#{tool_call_json},#{tool_call_json.sub('"id":1', '"id":2')}]"

      _status, _headers, body = call("POST", body: batch_json, headers: { "HTTP_AUTHORIZATION" => "Bearer secret" })

      expect(JSON.parse(body).map { |response| response["result"]["content"].first["text"] }).to eq(["8", "8"])
    end
  end
end
