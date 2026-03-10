# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0

require "json"
require "ostruct"
require "pony"
require "erb"

require "opentelemetry/sdk"

# Configure Pony to use test mode (no real SMTP in Lambda)
Pony.options = { via: :test }

# Minimal tracer for send_email compatibility
def send_email(data)
  tracer = OpenTelemetry.tracer_provider.tracer("email")
  tracer.in_span("send_email") do |span|
    template_path = File.join(__dir__, "views", "confirmation.erb")
    template = File.read(template_path)
    confirmation_content = ERB.new(template).result_with_hash(order: data.order)

    Pony.mail(
      to:      data.email,
      from:    "noreply@example.com",
      subject: "Your confirmation email",
      body:    confirmation_content,
      via:     :test
    )

    Mail::TestMailer.deliveries.clear

    span.set_attribute("app.email.recipient", data.email)
    puts "Order confirmation email sent to: #{data.email}"
  end
end

def handler(event:, context:)
  event["Records"].each do |record|
    body = JSON.parse(record["body"])
    send_email(
      OpenStruct.new(
        email: body["email"],
        order: OpenStruct.new(body["order"])
      )
    )
  end
  { statusCode: 200 }
end
