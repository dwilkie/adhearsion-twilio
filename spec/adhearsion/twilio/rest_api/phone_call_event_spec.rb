require 'spec_helper'

describe Adhearsion::Twilio::RestApi::PhoneCallEvent do
  include EnvHelpers

  describe "#notify!", :vcr => false do
    let(:stanza) { build_rayo_event_stanza }
    let(:rayo_event_namespace) { "urn:xmpp:rayo:1" }
    let(:event) { Adhearsion::Rayo::RayoNode.from_xml(parse_stanza(stanza).root, target_call_id, '1') }
    let(:basic_auth_credentials) { "user:secret" }
    let(:target_call_id) { "3a05f57f-c664-4986-b619-44ec0a2fd60c" }
    let(:variable_uuid) { target_call_id }
    let(:asserted_phone_call_id) { variable_uuid }

    subject { described_class.new(:event => event) }

    let(:phone_call_events_url) {
      "https://#{basic_auth_credentials}@somleng.example.com/api/admin/phone_calls/:phone_call_id/phone_call_events"
    }

    let(:response_status) { 201 }

    let(:phone_call_event_url) {
      interpolate_phone_call_events_url(
        :phone_call_id => asserted_phone_call_id
      )
    }

    def setup_scenario
      stub_env(:ahn_twilio_rest_api_phone_call_events_url => phone_call_events_url)
      stub_request(:post, phone_call_event_url).to_return(:status => response_status) if phone_call_events_url
      subject.notify!
    end

    before do
      setup_scenario
    end

    def parse_stanza(xml)
      Nokogiri::XML.parse(xml, nil, nil, Nokogiri::XML::ParseOptions::NOBLANKS)
    end

    def interpolate_phone_call_events_url(interpolations = {})
      event_url = phone_call_events_url.dup
      interpolations.each do |interpolation, value|
        event_url.sub!(":#{interpolation}", value.to_s)
      end
      event_url.sub!("#{basic_auth_credentials}@", "")
      event_url
    end

    def rayo_event_stanza_headers
      {"variable-uuid" => variable_uuid}
    end

    def rayo_event_stanza_children
      rayo_event_stanza_children = []
      rayo_event_stanza_headers.each do |key, value|
        rayo_event_stanza_children << {
          :element_type => :header,
          :element_attributes => [
            {
              :name => key,
              :value => value
            }
          ]
        }
      end
      rayo_event_stanza_children
    end

    def build_rayo_event_stanza
      children_xml = []
      rayo_event_stanza_children.each do |child|
        attributes = [child[:element_type]]
        child[:element_attributes].each do |element_attribute|
          element_attribute.each do |key, value|
            attributes << "#{key}=\"#{value}\""
          end
        end

        children_xml << "<#{attributes.join(' ')} />"
      end

      <<-MESSAGE
        <#{rayo_event_type} xmlns="#{rayo_event_namespace}">
          #{children_xml.join("\n")}
        </#{rayo_event_type}>
      MESSAGE
    end

    def asserted_notify_request_body
      {:type => asserted_phone_call_event_type.to_s}
    end

    def assert_notify!
      expect(WebMock).to have_requested(
        :post, phone_call_event_url
      ).with { |request|
        expect(request.headers["Authorization"]).to eq("Basic #{Base64.strict_encode64(basic_auth_credentials).chomp}")
        request_params = WebMock.request_params(request)
        asserted_notify_request_body.each do |asserted_key, asserted_value|
          expect(request_params[asserted_key.to_s]).to eq(asserted_value.to_s)
        end
      }
    end

    context "#event => Adhearsion::Event::Ringing" do
      let(:asserted_phone_call_event_type) { :ringing }
      let(:rayo_event_type) { :ringing }
      it { assert_notify! }
    end

    context "#event => Adhearsion::Event::Answered" do
      let(:asserted_phone_call_event_type) { :answered }
      let(:rayo_event_type) { :answered }
      it { assert_notify! }
    end

    context "#event => Adhearsion::Event::Complete" do
      let(:rayo_event_type) { :complete }
      let(:rayo_event_namespace) { "urn:xmpp:rayo:ext:1" }

      def rayo_event_stanza_headers
        {}
      end

      context "recording_complete" do
        let(:complete_namespace) { "urn:xmpp:rayo:record:complete:1" }
        let(:recording_duration) { "14440" }
        let(:recording_size) { "0" }
        let(:recording_uri) { "file:///var/lib/freeswitch/recordings/2f65c536-47f8-4fb4-9565-49677cf338c6-2.wav" }

        def rayo_event_stanza_children
          super << {
            :element_type => "recording",
            :element_attributes => [
              {
                "xmlns" => complete_namespace,
                "uri" => recording_uri,
                :duration => recording_duration,
                :size => recording_size
              }
            ]
          }
        end

        let(:asserted_phone_call_event_type) { :recording_completed }
        let(:asserted_recording_duration) { recording_duration }
        let(:asserted_recording_size) { recording_size }
        let(:asserted_recording_uri) { recording_uri }

        def asserted_notify_request_body
          super.merge(
            :recording_duration => asserted_recording_duration,
            :recording_size => asserted_recording_size,
            :recording_uri => asserted_recording_uri
          )
        end

        it { assert_notify! }
      end

      context "fax_complete" do
        let(:complete_namespace) { "urn:xmpp:rayo:fax:complete:1" }

        def assert_notify!
          expect(WebMock).not_to have_requested(
            :post, phone_call_event_url
          )
        end

        it { assert_notify! }
      end
    end

    context "#event => Adhearsion::Event::End" do
      let(:asserted_phone_call_event_type) { :completed }
      let(:rayo_event_type) { :end }
      let(:header_sip_term_status) { "200" }
      let(:header_answer_epoch) { "1478050584" }

      let(:asserted_sip_term_status) { header_sip_term_status }
      let(:asserted_answer_epoch) { header_answer_epoch }

      def rayo_event_stanza_headers
        super.merge(
          "variable-sip_term_status" => header_sip_term_status,
          "variable-answer_epoch" => header_answer_epoch,
        )
      end

      def rayo_event_stanza_children
        super << {
          :element_type => :timeout,
          :element_attributes => [
            {
              "platform-code" => "18"
            }
          ]
        }
      end

      def asserted_notify_request_body
        super.merge(
          :sip_term_status => asserted_sip_term_status,
          :answer_epoch => asserted_answer_epoch
        )
      end

      it { assert_notify! }
    end
  end
end
