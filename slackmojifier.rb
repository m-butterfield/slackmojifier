#!/usr/bin/env ruby
# frozen_string_literal: true

require 'docopt'
require 'down'
require 'http'
require 'nokogiri'
require 'open-uri'

begin
  OPTS = Docopt.docopt <<~DOCOPT
    slackmojifier

    Import custom emoji from Slackmoji into Slack!

    Usage:
        ./slackmojifier.rb <slack-team> <slack-cookie>

    Options:
        -h --help     Show this screen.
  DOCOPT
rescue Docopt::Exit => e
  puts e.message
  exit(1)
end

SLACK_TEAM = OPTS['<slack-team>'].freeze
SLACK_COOKIE = OPTS['<slack-cookie>'].freeze

SLACKMOJI_BASE_URL = 'https://slackmojis.com'
SLACKMOJI_POPULAR_URL = "#{SLACKMOJI_BASE_URL}/emojis/popular"
SLACK_CUSTOMIZE_URL = "https://#{SLACK_TEAM}.slack.com/customize/emoji"
SLACK_API_BASE_URL = "https://#{SLACK_TEAM}.slack.com/api"
SLACK_EMOJI_ADD_URL = "#{SLACK_API_BASE_URL}/emoji.add"
SLACK_EMOJI_LIST_URL = "#{SLACK_API_BASE_URL}/emoji.list"

def slackmojifier
  api_token = fetch_api_token
  existing_emoji = fetch_existing_emoji(api_token)
  Nokogiri::HTML.parse(OpenURI.open_uri(SLACKMOJI_POPULAR_URL)).css('a.downloader').each do |d|
    name = d.text.strip.gsub(/\A:|:\Z/, '')
    if existing_emoji.include? name
      puts "emoji with name: #{name} already exists, skipping..."
      next
    end

    tempfile = Down.download("#{SLACKMOJI_BASE_URL}#{d['href']}")
    begin
      upload(name, tempfile, api_token)
    ensure
      tempfile.close
      tempfile.unlink
    end
  end
end

def fetch_api_token
  puts 'Fetching API token...'
  data = OpenURI.open_uri(SLACK_CUSTOMIZE_URL, { "Cookie" => SLACK_COOKIE }) # must be string key
  Nokogiri::HTML.parse(data).css('script').each do |e|
    result = e.text.match(/"api_token":"([a-z\-0-9]+)"/)
    return result.captures[0] unless result.nil?
  end
  puts 'Error: Could not fetch API token'
  exit(1)
end

def fetch_existing_emoji(api_token)
  puts 'Fetching existing emoji names...'
  result = HTTP.get(SLACK_EMOJI_LIST_URL, params: { token: api_token }).parse
  return result['emoji'].keys if result['ok']

  puts "ERROR: #{result['error']}"
  exit(1)
end

def upload(emoji_name, emoji_file, api_token)
  puts "Uploading: #{emoji_name}"
  resp = HTTP.post(SLACK_EMOJI_ADD_URL, form: {
                     mode: 'data',
                     name: emoji_name,
                     token: api_token,
                     image: HTTP::FormData::File.new(emoji_file.path)
                   })

  if resp.status == 429
    wait_time = resp.headers['retry-after']
    puts "Rate limited. Waiting for #{wait_time} seconds"
    sleep(wait_time)
    return upload(emoji_name, emoji_file, api_token)
  end

  result = resp.parse
  return if result['ok']

  error = result['error']
  if result['error'].include? 'error_name_taken'
    puts "Name already taken: #{emoji_name}"
    return
  end
  puts "ERROR: #{error}"
  exit(1)
end

slackmojifier
