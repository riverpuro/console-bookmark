#!/usr/bin/env ruby
# coding: utf-8

require 'irb'
require 'fileutils'
require 'shellwords'

module Bookmarker
  extend Shellwords

  COOKIE_DIR = File.join(File.expand_path(File.dirname(__FILE__)), '.cookies')
  COOKIE_FILE = File.join(COOKIE_DIR, 'hatena.cookie')

  LOGIN_PATH = 'https://www.hatena.ne.jp/login'
  BASE_URL = 'http://b.hatena.ne.jp'

  module_function
  def curl(arg)
    `curl -s #{arg}`
  end

  def init
    FileUtils.mkdir_p(COOKIE_DIR)
  end

  def cleanup
    FileUtils.rm_rf(COOKIE_DIR)
  end

  def login(name, password)
    res = curl "-c #{COOKIE_FILE} -d name=#{name} -d password=#{password} #{LOGIN_PATH}"
    !res.match(/error-message/)
  end

  def login?
    res = curl "-b #{COOKIE_FILE} #{LOGIN_PATH}"
    !!res.match(/oauth-message/)
  end

  def bookmark_confirm(hatena_id, target_url)
    confirm_url = File.join BASE_URL, hatena_id, 'add.confirm'
    confirm_url += "?url=#{shellescape target_url}"

    res = curl "-b #{COOKIE_FILE} #{confirm_url}"

    rks   = $1 if res =~ /name="rks".*value="(\S+?)"/
    url   = $1 if res =~ /name="url".*value="(\S+?)"/
    from  = $1 if res =~ /name="from".*value="(\S+?)"/
    users = $1 if res =~ %r|<span>(\d+)</span>(?:\s*)users?|

    tags = res.scan(/class="tag".*?>(\S+?)</)
    tags.flatten!

    {:rks => rks, :url => url, :from => from, :users => users, :tags => tags}
  end

  def bookmark(hatena_id, comment, options = {})
    post_url = File.join BASE_URL, hatena_id, 'add.edit'
    res = curl "-L -b #{COOKIE_FILE} -d rks=#{shellescape options[:rks]} -d url=#{shellescape options[:url]} -d from=#{shellescape options[:from]} --data-urlencode comment=#{shellescape comment} #{post_url}"
    if res =~ /link.*rel="canonical".*href="(\S+?)"/
      $1
    else
      "fail?"
    end
  end

  def prompt(message)
    print "#{message}: "
    res = gets
    res.chomp
  end

  def secure_prompt(message)
    print "#{message}: "
    system 'stty -echo'
    res = gets
    system 'stty echo'
    res.chomp
  end
end


module User
  module_function
  def destroy
    FileUtils.rm_rf username_file if File.exists?(username_file)
  end

  def restore
    File.read username_file if File.exists?(username_file)
  end

  def username_file
    File.join(Bookmarker::COOKIE_DIR, 'username')
  end

  def serialize(name)
    File.open(username_file, 'wb') {|f| f.write name }
  end
end


def usage
  print <<-EOL
login:
  login with hatena_id and password.

logout:
  logout and delete cookie.

bookmark:
  bookmark.

login?:
  return login status.

me:
  return login user name.
  EOL
end

def login
  name     = Bookmarker.prompt('hatena id')
  password = Bookmarker.secure_prompt('password')

  puts "\nlogging in ..."

  if Bookmarker.login(name, password) and @me = name and User.serialize(name)
    'success'
  else
    'fail'
  end
end

def logout
  User.destroy
  Bookmarker.cleanup
  "logged out"
end

def bookmark
  url = Bookmarker.prompt('URL')

  confirmation = Bookmarker.bookmark_confirm(me, url)
  puts "#{confirmation[:users] || 0} users bookmark"
  unless (tags = confirmation[:tags]).empty?
    puts "tags: #{tags.join(', ')}"
  end

  comment = Bookmarker.prompt('comment')

  Bookmarker.bookmark(me, comment, confirmation)
end

def login?
  Bookmarker.login?
end

def me
  @me ||= User.restore
end

begin
  Bookmarker.init
  IRB.start
#ensure
#  logout
end
