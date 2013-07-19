#!/usr/bin/env ruby
# Copyright 2013, Nathan Milford
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
require 'logger'
require 'sinatra'
require 'mail'
require 'json'
require 'pp'

knife_bin = `which knife`.chomp
git_bin   = `which git`.chomp

if knife_bin.empty?
  puts "Could not locate knife binary, exiting."
  abort
elsif git_bin.empty?
  puts "Could not locate git binary, exiting."
  abort
end

configure do
  set :bind,      "0.0.0.0"
  set :port,      31335
  set :repo,      "chef-repo"
  set :url,       "git@github.com:YOURREPO/#{settings.repo}.git"
  set :target,    "/var/tmp/checkout/"
  set :deploylog, "/var/tmp/chefdeploy.log"
  set :knife_bin, knife_bin
  set :git_bin,   git_bin
  set :mail_from, "Chef Deploy Status <alerts@example.com>"
  set :mail_cc,   "automation@example.com"
end

before do
  @log = Logger.new(settings.deploylog, 0, 100 * 1024 * 1024)
  @log.level = Logger::WARN

  Mail.defaults do
    delivery_method :smtp, {
      :address   => "smtp.example.com",
      :port      => 587,
      :domain    => "example.com",
      :user_name => "username",
      :password  => "passwd",
      :authentication => 'plain',
      :enable_starttls_auto => true
    }
  end
end

def upload_to_chef(cookbook)
  knife_status = []

  @log.info("*** Uploading #{cookbook} to Chef.")
  knife_status << `#{settings.knife_bin} cookbook upload #{cookbook} -o #{settings.target}#{settings.repo}/cookbooks`

  if $?.to_i != 0
    @log.fatal("*** Error uploading #{cookbook} to Chef.")
    knife_status << 1
  else
    knife_status << 0
  end

  @log.debug(knife_status.inspect)

  return knife_status
end

def check_out_cookbook(cookbook)

  git_status = []

  if File.directory?(settings.target)
    FileUtils.rm_rf(settings.target)
    @log.warn("*** Removing previous deploy directory at #{settings.target}.")
  end

  @log.info("*** Creating deploy directory at #{settings.target}.")
  FileUtils.mkdir_p(settings.target)

  @log.info("*** Cloning at #{settings.url} to #{settings.target}#{settings.repo}.")
  git_status << `#{settings.git_bin} clone #{settings.url} #{settings.target}#{settings.repo}`

  if $?.to_i != 0
    @log.fatal("*** Error cloning #{settings.url}.")
    git_status << 1
  else
    git_status << 0
  end

  @log.debug(git_status.inspect)

  return git_status
end

def notify_comitter(comitter, cookbook, git_status, knife_status)
  mail_cc   = settings.mail_cc
  mail_from = settings.mail_from

  if git_status[1] != 0
    subj = "[CHEFDEPLOY] Git checkout of #{cookbook} failed, could not deploy."
    msg  = "Git checkout of #{cookbook} from #{settings.url} failed.\n\n, Git command output:\n\n #{git_status[0]}."
  elsif knife_status[1] != 0
    subj = "[CHEFDEPLOY] Knife upload of #{cookbook} failed, could not deploy."
    msg  = "Knife upload of #{cookbook} failed.\n\n, Knife command output:\n\n #{knife_status[0]}."
  else
    subj = "[CHEFDEPLOY] Chef Deploy of #{cookbook} was a success."
    msg  = "Well done!\n\n Knife command output:\n\n #{knife_status[0]}."
  end

  @log.debug(subj.inspect)
  @log.debug(msg.inspect)

  @log.info("Sending notification email to #{comitter}")
  mail = Mail.deliver do
    to      comitter
    cc      mail_cc
    from    mail_from
    subject subj
    text_part do
      body msg
    end
  end
end

def cleanup()
  if File.directory?(settings.target)
    @log.info("*** Cleaning up deploy directory at #{settings.target}.")
    FileUtils.rm_rf(settings.target)
  end
end

post '/chefdeploy' do
  push = JSON.parse(params[:payload])
  push['commits'].each do |commit|
    if commit['message'] =~ /#chefdeploy:([\w\-]+)/
      cookbooks = $1.split(",")
      cookbooks.each do |cookbook|
        @log.info("Processing #chefdeploy of #{cookbook} by #{commit['committer']['email']}")
        git_status = check_out_cookbook(cookbook)
        knife_status = upload_to_chef(cookbook)
        notify_comitter(commit['committer']['email'], cookbook, git_status, knife_status)
        cleanup()
      end
    end
  end
  return nil
end
