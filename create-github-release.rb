#!/usr/bin/env ruby
require 'optparse'

require 'octokit'

PROG_NAME = File.basename($PROGRAM_NAME)

DEFAULT_API_TOKEN_ENV_VAR = 'GITHUB_API_TOKEN'

Options = Struct.new(
  :api_token,
  :repo_slug,
  :tag_name,
  :assets,
  :target,
  :name,
  :release_notes,
  :draft,
  :prerelease
)

class ArgsParser
  REQUIRED_OPTIONS = %i[
    api_token
    repo_slug
    tag_name
  ].freeze

  def self.parse(options, ec = 0)
    args = Options.new
    # create our parser
    parser = OptionParser.new do |parser|
      parser.banner = "Usage: #{PROG_NAME} [options] <repo-slug> <tag-name> [asset1 ...]"

      parser.on('--api-token API-TOKEN', 'GitHub API token') do |value|
        args.api_token = value
      end

      parser.on('--api-token-env-var ENV-VAR', "Name of the environment variable containing the GitHub API token (defaults to #{DEFAULT_API_TOKEN_ENV_VAR})") do |value|
        args.api_token = ENV[value]
      end

      parser.on('--target TARGET', 'Target commit-ish for the git tag') do |value|
        args.target = value
      end

      parser.on('--name NAME', 'Name for the release') do |value|
        args.name = value
      end

      parser.on('--release-notes NOTES', 'Release notes') do |value|
        args.release_notes = value
      end

      parser.on('--draft') do
        args.draft = true
      end

      parser.on('--prerelease') do
        args.prerelease = true
      end

      parser.on_tail('-h', '--help', 'Print this help message') do
        warn parser
        exit ec
      end
    end
    # parse
    parser.parse!(options)
    args[:repo_slug] = options.shift
    args[:tag_name] = options.shift
    args[:assets] = options.map { |path| File.new(path, 'rb') }
    # fallback and defaults
    args.api_token ||= ENV[DEFAULT_API_TOKEN_ENV_VAR]
    # report any missing required options
    missing = REQUIRED_OPTIONS.select { |opt| args[opt].nil? }
    raise OptionParser::MissingArgument.new(missing.join(', ')) unless missing.empty?
    # return parsed options if all is well
    args
  end
end

begin
  options = ArgsParser.parse(ARGV)
rescue OptionParser::InvalidOption, OptionParser::MissingArgument
  warn $!.to_s
  ArgsParser.parse(%w[--help], 1)
end

client = Octokit::Client.new(access_token: options.api_token)
release = client.create_release(
  options.repo_slug,
  options.tag_name,
  {
    target_commitish: options.target,
    name: options.name,
    body: options.release_notes,
    draft: options.draft,
    prerelease: options.prerelease
  }.reject { |_, v| v.nil? }
)

begin
  options.assets.each do |asset|
    client.upload_asset(release[:url], asset)
  end
rescue StandardError
  # attempt to delete the release if we fail to upload an asset
  client.delete_release(release[:url])
  raise
end

