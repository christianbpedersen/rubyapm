module Api
  module V1
    # Receives gzipped MessagePack (or JSON) payloads from the ruby_apm agent.
    class IngestController < ActionController::API
      MAX_BODY = 20.megabytes
      MAX_INFLATED = 100.megabytes

      class TooLarge < StandardError; end

      def create
        raw = request.raw_post.to_s
        return head(:payload_too_large) if raw.bytesize > MAX_BODY

        app = App.for_ingest(bearer_token, nil)
        # Unknown keys are only worth decoding when they may self-register;
        # never inflate a body for a caller we would reject anyway.
        return head(:unauthorized) unless app || (Rails.configuration.x.auto_register_apps && bearer_token.present?)

        doc = decode(raw)
        app ||= App.for_ingest(bearer_token, doc["app"])
        return head(:unauthorized) unless app

        result = Ingestor.new(app, doc, bytes: raw.bytesize).call
        render json: { ok: true, rows: result.counts }, status: :accepted
      rescue TooLarge
        head :payload_too_large
      rescue Ingestor::InvalidPayload, MessagePack::MalformedFormatError, MessagePack::UnpackError, Zlib::Error,
             JSON::ParserError, EOFError => e
        render json: { ok: false, error: e.message }, status: :unprocessable_entity
      end

      private

      def bearer_token
        request.authorization.to_s[/\ABearer (.+)\z/, 1] || request.headers["X-RubyAPM-Key"] || request.headers["X-NewFenic-Key"]
      end

      def decode(raw)
        raw = inflate(raw) if request.headers["Content-Encoding"] == "gzip"
        doc = request.media_type == "application/json" ? JSON.parse(raw) : MessagePack.unpack(raw)
        raise Ingestor::InvalidPayload, "payload must be a map" unless doc.is_a?(Hash)
        doc
      end

      # Streams the gzip body and stops at MAX_INFLATED, so a small
      # compression bomb cannot exhaust memory.
      def inflate(raw)
        out = String.new(capacity: [raw.bytesize * 8, MAX_INFLATED].min, encoding: Encoding::BINARY)
        Zlib::GzipReader.wrap(StringIO.new(raw)) do |gz|
          while (chunk = gz.read(64.kilobytes))
            out << chunk
            raise TooLarge if out.bytesize > MAX_INFLATED
          end
        end
        out
      end
    end
  end
end
