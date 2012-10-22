# encoding: utf-8
require "openssl"
require "base64"


class Manifest
  def initialize(attributes, &block)
    @attributes = Hash[attributes.map { |k, v| [k.to_s.downcase, v] }]

    unless block_given?
      raise ArgumentError, "manifest rules must be specified by a block, no block given"
    end

    instance_exec(&block)
  end

  attr_reader :attributes

  def validate
    failures = rules.each_with_object([]) do |rule, failures|
      value = attributes.fetch(rule[:name]) do
        failures << [:required, rule] if rule[:required]
        next
      end

      unless rule[:matcher] === value
        failures << [:matcher, rule]
      end
    end
  end

  def valid?
    (failures = validate).none?
  end

  def rules
    @rules ||= {}
  end

  def manifest
    [].tap do |manifest|
      manifest << attributes["method"].upcase
      manifest << attributes["md5"]
      manifest << attributes["content-type"]
      manifest << attributes["date"]
      normalized_headers.each do |(header, *values)|
        manifest << "#{header}:#{values.join(",")}"
      end
      manifest << attributes["filename"]
    end.join("\n")
  end

  def sign(access_key, secret_access_key)
    return unless valid?
    digest = OpenSSL::HMAC.digest("sha1", secret_access_key, manifest)
    signature = Base64.strict_encode64(digest)
    "AWS #{access_key}:#{signature}"
  end

  protected

  def normalized_headers
    attributes.select  { |property, _| property =~ /x-amz-/ }
              .map     { |(header, values)| [property.downcase, values] }
              .sort_by { |(header, _)| header }
  end

  def required(name, constraints = nil, options = {}, &block)
    matcher = if block_given? then block
    elsif constraints.is_a?(Regex)
      constraints.method(:===)
    elsif constraints.is_a?(String)
      constraints.method(:===)
    elsif constriants.is_a?(Array)
      constraints.method(:include?)
    end

    { name: name, matcher: matcher, options: options, required: true }.tap do |rule|
      rules << rule
    end
  end

  def optional(*args, &block)
    required(*args, &block).tap { |rule| rule[:required] = false }
  end
end