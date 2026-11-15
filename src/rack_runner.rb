module Foobara
  class McpConnector < CommandConnector
    class RackRunner
      attr_accessor :mcp_connector

      def initialize(mcp_connector)
        self.mcp_connector = mcp_connector
      end

      def call(env)
        return forbidden unless origin_allowed?(env["HTTP_ORIGIN"])

        case env["REQUEST_METHOD"]
        when "POST" then post(env)
        when "DELETE" then delete(env["HTTP_MCP_SESSION_ID"])
        else method_not_allowed
        end
      end

      private

      def post(env)
        session_id = env["HTTP_MCP_SESSION_ID"]
        request = mcp_connector.prepare_request(env["rack.input"]&.read.to_s, session_id:, env:)

        if session_required?(request)
          return bad_request("Missing Mcp-Session-Id header") unless session_id
          return not_found("Unknown or expired session") unless request.session
        end

        body = mcp_connector.run_request(request).body

        if body
          headers = { "content-type" => "application/json" }
          headers["mcp-session-id"] = request.session_id if request.session_id && request.session
          [200, headers, [body]]
        else
          [202, {}, []]
        end
      end

      def delete(session_id)
        session_store = mcp_connector.session_store

        return method_not_allowed unless session_store
        return bad_request("Missing Mcp-Session-Id header") unless session_id

        if session_store.delete(session_id)
          [204, {}, []]
        else
          not_found("Unknown or expired session")
        end
      end

      def session_required?(request)
        mcp_connector.session_store && !request.error && !request.initialization?
      end

      def origin_allowed?(origin)
        allowed_origins = mcp_connector.allowed_origins

        allowed_origins.nil? || origin.nil? || allowed_origins.include?(origin)
      end

      def forbidden
        text_response(403, "Origin not allowed")
      end

      def bad_request(message)
        text_response(400, message)
      end

      def not_found(message)
        text_response(404, message)
      end

      def method_not_allowed
        [405, { "allow" => allowed_methods, "content-type" => "text/plain" }, ["Method not allowed"]]
      end

      def allowed_methods
        mcp_connector.session_store ? "POST, DELETE" : "POST"
      end

      def text_response(status, message)
        [status, { "content-type" => "text/plain" }, [message]]
      end
    end
  end
end
