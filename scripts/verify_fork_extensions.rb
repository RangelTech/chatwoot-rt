#!/usr/bin/env ruby
# frozen_string_literal: true

require 'pathname'
require 'yaml'

REPOSITORY_ROOT = Pathname.new(__dir__).join('..').realpath
CHATWOOT_ROOT = REPOSITORY_ROOT.join('chatwoot')
MANIFEST_PATH = CHATWOOT_ROOT.join('fork_extensions.yml')
VALID_STATUSES = %w[active planned].freeze

def fail_with(errors, message)
  errors << message
end

def safe_relative_path(path, errors, extension_id)
  candidate = Pathname.new(path)
  if candidate.absolute? || candidate.each_filename.any? { |part| part == '..' }
    fail_with(errors, "#{extension_id}: unsafe relative path #{path.inspect}")
    return false
  end

  true
end

def verify_path(path, errors, extension_id)
  return unless safe_relative_path(path, errors, extension_id)

  fail_with(errors, "#{extension_id}: missing #{path}") unless CHATWOOT_ROOT.join(path).file?
end

def verify_marker(path, marker, errors, extension_id)
  return unless safe_relative_path(path, errors, extension_id)

  target = CHATWOOT_ROOT.join(path)
  unless target.file?
    fail_with(errors, "#{extension_id}: missing marker target #{path}")
    return
  end

  fail_with(errors, "#{extension_id}: marker not found in #{path}: #{marker.inspect}") unless target.read.include?(marker)
end

manifest = YAML.safe_load(MANIFEST_PATH.read, aliases: false)
errors = []

unless manifest.is_a?(Hash) && manifest['schema_version'] == 1 && manifest['extensions'].is_a?(Array)
  abort "Invalid manifest: #{MANIFEST_PATH} must define schema_version: 1 and extensions."
end

extension_ids = manifest['extensions'].map { |extension| extension['id'] }
fail_with(errors, 'manifest: extension ids must be unique') if extension_ids.uniq.length != extension_ids.length

manifest['extensions'].each do |extension|
  id = extension['id']
  status = extension['status']
  unless id.is_a?(String) && !id.empty?
    fail_with(errors, 'manifest: every extension needs a non-empty id')
    next
  end
  unless VALID_STATUSES.include?(status)
    fail_with(errors, "#{id}: status must be one of #{VALID_STATUSES.join(', ')}")
    next
  end

  if status == 'planned'
    puts "SKIP  #{id} (planned)"
    next
  end

  Array(extension['required_paths']).each { |path| verify_path(path, errors, id) }
  Array(extension['touchpoints']).each { |path| verify_path(path, errors, id) }
  (extension['markers'] || {}).each { |path, marker| verify_marker(path, marker, errors, id) }
  puts "PASS  #{id}"
end

if errors.empty?
  puts "Fork extension contract is valid (#{manifest['extensions'].length} entries)."
  exit 0
end

warn "Fork extension contract failed:"
errors.each { |error| warn "- #{error}" }
exit 1
