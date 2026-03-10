# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0

require "minitest/autorun"
require "json"
require "ostruct"

# Pre-register stubs so require calls in lambda_handler.rb are no-ops
# We mark these gems as already loaded in Ruby's $LOADED_FEATURES
$LOADED_FEATURES << "pony"
$LOADED_FEATURES << "erb"
$LOADED_FEATURES << "opentelemetry/sdk"

# Stub OpenTelemetry
module OpenTelemetry
  def self.tracer_provider
    @tracer_provider ||= StubTracerProvider.new
  end

  class StubTracerProvider
    def tracer(_name)
      StubTracer.new
    end
  end

  class StubTracer
    def in_span(_name)
      yield StubSpan.new
    end
  end

  class StubSpan
    def set_attribute(_key, _value); end
  end
end

# Stub Pony
module Pony
  @last_mail = nil
  class << self
    attr_accessor :last_mail, :options
    def mail(opts)
      @last_mail = opts
    end
  end
end

# Stub Mail::TestMailer
module Mail
  class TestMailer
    def self.deliveries
      @deliveries ||= []
    end
  end
end

# Load the handler
require_relative "lambda_handler"

# Capture send_email calls for testing instead of actually sending
$send_email_calls = []
define_method(:send_email) do |data|
  $send_email_calls << data
end

class LambdaHandlerTest < Minitest::Test
  def setup
    $send_email_calls.clear
  end

  # --- Property 11: SQS message round-trip ---
  # **Validates: Requirements 6.1, 7.1**

  def test_single_record_preserves_email
    event = build_sqs_event([sample_order_body])
    result = handler(event: event, context: nil)

    assert_equal 200, result[:statusCode]
    assert_equal 1, $send_email_calls.size
    assert_equal "customer@example.com", $send_email_calls[0].email
  end

  def test_single_record_preserves_order_id
    event = build_sqs_event([sample_order_body])
    handler(event: event, context: nil)

    assert_equal "order-123", $send_email_calls[0].order["orderId"]
  end

  def test_single_record_preserves_shipping_tracking_id
    event = build_sqs_event([sample_order_body])
    handler(event: event, context: nil)

    assert_equal "track-456", $send_email_calls[0].order["shippingTrackingId"]
  end

  def test_single_record_preserves_shipping_cost
    event = build_sqs_event([sample_order_body])
    handler(event: event, context: nil)

    cost = $send_email_calls[0].order["shippingCost"]
    assert_equal "USD", cost["currencyCode"]
    assert_equal 5, cost["units"]
    assert_equal 0, cost["nanos"]
  end

  def test_single_record_preserves_items
    event = build_sqs_event([sample_order_body])
    handler(event: event, context: nil)

    items = $send_email_calls[0].order["items"]
    assert_equal 1, items.size
    assert_equal "prod-789", items[0]["productId"]
    assert_equal 2, items[0]["quantity"]
  end

  def test_multiple_records_each_processed
    body2 = sample_order_body.merge("email" => "other@example.com")
    body2 = body2.merge("order" => body2["order"].merge("orderId" => "order-999"))

    event = build_sqs_event([sample_order_body, body2])
    result = handler(event: event, context: nil)

    assert_equal 200, result[:statusCode]
    assert_equal 2, $send_email_calls.size
    assert_equal "customer@example.com", $send_email_calls[0].email
    assert_equal "other@example.com", $send_email_calls[1].email
    assert_equal "order-123", $send_email_calls[0].order["orderId"]
    assert_equal "order-999", $send_email_calls[1].order["orderId"]
  end

  def test_empty_records_returns_200
    event = { "Records" => [] }
    result = handler(event: event, context: nil)

    assert_equal 200, result[:statusCode]
    assert_equal 0, $send_email_calls.size
  end

  # --- Property 12: Email Lambda error propagation ---
  # **Validates: Requirements 7.3**

  def test_invalid_json_propagates_exception
    event = {
      "Records" => [
        { "body" => "not valid json{{{" }
      ]
    }

    assert_raises(JSON::ParserError) do
      handler(event: event, context: nil)
    end
  end

  def test_send_email_exception_propagates
    Object.define_method(:send_email) { |_data| raise RuntimeError, "SMTP connection failed" }

    event = build_sqs_event([sample_order_body])
    assert_raises(RuntimeError) do
      handler(event: event, context: nil)
    end
  ensure
    Object.define_method(:send_email) { |data| $send_email_calls << data }
  end

  def test_partial_batch_failure_propagates
    call_count = 0
    Object.define_method(:send_email) do |data|
      call_count += 1
      raise RuntimeError, "fail on second" if call_count == 2
      $send_email_calls << data
    end

    body2 = sample_order_body.merge("email" => "second@example.com")
    event = build_sqs_event([sample_order_body, body2])

    assert_raises(RuntimeError) do
      handler(event: event, context: nil)
    end
    assert_equal 1, $send_email_calls.size
  ensure
    Object.define_method(:send_email) { |data| $send_email_calls << data }
  end

  private

  def sample_order_body
    {
      "type" => "ORDER_CONFIRMATION",
      "email" => "customer@example.com",
      "order" => {
        "orderId" => "order-123",
        "shippingTrackingId" => "track-456",
        "shippingCost" => { "currencyCode" => "USD", "units" => 5, "nanos" => 0 },
        "items" => [
          { "productId" => "prod-789", "quantity" => 2, "cost" => { "currencyCode" => "USD", "units" => 10, "nanos" => 0 } }
        ]
      }
    }
  end

  def build_sqs_event(bodies)
    {
      "Records" => bodies.map { |b| { "body" => JSON.generate(b) } }
    }
  end
end
