#!/usr/bin/env ruby
# frozen_string_literal: true

require 'docopt'

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

require 'down'
require 'http'
require 'nokogiri'
require 'open-uri'

SLACK_TEAM = OPTS['<slack-team>'].freeze
SLACK_HEADERS = { "Cookie" => OPTS['<slack-cookie>'] }.freeze # must be string key for OpenURI

SLACKMOJI_BASE_URL = 'https://slackmojis.com'
SLACKMOJI_POPULAR_URL = "#{SLACKMOJI_BASE_URL}/emojis/popular"
SLACK_CUSTOMIZE_URL = "https://#{SLACK_TEAM}.slack.com/customize/emoji"
SLACK_EMOJI_API_URL = "https://#{SLACK_TEAM}.slack.com/api/emoji.add"

def slackmojifier
  api_token = fetch_api_token(OpenURI.open_uri(SLACK_CUSTOMIZE_URL, SLACK_HEADERS))
  Nokogiri::HTML.parse(OpenURI.open_uri(SLACKMOJI_POPULAR_URL)).css('a.downloader').each do |d|
    tempfile = Down.download("#{SLACKMOJI_BASE_URL}#{d['href']}")
    begin
      upload(d.text.strip.gsub(/\A:|:\Z/, ''), tempfile, api_token)
    ensure
      tempfile.close
      tempfile.unlink
    end
  end
end

def fetch_api_token(data)
  Nokogiri::HTML.parse(data).css('script').each do |e|
    result = e.text.match(/"api_token":"([a-z\-0-9]+)"/)
    return result.captures[0] unless result.nil?
  end
end

def upload(emoji_name, emoji_file, api_token)
  puts "Uploading: #{emoji_name}"
  result = HTTP.post(SLACK_EMOJI_API_URL, form: {
                       mode: 'data',
                       name: emoji_name,
                       token: api_token,
                       image: HTTP::FormData::File.new(emoji_file.path)
                     }).parse
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
