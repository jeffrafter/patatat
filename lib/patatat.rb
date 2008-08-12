require 'rubygems'
require 'time'
require 'cgi'
require 'yaml'
require File.expand_path(File.dirname(__FILE__)) + '/../lib/tweeter'

# Monkeypatch some append action since I couldn't get normal array appends to work with fsdb arrays
class FSDB::Database
  def append(database_path, element)
    self[database_path] = [] if self[database_path].nil?
    array = self[database_path]
    array << element
    self[database_path] = array
  end
end

class Patatat < Tweeter
  attr_accessor :botname, :database_path, :last_processed_at

  def initialize(username,password)
    super(username, password)
    @database = FSDB::Database.new("#{PATATAT_ROOT}/database/")
    @last_processed_at = @database['last_processed_at']
    Dir.mkdir("#{PATATAT_ROOT}/yoke/.theyoke") unless File.directory?("#{PATATAT_ROOT}/yoke/.theyoke")
  end

  def reset
    @last_processed_at = nil
  end

  def send_rss_updates(screen_name)
    Tweeter.yell "Checking for rss updates for #{screen_name}:"
    yoke_command = "./bin/theyoke.pl --columns=150 --username=#{screen_name} --configdir=#{PATATAT_ROOT}/yoke/.theyoke" # This is dangerous! - imagine nefarious screen names
    Tweeter.yell yoke_command
    rss_update = `#{yoke_command}`
    Tweeter.yell rss_update
    rss_update.split("\n").each{|headline|

      # Lets maximize our use of 140 characters:
      headline.gsub!(/  +/," ")
      headline.gsub!(/ : /,": ")
      headline.gsub!(/ - /,"-")
      headline.gsub!(/ \/ /,"/")
      $shortcuts["shortcuts"].each{|site,settings|
        headline.gsub!(/#{settings["regex"]}/,settings["replacement"])
      }
      # Camel case no spaces FTW? CamelCaseNoSpacesFTW?:
      # "There was more chaos".gsub(/ (.)/){|match| match.upcase}.gsub(/ /,"")
      headline = headline.gsub(/ (.)/){|match| match.upcase}.gsub(/ /,"") if headline.length > 120 # Use camelcase if it seems like we can make the whole thing fit, otherwise truncate
      message_to_send = headline[0..120] #truncate but leave room for twitter specific stuff
      send_direct_message(screen_name, message_to_send) unless headline.empty? or @database["#{screen_name}/messages_sent"].include?(message_to_send)
    }
  end

  def process
    Tweeter.yell "Processing... #{Time.now.to_s}"

    #screen_names = @database.browse{|object| object}.collect{|object|object.chop if object.match(/\//)}.compact #Finds all of the screen_names in the database
    friends.each{|screen_name|
      send_rss_updates(screen_name)
    }

    processing_timestamp = CGI.escape(Time.now.httpdate)
    friends_needing_following = unfollowed_friends_screenames
    new_messages = get_direct_messages(@last_processed_at)
    @last_processed_at = processing_timestamp
    @database['last_processed_at'] = @last_processed_at

    friends_needing_following.each{|friend_needing_following|
      Tweeter.yell "Found new follower: #{friend_needing_following}"
      new_follower(friend_needing_following)
    }

    new_messages.reverse.each{|message|
      process_message(message['text'], message['sender_screen_name'])
    }

    rescue => exception
      Tweeter.yell $!
      Tweeter.yell exception.backtrace
  end

  def process_message(message, screen_name)
    case message
      when /(http:\/\/.+)/i
        send_direct_message(screen_name, "you will receive an sms whenever '#{$1}' is updated")
        subscribe(screen_name, $1)
      when /help/i
        send_help_message(screen_name)
      when /remove (.+)/i
        remove(screen_name,$1)
      when /show feeds/i
        send_direct_message(screen_name, feed_list_compact(screen_name).join(" |"))
      else
        $shortcuts["shortcuts"].each{|shortcut, settings|
          next unless settings["url"]
          subscribe_shortcut(screen_name, $1, setting["url"]) if message.match(/#{shortcut} (.+)/)
        }
    end
  end


  def send_help_message(screen_name)
    help_string = ""
    $shortcuts["shortcuts"].each{|shortcut, settings|
      next unless settings["url"]
      help_string += "Add #{shortcut} feed: d #{@username} #{shortcut} topic. "
    }
    help_string += "Add rss: d #{@username} http://... . Remove: d #{@username} remove topic. Show current: d #{@username} show feeds."
    send_direct_message(screen_name, help_string)
  end

  def subscribe_shortcut(screen_name, search_term, url)
    subscribe(screen_name, url.gsub(/SEARCH_TERM/, search_term))
  end

  def subscribe(screen_name, feed)
    yoke_screen_name_dir = ".theyoke/#{screen_name}"
    Dir.mkdir(yoke_screen_name_dir) unless File.directory?(yoke_screen_name_dir)
    yoke_feeds_file = yoke_screen_name_dir + "/feeds"
    file = File.open(yoke_feeds_file, File::WRONLY|File::APPEND|File::CREAT)
    file.puts(feed)
    file.close
    send_rss_updates(screen_name)
  end

  def remove(screen_name, feed_to_remove)
    yoke_feeds_file = ".theyoke/#{screen_name}/feeds"
    File.open(yoke_feeds_file, 'r+') do |file|   # open file for update
      lines = file.readlines                   # read into array of lines
      lines.each do |line|                    # modify lines
        line = "" if line.match(/#{feed_to_remove}/)
        send_direct_message(screen_name, "Removed #{feed_to_remove}")
      end
      lines.uniq!
      file.pos = 0                             # back to start
      file.print lines                         # write out modified lines to original file
      file.truncate(file.pos)                     # truncate to new length
    end                                       # file is automatically close
  end

  def feed_list(screen_name)
    yoke_feeds_file = ".theyoke/#{screen_name}/feeds"
    File.open(yoke_feeds_file).collect{|feed|feed}
  end

  def feed_list_compact(screen_name)
    # Try and give a short representation otherwise use the feed
    feed_list(screen_name).collect{|feed|
      puts "#{feed}"
      $shortcuts["shortcuts"].collect{|shortcut, settings|
        next unless settings["url"]
        puts settings["url"]
        regex = settings["url"].gsub(/SEARCH_TERM/, "(.*)")
        "#{shortcut} #{$1}" if feed.match(/#{regex}/)
      }.compact.first rescue feed
    }.flatten
  end

  def send_direct_message(recipient, message)
    super(recipient, message)
    @database.append("#{recipient}/messages_sent", message)
  end

  def messages_sent(screen_name)
     @database["#{screen_name}/messages_sent"]
  end

  def new_follower(screen_name)
    follow(screen_name)
    send_direct_message(screen_name, "Welcome to #{@username}, send 'd #{@username} help' for more information")
  end

end