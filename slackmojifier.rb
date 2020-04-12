# frozen_string_literal: true

require 'down'
require 'http'
require 'nokogiri'
require 'open-uri'

class Slackmojifier

  SLACKMOJI_BASE_URL = 'https://slackmojis.com'

  def initialize(slack_team, slack_cookie)
    @slack_team = slack_team
    @api_token = fetch_api_token(slack_cookie)
    slack_api_base_url = "https://#{@slack_team}.slack.com/api"
    @slack_emoji_add_url = "#{slack_api_base_url}/emoji.add"
    @slack_emoji_list_url = "#{slack_api_base_url}/emoji.list"
    @existing_emoji = fetch_existing_emoji
  end

  def copy_emojis(path: '/emojis/popular')
    url = SLACKMOJI_BASE_URL + path
    puts "Copying emojis from #{url} to #{@slack_team}'s Slack"
    Nokogiri::HTML.parse(OpenURI.open_uri(url)).css('a.downloader').each do |d|
      copy_emoji(d.text.strip.gsub(/\A:|:\Z/, ''), SLACKMOJI_BASE_URL + d['href'])
    end
    puts 'Done!'
  end

  def copy_emoji(name, url)
    if @existing_emoji.include? name
      puts "emoji with name: #{name} already exists, skipping..."
      return
    end

    tempfile = Down.download(url)
    begin
      upload_emoji(name, tempfile.path)
    ensure
      tempfile.close
      tempfile.unlink
    end

    @existing_emoji.add(name)
  end

  def upload_emoji(emoji_name, file_path)
    puts "Uploading: #{emoji_name}"
    resp = HTTP.post(
      @slack_emoji_add_url,
      form: {
        mode: 'data',
        name: emoji_name,
        token: @api_token,
        image: HTTP::FormData::File.new(file_path)
      }
    )

    if resp.status == 429
      wait_time = resp.headers['retry-after']
      puts "Rate limited. Waiting for #{wait_time} seconds"
      sleep(wait_time.to_i)
      return upload_emoji(emoji_name, file_path)
    end

    check_upload_error(resp.parse, emoji_name)
  end

  def check_upload_error(result, emoji_name)
    return if result['ok']

    error = result['error']
    if result['error'].include? 'error_name_taken'
      puts "Name already taken: #{emoji_name}"
      return
    end
    puts "ERROR: #{error}"
    exit(1)
  end

  def fetch_api_token(slack_cookie)
    puts 'Fetching API token...'
    url = "https://#{@slack_team}.slack.com/customize/emoji"
    opts = { "Cookie" => slack_cookie } # "Cookie" must be string key here
    Nokogiri::HTML.parse(OpenURI.open_uri(url, opts)).css('script').each do |e|
      result = e.text.match(/"api_token":"([a-z\-0-9]+)"/)
      return result.captures[0] unless result.nil?
    end
    puts 'Error: Could not fetch API token'
    exit(1)
  end

  def fetch_existing_emoji
    puts 'Fetching existing emoji names...'
    result = HTTP.get(@slack_emoji_list_url, params: { token: @api_token }).parse
    return result['emoji'].keys.to_set if result['ok']

    puts "ERROR: #{result['error']}"
    exit(1)
  end
end
