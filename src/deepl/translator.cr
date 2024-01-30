require "json"
require "./utils/proxy"

module Deepl
  class ApiKeyError < Exception; end

  class RequestError < Exception; end

  class Translator
    API_URL_BASE = {% if env("DEEPL_API_PRO") %}
                     "https://api.deepl.com/v2"
                   {% else %}
                     "https://api-free.deepl.com/v2"
                   {% end %}
    API_URL_TRANSLATE = "#{API_URL_BASE}/translate"
    API_URL_DOCUMENT  = "#{API_URL_BASE}/document"

    def initialize
    end

    private def http_headers_for_text
      HTTP::Headers{
        "Authorization" => "DeepL-Auth-Key #{api_key}",
        "User-Agent"    => user_agent,
        "Content-Type"  => "application/x-www-form-urlencoded",
      }
    end

    private def http_headers_for_document(content_type)
      HTTP::Headers{
        "Authorization" => "DeepL-Auth-Key #{api_key}",
        "User-Agent"    => user_agent,
        "Content-Type"  => content_type,
      }
    end

    private def api_key
      ENV.fetch("DEEPL_API_KEY") { raise ApiKeyError.new }
    end

    private def user_agent
      {% if env("DEEPL_USER_AGENT") %}
        "{{ env("DEEPL_USER_AGENT") }}"
      {% else %}
        "deepl-cli/#{VERSION}"
      {% end %}
    end

    def translate(option)
      case option.sub_command
      when SubCmd::Document
        translate_document(option)
      when SubCmd::Text
        translate_text(option.input, option.target_lang, option.source_lang)
      end
    end

    def translate_text(text, target_lang, source_lang)
      params = HTTP::Params.build do |form|
        form.add("text", text)
        form.add("target_lang", target_lang)
        form.add("source_lang", source_lang) unless source_lang == "AUTO"
      end
      response = execute_post_request(API_URL_TRANSLATE, params, http_headers_for_text)
      parsed_response = JSON.parse(response.body)
      begin
        parsed_response.dig("translations", 0, "text")
      rescue
        raise RequestError.new("Error: #{parsed_response}")
      end
    end

    def translate_document(option)
      io = IO::Memory.new
      builder = HTTP::FormData::Builder.new(io)
      builder.field("target_lang", option.target_lang)
      builder.field("source_lang", option.source_lang) unless option.source_lang == "AUTO"
      file = File.open(option.input)
      filename = File.basename(option.input)
      metadata = HTTP::FormData::FileMetadata.new(filename: filename)
      headers = HTTP::Headers{"Content-Type" => "text/plain"}
      builder.file("file", file, metadata, headers)
      builder.finish

      response = execute_post_request(API_URL_DOCUMENT, io, http_headers_for_document(builder.content_type))
      parsed_response = JSON.parse(response.body)
      begin
        parsed_response.dig("document_id")
      rescue
        raise RequestError.new("Error: #{parsed_response}")
      end
    end

    private def execute_post_request(url = url, body = body, headers = headers)
      HTTP::Client.post(url, body: body, headers: headers)
    rescue ex
      raise RequestError.new("Error: #{ex.message}")
    end

    def request_languages(type)
      HTTP::Client.get("#{API_URL_BASE}/languages?type=#{type}", headers: http_headers_for_text)
    rescue ex
      raise RequestError.new("Error: #{ex.message}")
    end

    def target_languages
      response = request_languages("target")
      parse_languages_response(response)
    rescue ex
      raise RequestError.new("Error: #{ex.message}")
    end

    def source_languages
      response = request_languages("source")
      parse_languages_response(response)
    rescue ex
      raise RequestError.new("Error: #{ex.message}")
    end

    private def parse_languages_response(response)
      (Array(Hash(String, (String | Bool)))).from_json(response.body)
    end

    def usage
      response = request_usage
      parse_usage_response(response)
    rescue ex
      raise RequestError.new("Error: #{ex.message}")
    end

    private def request_usage
      HTTP::Client.get("#{API_URL_BASE}/usage", headers: http_headers_for_text)
    rescue ex
      raise RequestError.new("Error: #{ex.message}")
    end

    private def parse_usage_response(response)
      Hash(String, Int32).from_json(response.body)
    end
  end
end
